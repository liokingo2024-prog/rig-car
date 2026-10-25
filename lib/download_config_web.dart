// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadTextFile(
  String name,
  String contents,
  String mimeType,
) async {
  final blob = html.Blob([utf8.encode(contents)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = name
    ..click();
  html.Url.revokeObjectUrl(url);
  anchor.remove();
}
