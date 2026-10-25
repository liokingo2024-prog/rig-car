// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<String?> pickModelFile() async {
  final input = html.FileUploadInputElement()..accept = '.glb,.gltf';
  input.click();
  await input.onChange.first;
  final files = input.files;
  return files == null || files.isEmpty ? null : files.first.name;
}
