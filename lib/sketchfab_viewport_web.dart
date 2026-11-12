// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class SketchfabViewport extends StatefulWidget {
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

  /// Re-attaches the already-loaded Three.js scene without reloading a model.
  final bool attachOnly;

  @override
  State<SketchfabViewport> createState() => _SketchfabViewportState();
}

class _SketchfabViewportState extends State<SketchfabViewport> {
  static int _viewIdSeq = 0;
  late final String _viewType;
  html.DivElement? _container;
  Uint8List? _loadedBytes;
  static Uint8List? _globalLoadedBytes;
  html.EventListener? _cameraOrbitListener;
  html.EventListener? _nodeSelectListener;

  @override
  void initState() {
    super.initState();
    _viewType = 'sketchfab-viewport-${++_viewIdSeq}';

    _container = html.DivElement()
      ..id = 'sketchfab-host-$_viewIdSeq'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#090D0B';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _container!,
    );

    _cameraOrbitListener = (html.Event event) {
      if (event is html.CustomEvent) {
        try {
          final jsEvent = js.JsObject.fromBrowserObject(event);
          final detail = jsEvent['detail'];
          if (detail != null) {
            final az = (detail['azimuth'] as num?)?.toDouble();
            final el = (detail['elevation'] as num?)?.toDouble();
            final dist = (detail['distance'] as num?)?.toDouble();
            if (az != null && el != null && dist != null) {
              widget.onCameraOrbit?.call(az, el, dist);
            }
          }
        } catch (_) {}
      }
    };
    html.window.addEventListener('sketchfab-camera-orbit', _cameraOrbitListener);

    _nodeSelectListener = (html.Event event) {
      if (event is html.CustomEvent) {
        try {
          final jsEvent = js.JsObject.fromBrowserObject(event);
          final detail = jsEvent['detail'];
          if (detail != null) {
            final meshName = detail['meshName']?.toString();
            if (meshName != null && meshName.isNotEmpty) {
              widget.onMeshSelected?.call(meshName);
            }
          }
        } catch (_) {}
      }
    };
    html.window.addEventListener('sketchfab-node-select', _nodeSelectListener);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initViewer();
    });
  }

  @override
  void dispose() {
    if (_cameraOrbitListener != null) {
      html.window.removeEventListener('sketchfab-camera-orbit', _cameraOrbitListener);
      _cameraOrbitListener = null;
    }
    if (_nodeSelectListener != null) {
      html.window.removeEventListener('sketchfab-node-select', _nodeSelectListener);
      _nodeSelectListener = null;
    }
    super.dispose();
  }

  void _initViewer() {
    if (_container == null || !mounted) return;
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer != null) {
        viewer.callMethod('init', [_container]);
        final bytes = widget.bytes;
        if (widget.attachOnly) {
          // Keep the existing scene/model; Flutter only moved the canvas.
        } else if (bytes != null &&
            bytes.isNotEmpty &&
            !identical(bytes, _globalLoadedBytes)) {
          _loadModel(bytes);
        } else if (bytes == null || bytes.isEmpty) {
          viewer.callMethod('loadDemoCar');
          _globalLoadedBytes = null;
        }
        _syncControls();
        // Platform views are laid out after the first frame; a late resize
        // avoids a stretched canvas in freshly mounted Test Drive views.
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          try {
            js.context['SketchfabViewer']?.callMethod('resize');
          } catch (_) {}
        });
      } else {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) _initViewer();
        });
      }
    } catch (e) {
      debugPrint('SketchfabViewport init error: $e');
    }
  }

  void _loadModel(Uint8List bytes) {
    if (_loadedBytes == bytes) return;
    _loadedBytes = bytes;
    _globalLoadedBytes = bytes;
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer != null) {
        // Pass Uint8List directly to JS with filename
        viewer.callMethod('loadModel', [bytes, widget.fileName ?? 'model.glb']);
      } else {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted && _loadedBytes == bytes) {
            _loadedBytes = null;
            _loadModel(bytes);
          }
        });
      }
    } catch (e) {
      debugPrint('SketchfabViewport loadModel error: $e');
    }
  }

  void _syncControls() {
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer == null) return;
      viewer.callMethod('setRenderMode', [widget.renderMode]);
      viewer.callMethod('setLighting', [widget.lighting]);
      viewer.callMethod('setGridStyle', [widget.gridStyle]);
      viewer.callMethod('setForwardArrowVisible', [widget.showForwardArrow]);
      viewer.callMethod('setTurntable', [widget.autoTurntable]);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant SketchfabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bytes != oldWidget.bytes) {
      if (widget.bytes != null && widget.bytes!.isNotEmpty) {
        _loadModel(widget.bytes!);
      } else {
        _loadedBytes = null;
        try {
          final viewer = js.context['SketchfabViewer'];
          viewer?.callMethod('loadDemoCar');
        } catch (_) {}
      }
    }
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer != null) {
        if (widget.renderMode != oldWidget.renderMode) {
          viewer.callMethod('setRenderMode', [widget.renderMode]);
        }
        if (widget.lighting != oldWidget.lighting) {
          viewer.callMethod('setLighting', [widget.lighting]);
        }
        if (widget.gridStyle != oldWidget.gridStyle) {
          viewer.callMethod('setGridStyle', [widget.gridStyle]);
        }
        if (widget.showForwardArrow != oldWidget.showForwardArrow) {
          viewer.callMethod('setForwardArrowVisible', [widget.showForwardArrow]);
        }
        if (widget.autoTurntable != oldWidget.autoTurntable) {
          viewer.callMethod('setTurntable', [widget.autoTurntable]);
        }
        if (widget.cameraPreset != oldWidget.cameraPreset) {
          viewer.callMethod('setCameraPreset', [widget.cameraPreset]);
        }
        if (widget.resetEpoch != oldWidget.resetEpoch) {
          viewer.callMethod('resetCamera');
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.attachOnly &&
        (widget.bytes == null || widget.bytes!.isEmpty)) {
      return widget.fallbackWidget ?? const SizedBox.shrink();
    }
    return HtmlElementView(viewType: _viewType);
  }
}

void rotateSketchfabModel(double yawAngle) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('rotateModel', [yawAngle]);
    }
  } catch (e) {
    debugPrint('rotateSketchfabModel error: $e');
  }
}

void flipSketchfabModel() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('flipModel');
    }
  } catch (e) {
    debugPrint('flipSketchfabModel error: $e');
  }
}

void snapSketchfabModelToGround() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('snapToGround');
    }
  } catch (e) {
    debugPrint('snapSketchfabModelToGround error: $e');
  }
}

void purgeSketchfabUnderWheelObjects() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('purgeUnderWheelMeshes');
    }
  } catch (e) {
    debugPrint('purgeSketchfabUnderWheelObjects error: $e');
  }
}

void scaleSketchfabModel(double targetLength) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('applyScale', [targetLength]);
    }
  } catch (e) {
    debugPrint('scaleSketchfabModel error: $e');
  }
}

void updateSketchfabWheelMarkers(List<dynamic> wheels) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      final jsList = wheels.map((w) {
        if (w is Map) return w;
        return {'x': (w as dynamic).x, 'y': (w as dynamic).y, 'z': (w as dynamic).z};
      }).toList();
      viewer.callMethod('setWheelMarkers', [js.JsObject.jsify(jsList)]);
    }
  } catch (e) {
    debugPrint('updateSketchfabWheelMarkers error: $e');
  }
}

void highlightSketchfabWheels(List<String> wheelNodeNames) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('highlightWheelMeshes', [js.JsObject.jsify(wheelNodeNames)]);
    }
  } catch (e) {
    debugPrint('highlightSketchfabWheels error: $e');
  }
}

void clearSketchfabWheels() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('clearWheelDataAndMarkers');
    }
  } catch (e) {
    debugPrint('clearSketchfabWheels error: $e');
  }
}

void setSketchfabCameraPreset(String preset) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('setCameraPreset', [preset]);
    }
  } catch (e) {
    debugPrint('setSketchfabCameraPreset error: $e');
  }
}

void setSketchfabForwardArrowVisible(bool visible) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('setForwardArrowVisible', [visible]);
    }
  } catch (e) {
    debugPrint('setSketchfabForwardArrowVisible error: $e');
  }
}

void highlightSketchfabMeshesCyan(dynamic meshNamesOrList) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('highlightMeshesCyan', [js.JsObject.jsify(meshNamesOrList)]);
    }
  } catch (e) {
    debugPrint('highlightSketchfabMeshesCyan error: $e');
  }
}

dynamic detectSketchfabWheels({double groundTol = 0.08, double inboardTol = 0.015}) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      return viewer.callMethod('detectWheels', [
        js.JsObject.jsify({
          'groundTolerance': groundTol,
          'inboardCaptureWidth': inboardTol,
        })
      ]);
    }
  } catch (e) {
    debugPrint('detectSketchfabWheels error: $e');
  }
  return null;
}

void playSketchfabAudioPreview(
  String slotId,
  double pitchMultiplier, {
  Uint8List? bytes,
}) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      final payload = bytes != null && bytes.isNotEmpty
          ? js.JsObject.jsify(bytes.toList())
          : null;
      viewer.callMethod('playAudioPreview', [slotId, pitchMultiplier, payload]);
    }
  } catch (e) {
    debugPrint('playSketchfabAudioPreview error: $e');
  }
}

void stopSketchfabAudioPreview() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('stopAudioPreview');
    }
  } catch (e) {
    debugPrint('stopSketchfabAudioPreview error: $e');
  }
}

void updateSketchfabEngineAudio(
  double rpm,
  double throttle,
  String profile,
  bool sirenEnabled,
) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod(
        'updateEngineAndSirenAudio',
        [rpm, throttle, profile, sirenEnabled],
      );
    }
  } catch (e) {
    debugPrint('updateSketchfabEngineAudio error: $e');
  }
}

void stopSketchfabEngineAudio() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('stopEngineAndSirenAudio');
    }
  } catch (e) {
    debugPrint('stopSketchfabEngineAudio error: $e');
  }
}

/// Puts the live Three.js scene into drivable Test Drive mode.
bool enterSketchfabTestDrive() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      return viewer.callMethod('enterTestDriveMode') == true;
    }
  } catch (e) {
    debugPrint('enterSketchfabTestDrive error: $e');
  }
  return false;
}

final js.JsObject _tdState = js.JsObject(js.context['Object']);
final js.JsObject _tdCompressions = js.JsObject.jsify(<double>[0, 0, 0, 0]);

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
}) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer == null) return;
    for (var i = 0; i < 4 && i < compressions.length; i++) {
      _tdCompressions[i] = compressions[i];
    }
    _tdState['x'] = x;
    _tdState['y'] = y;
    _tdState['z'] = z;
    _tdState['yaw'] = yaw;
    _tdState['pitch'] = pitch;
    _tdState['roll'] = roll;
    _tdState['steerAngle'] = steerAngle;
    _tdState['rearSteerAngle'] = rearSteerAngle;
    _tdState['wheelRollRad'] = wheelRollRad;
    _tdState['compressions'] = _tdCompressions;
    _tdState['camX'] = camX;
    _tdState['camY'] = camY;
    _tdState['camZ'] = camZ;
    _tdState['targetX'] = targetX;
    _tdState['targetY'] = targetY;
    _tdState['targetZ'] = targetZ;
    viewer.callMethod('updateTestDriveState', [_tdState]);
  } catch (e) {
    debugPrint('updateSketchfabTestDriveState error: $e');
  }
}

void exitSketchfabTestDrive() {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('exitTestDriveMode');
    }
  } catch (e) {
    debugPrint('exitSketchfabTestDrive error: $e');
  }
}

void updateSketchfabSkidAudio(bool isDrifting, bool enabled) {
  try {
    final viewer = js.context['SketchfabViewer'];
    if (viewer != null) {
      viewer.callMethod('updateSkidAudio', [isDrifting, enabled]);
    }
  } catch (e) {
    debugPrint('updateSketchfabSkidAudio error: $e');
  }
}
