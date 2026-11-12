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
    this.onMeshSelected,
    this.fallbackWidget,
    this.attachOnly = false,
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
  final ValueChanged<String>? onMeshSelected;
  final Widget? fallbackWidget;
  final bool attachOnly;

  @override
  Widget build(BuildContext context) {
    return fallbackWidget ?? const SizedBox.shrink();
  }
}

void rotateSketchfabModel(double yawAngle) {}
void flipSketchfabModel() {}
void snapSketchfabModelToGround() {}
void purgeSketchfabUnderWheelObjects() {}
void scaleSketchfabModel(double targetLength) {}
void updateSketchfabWheelMarkers(List<dynamic> wheels) {}
void highlightSketchfabWheels(List<String> wheelNodeNames) {}
void clearSketchfabWheels() {}
void setSketchfabCameraPreset(String preset) {}
void setSketchfabForwardArrowVisible(bool visible) {}
void highlightSketchfabMeshesCyan(dynamic meshNamesOrList) {}
dynamic detectSketchfabWheels({double groundTol = 0.08, double inboardTol = 0.015}) => null;
void playSketchfabAudioPreview(
  String slotId,
  double pitchMultiplier, {
  Uint8List? bytes,
}) {}
void stopSketchfabAudioPreview() {}
void updateSketchfabSkidAudio(bool isDrifting, bool enabled) {}
void updateSketchfabEngineAudio(
  double rpm,
  double throttle,
  String profile,
  bool sirenEnabled,
) {}
void stopSketchfabEngineAudio() {}
bool enterSketchfabTestDrive() => false;
void updateSketchfabTestDriveState({
  required double x,
  required double y,
  required double z,
  required double yaw,
  required double pitch,
  required double roll,
  required double steerAngle,
  required double rearSteerAngle,
  required double wheelRollRad,
  required List<double> compressions,
  required double camX,
  required double camY,
  required double camZ,
  required double targetX,
  required double targetY,
  required double targetZ,
}) {}
void exitSketchfabTestDrive() {}
