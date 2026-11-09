import 'dart:typed_data';
import 'package:flutter/material.dart';

class SketchfabViewport extends StatelessWidget {
  const SketchfabViewport({
    super.key,
    this.bytes,
    this.fileName,
    required this.renderMode,
    required this.lighting,
    required this.gridStyle,
    this.showForwardArrow = true,
    required this.autoTurntable,
    required this.cameraPreset,
    this.resetEpoch = 0,
    this.detectedWheels = const [],
    this.onCameraOrbit,
    this.fallbackWidget,
  });

  final Uint8List? bytes;
  final String? fileName;
  final String renderMode;
  final String lighting;
  final String gridStyle;
  final bool showForwardArrow;
  final bool autoTurntable;
  final String cameraPreset;
  final int resetEpoch;
  final List<dynamic> detectedWheels;
  final void Function(double azimuth, double elevation, double distance)? onCameraOrbit;
  final Widget? fallbackWidget;

  @override
  Widget build(BuildContext context) {
    return fallbackWidget ?? const SizedBox.shrink();
  }
}

void rotateSketchfabModel(double yawAngle) {}
void flipSketchfabModel() {}
void snapSketchfabModelToGround() {}
void scaleSketchfabModel(double targetLength) {}
void updateSketchfabWheelMarkers(List<dynamic> wheels) {}
void highlightSketchfabWheels(List<String> wheelNodeNames) {}
void clearSketchfabWheels() {}
void setSketchfabCameraPreset(String preset) {}
void setSketchfabForwardArrowVisible(bool visible) {}
void highlightSketchfabMeshesCyan(dynamic meshNamesOrList) {}
dynamic detectSketchfabWheels({double groundTol = 0.08, double inboardTol = 0.015}) => null;
