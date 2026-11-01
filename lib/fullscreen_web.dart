// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

bool isBrowserFullscreen() {
  return html.document.fullscreenElement != null;
}

void toggleBrowserFullscreen() {
  if (html.document.fullscreenElement != null) {
    html.document.exitFullscreen();
  } else {
    html.document.documentElement?.requestFullscreen();
  }
}
