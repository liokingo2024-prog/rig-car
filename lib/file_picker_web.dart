// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'model_data.dart';

PickedFile? mockPickedFileForTest;

Future<PickedFile?> pickModelFile() async {
  if (mockPickedFileForTest != null) {
    return mockPickedFileForTest;
  }
  final input = html.FileUploadInputElement()
    ..accept = '.glb,.gltf,.obj,.fbx,.stl,.zip,.dae';

  // `onChange` never fires when the dialog is dismissed, so a bare
  // `await input.onChange.first` left the import button dead forever. The
  // `cancel` event and the window regaining focus both close the request.
  final pickCompleter = Completer<html.File?>();
  StreamSubscription<html.Event>? changeSub;
  StreamSubscription<html.Event>? cancelSub;
  StreamSubscription<html.Event>? focusSub;

  void finish(html.File? file) {
    if (pickCompleter.isCompleted) return;
    changeSub?.cancel();
    cancelSub?.cancel();
    focusSub?.cancel();
    pickCompleter.complete(file);
  }

  changeSub = input.onChange.listen((_) {
    final files = input.files;
    finish((files != null && files.isNotEmpty) ? files.first : null);
  });
  cancelSub = input.on['cancel'].listen((_) => finish(null));
  // Older browsers do not fire `cancel`; when the tab regains focus and the
  // input is still empty the user dismissed the dialog.
  focusSub = html.window.onFocus.listen((_) {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (pickCompleter.isCompleted) return;
      final files = input.files;
      finish((files != null && files.isNotEmpty) ? files.first : null);
    });
  });

  input.click();
  final file = await pickCompleter.future;
  if (file == null) return null;

  final reader = html.FileReader();
  final completer = Completer<Uint8List>();

  reader.onLoadEnd.listen((event) {
    final result = reader.result;
    if (result is Uint8List) {
      completer.complete(result);
    } else if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is List<int>) {
      completer.complete(Uint8List.fromList(result));
    } else {
      completer.complete(Uint8List(0));
    }
  });

  reader.onError.listen((error) {
    completer.completeError(error);
  });

  reader.readAsArrayBuffer(file);
  final bytes = await completer.future;

  return PickedFile(file.name, bytes);
}

Future<PickedFile?> pickAudioFile() async {
  if (mockPickedFileForTest != null) {
    return mockPickedFileForTest;
  }
  final input = html.FileUploadInputElement()
    ..accept = '.wav,.ogg,.mp3,.flac';
  input.click();
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final reader = html.FileReader();
  final completer = Completer<Uint8List>();

  reader.onLoadEnd.listen((event) {
    final result = reader.result;
    if (result is Uint8List) {
      completer.complete(result);
    } else if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is List<int>) {
      completer.complete(Uint8List.fromList(result));
    } else {
      completer.complete(Uint8List(0));
    }
  });
  reader.onError.listen((error) => completer.complete(Uint8List(0)));
  reader.readAsArrayBuffer(file);

  return PickedFile(file.name, await completer.future);
}
