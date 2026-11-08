import 'dart:typed_data';
import 'package:flutter/material.dart';

class SketchfabViewport extends StatelessWidget {
  const SketchfabViewport({
    super.key,
    this.bytes,
    required this.renderMode,
    required this.lighting,
    required this.gridStyle,
    required this.autoTurntable,
    required this.cameraPreset,
    this.resetEpoch = 0,
    this.detectedWheels = const [],
    this.fallbackWidget,
  });

  final Uint8List? bytes;
  final String renderMode;
  final String lighting;
  final String gridStyle;
  final bool autoTurntable;
  final String cameraPreset;
  final int resetEpoch;
  final List<dynamic> detectedWheels;
  final Widget? fallbackWidget;

  @override
  Widget build(BuildContext context) {
    return fallbackWidget ?? const SizedBox.shrink();
  }
}
