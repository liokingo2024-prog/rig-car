import 'dart:typed_data';
import 'model_data.dart';

PickedFile? mockPickedFileForTest;

Future<PickedFile?> pickModelFile() async => mockPickedFileForTest;

Future<PickedFile?> pickAudioFile() async =>
    mockPickedFileForTest ?? PickedFile('custom_audio.wav', Uint8List(0));
