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
