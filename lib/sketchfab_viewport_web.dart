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
  final bool autoTurntable;
  final String cameraPreset;
  final int resetEpoch;
  final List<dynamic> detectedWheels;
  final void Function(double azimuth, double elevation, double distance)? onCameraOrbit;
  final Widget? fallbackWidget;

  @override
  State<SketchfabViewport> createState() => _SketchfabViewportState();
}

class _SketchfabViewportState extends State<SketchfabViewport> {
  static int _viewIdSeq = 0;
  late final String _viewType;
  html.DivElement? _container;
  Uint8List? _loadedBytes;
  html.EventListener? _cameraOrbitListener;

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
    super.dispose();
  }

  void _initViewer() {
    if (_container == null || !mounted) return;
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer != null) {
        viewer.callMethod('init', [_container]);
        if (widget.bytes != null && widget.bytes!.isNotEmpty) {
          _loadModel(widget.bytes!);
        } else {
          viewer.callMethod('loadDemoCar');
        }
        _syncControls();
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
    if (widget.bytes == null || widget.bytes!.isEmpty) {
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
