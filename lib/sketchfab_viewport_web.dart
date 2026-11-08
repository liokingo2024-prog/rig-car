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
  State<SketchfabViewport> createState() => _SketchfabViewportState();
}

class _SketchfabViewportState extends State<SketchfabViewport> {
  static int _viewIdSeq = 0;
  late final String _viewType;
  html.DivElement? _container;
  Uint8List? _loadedBytes;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initViewer();
    });
  }

  void _initViewer() {
    if (_container == null || !mounted) return;
    try {
      final viewer = js.context['SketchfabViewer'];
      if (viewer != null) {
        viewer.callMethod('init', [_container]);
        if (widget.bytes != null && widget.bytes!.isNotEmpty) {
          _loadModel(widget.bytes!);
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
        // Pass Uint8List directly to JS
        viewer.callMethod('loadGlbFromArrayBuffer', [bytes]);
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
    if (widget.bytes != oldWidget.bytes && widget.bytes != null) {
      _loadModel(widget.bytes!);
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
    // If bytes are not loaded or WebGL is not available, render fallback canvas
    if (widget.bytes == null || widget.bytes!.isEmpty) {
      return widget.fallbackWidget ?? const SizedBox.shrink();
    }
    return HtmlElementView(viewType: _viewType);
  }
}
