import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'fullscreen.dart';
import 'model_data.dart';

// ── 3D Wireframe Viewer ─────────────────────────────────────────────────────
//
// Interactive 3D viewport that renders the parsed model mesh as a wireframe,
// highlights detected wheels and body parts, and renders 3D markers for wheels
// and center of mass. Supports orbit, zoom, pan, and view presets.

enum CameraPreset {
  iso('ISO', 'Isometric View', Icons.view_in_ar_rounded),
  front('FRONT', 'Front View (-Z)', Icons.keyboard_arrow_up_rounded),
  back('BACK', 'Rear View (+Z)', Icons.keyboard_arrow_down_rounded),
  left('LEFT', 'Left Side (-X)', Icons.keyboard_arrow_left_rounded),
  right('RIGHT', 'Right Side (+X)', Icons.keyboard_arrow_right_rounded),
  top('TOP', 'Top View (+Y)', Icons.vertical_align_top_rounded),
  bottom('BOTTOM', 'Underside (-Y)', Icons.vertical_align_bottom_rounded);

  const CameraPreset(this.shortName, this.label, this.icon);
  final String shortName;
  final String label;
  final IconData icon;
}

enum ViewerLighting {
  studio('Studio', Icons.lightbulb_outline_rounded),
  daylight('Daylight', Icons.wb_sunny_outlined),
  night('Night', Icons.nightlight_outlined),
  flat('Flat', Icons.contrast_rounded);

  const ViewerLighting(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum ViewerRenderMode {
  wireframe('Wireframe', Icons.polyline_rounded),
  solid('Solid', Icons.view_in_ar_rounded),
  hybrid('Hybrid', Icons.layers_rounded);

  const ViewerRenderMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum GroundGridStyle {
  cad('CAD Studio', 'CAD Grid', Icons.grid_4x4_rounded),
  radial('Radial Podium', 'Radial', Icons.motion_photos_on_rounded),
  hex('Cyber Hex', 'Hex Grid', Icons.hive_rounded),
  checker('Proving Skidpad', 'Skidpad', Icons.grid_view_rounded),
  off('Minimal Floor (Off)', 'Off', Icons.grid_off_rounded);

  const GroundGridStyle(this.label, this.shortName, this.icon);
  final String label;
  final String shortName;
  final IconData icon;

  GroundGridStyle get next {
    final idx = (index + 1) % GroundGridStyle.values.length;
    return GroundGridStyle.values[idx];
  }
}

class WireframeViewer extends StatefulWidget {
  const WireframeViewer({
    super.key,
    required this.model,
    required this.detection,
    this.bodyNodeIndex,
    this.selectedNodeIndex,
    this.onNodeSelected,
    this.accentColor = const Color(0xFF10B981),
    this.bodyColor = const Color(0xFF64B5F6),
    this.wheelColor = const Color(0xFF34D399),
    this.wireColor = const Color(0xFF455A64),
    this.centerOfMassY = -0.18,
    this.onTestDrive,
  });

  final ParsedModel? model;
  final DetectionResult? detection;
  final int? bodyNodeIndex;
  final int? selectedNodeIndex;
  final ValueChanged<int>? onNodeSelected;
  final Color accentColor;
  final Color bodyColor;
  final Color wheelColor;
  final Color wireColor;
  final double centerOfMassY;
  final VoidCallback? onTestDrive;

  @override
  State<WireframeViewer> createState() => _WireframeViewerState();
}

class _WireframeViewerState extends State<WireframeViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _autoTurntable = false;
  bool _isFullscreen = false;
  CameraPreset _preset = CameraPreset.iso;

  // Camera spherical coordinates
  double _azimuth = 0.785; // 45 degrees
  double _elevation = 0.45; // ~26 degrees
  double _distance = 6.0;
  Vec3 _target = Vec3.zero;
  double _panX = 0;
  double _panY = 0;

  bool _showMarkers = false;
  GroundGridStyle _gridStyle = GroundGridStyle.cad;
  ViewerLighting _lighting = ViewerLighting.studio;
  ViewerRenderMode _renderMode = ViewerRenderMode.solid;
  bool get _showGrid => _gridStyle != GroundGridStyle.off;
  bool _invertDrag = false;
  // Performance-first default. The full parsed model remains available for
  // detection; only the preview is intentionally decimated.
  final bool _denseWireframe = false;

  @override
  void initState() {
    super.initState();
    _resetCameraToModel();
    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2400),
        )..addListener(() {
          if (_autoTurntable) _azimuth += 0.007;
        });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WireframeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model != oldWidget.model && widget.model != null) {
      _resetCameraToModel();
    }
  }

  void _resetCameraToModel() {
    final model = widget.model;
    if (model != null && model.instances.isNotEmpty) {
      _target = model.worldBBox.center;
      final diag = model.worldBBox.diagonal;
      _distance = (diag > 0.1 ? diag : 4.0) * 1.6;
    } else {
      _target = Vec3.zero;
      _distance = 6.0;
    }
    _azimuth = 0.785;
    _elevation = 0.38;
    _panX = 0;
    _panY = 0;
    _preset = CameraPreset.iso;
  }

  void _setPreset(CameraPreset preset) {
    setState(() {
      _preset = preset;
      switch (preset) {
        case CameraPreset.iso:
          _azimuth = 0.785;
          _elevation = 0.45;
        case CameraPreset.front:
          _azimuth = 3.14159; // facing -Z
          _elevation = 0.05;
        case CameraPreset.back:
          _azimuth = 0.0; // facing +Z
          _elevation = 0.05;
        case CameraPreset.left:
          _azimuth = -1.5708; // facing +X from the left
          _elevation = 0.05;
        case CameraPreset.right:
          _azimuth = 1.5708; // facing +X
          _elevation = 0.05;
        case CameraPreset.top:
          _azimuth = 0.0;
          _elevation = 1.56; // near 90 deg up
        case CameraPreset.bottom:
          _azimuth = 0.0;
          _elevation = -1.35;
      }
    });
  }

  void _toggleFullscreen() {
    toggleBrowserFullscreen();
    setState(() => _isFullscreen = !_isFullscreen);
  }

  void _toggleTurntable() {
    setState(() => _autoTurntable = !_autoTurntable);
    if (_autoTurntable) {
      _animController.repeat();
    } else {
      _animController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090D0B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── Interactive Gesture Area ──────────────────────────────────────
          Positioned.fill(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    _distance = (_distance * (1 + event.scrollDelta.dy * 0.001))
                        .clamp(1.0, 50.0);
                  });
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(_resetCameraToModel),
                onPanUpdate: (details) {
                  setState(() {
                    // Natural orbit: dragging right rotates model right; dragging up tilts view up.
                    // Both axes maintain unified polarity across natural and inverted modes.
                    final factor = _invertDrag ? 1.0 : -1.0;
                    _azimuth += factor * details.delta.dx * 0.01;
                    _elevation = (_elevation - factor * details.delta.dy * 0.01)
                        .clamp(-1.5, 1.5);
                  });
                },
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        painter: _WireframeScenePainter(
                          model: widget.model,
                          detection: widget.detection,
                          bodyNodeIndex: widget.bodyNodeIndex,
                          selectedNodeIndex: widget.selectedNodeIndex,
                          azimuth: _azimuth,
                          elevation: _elevation,
                          distance: _distance,
                          target: _target,
                          panX: _panX,
                          panY: _panY,
                          gridStyle: _gridStyle,
                          lighting: _lighting,
                          renderMode: _renderMode,
                          showGrid: _showGrid,
                          showMarkers: _showMarkers,
                          denseWireframe: _denseWireframe,
                          accentColor: widget.accentColor,
                          bodyColor: widget.bodyColor,
                          wheelColor: widget.wheelColor,
                          wireColor: widget.wireColor,
                          centerOfMassY: widget.centerOfMassY,
                          pulseProgress: _animController.value,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Top Bar Controls ──────────────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: LayoutBuilder(
              builder: (context, box) {
                final isUltraCompact = box.maxWidth < 640;
                final isCompact = box.maxWidth < 780;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _VehicleStatusBadge(
                        fileName: widget.model != null
                            ? widget.model!.fileName
                            : 'Procedural 3D Rig',
                        wheelCount: widget.detection?.wheels.length ?? 0,
                        compact: isCompact,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                            if (widget.onTestDrive != null) ...[
                              FilledButton.icon(
                                onPressed: widget.onTestDrive,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: const Color(0xFF041D14),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isUltraCompact ? 7 : 9,
                                    vertical: 5,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  elevation: 3,
                                  shadowColor: const Color(0x6010B981),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.sports_motorsports_rounded,
                                  size: 13,
                                ),
                                label: Text(
                                  isUltraCompact ? 'DRIVE' : 'TEST DRIVE',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],

                            // 1. View Selection (Render Mode: Solid / Wireframe / Hybrid)
                            PopupMenuButton<ViewerRenderMode>(
                              tooltip: 'Render mode: ${_renderMode.label}',
                              initialValue: _renderMode,
                              onSelected: (mode) =>
                                  setState(() => _renderMode = mode),
                              color: const Color(0xFF111714),
                              surfaceTintColor: Colors.transparent,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0xFF223127),
                                ),
                              ),
                              itemBuilder: (context) =>
                                  ViewerRenderMode.values.map((mode) {
                                    final selected = mode == _renderMode;
                                    return PopupMenuItem<ViewerRenderMode>(
                                      value: mode,
                                      height: 38,
                                      child: Row(
                                        children: [
                                          Icon(
                                            mode.icon,
                                            size: 16,
                                            color: selected
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF86978C),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            mode.label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: selected
                                                  ? const Color(0xFFF0FDF4)
                                                  : const Color(0xFFC9D1D9),
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                          if (selected) ...[
                                            const Spacer(),
                                            const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Color(0xFF10B981),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              child: _ViewerControl(
                                icon: _renderMode.icon,
                                label: _renderMode.label,
                                active:
                                    _renderMode != ViewerRenderMode.wireframe,
                              ),
                            ),
                            const SizedBox(width: 4),

                            // 2. Camera View Angle Dropdown
                            PopupMenuButton<CameraPreset>(
                              tooltip: 'Camera angle: ${_preset.label}',
                              initialValue: _preset,
                              onSelected: _setPreset,
                              color: const Color(0xFF111714),
                              surfaceTintColor: Colors.transparent,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0xFF223127),
                                ),
                              ),
                              itemBuilder: (context) =>
                                  CameraPreset.values.map((preset) {
                                    final selected = preset == _preset;
                                    return PopupMenuItem<CameraPreset>(
                                      value: preset,
                                      height: 38,
                                      child: Row(
                                        children: [
                                          Icon(
                                            preset.icon,
                                            size: 16,
                                            color: selected
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF86978C),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            preset.label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: selected
                                                  ? const Color(0xFFF0FDF4)
                                                  : const Color(0xFFC9D1D9),
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                          if (selected) ...[
                                            const Spacer(),
                                            const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Color(0xFF10B981),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              child: _ViewerControl(
                                icon: _preset.icon,
                                label: _preset.shortName,
                                active: true,
                              ),
                            ),
                            const SizedBox(width: 4),

                            // 3. Viewport Lighting Dropdown
                            PopupMenuButton<ViewerLighting>(
                              tooltip: 'Viewport lighting: ${_lighting.label}',
                              initialValue: _lighting,
                              onSelected: (lighting) =>
                                  setState(() => _lighting = lighting),
                              color: const Color(0xFF111714),
                              surfaceTintColor: Colors.transparent,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0xFF223127),
                                ),
                              ),
                              itemBuilder: (context) =>
                                  ViewerLighting.values.map((lighting) {
                                    return PopupMenuItem<ViewerLighting>(
                                      value: lighting,
                                      child: Row(
                                        children: [
                                          Icon(lighting.icon, size: 16),
                                          const SizedBox(width: 8),
                                          Text(lighting.label),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              child: _ViewerControl(
                                icon: _lighting.icon,
                                label: isCompact ? '' : _lighting.label,
                                active: false,
                              ),
                            ),
                            const SizedBox(width: 4),

                            // 4. Quick Actions Capsule (Turntable + Reset)
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xC0111714),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: const Color(0xFF223127),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: _autoTurntable
                                        ? 'Pause Turntable'
                                        : 'Auto 360° Turntable',
                                    child: InkWell(
                                      onTap: _toggleTurntable,
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                        left: Radius.circular(5),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 5,
                                        ),
                                        child: Icon(
                                          _autoTurntable
                                              ? Icons.pause_circle_filled_rounded
                                              : Icons.rotate_right_rounded,
                                          size: 15,
                                          color: _autoTurntable
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFBAC7CE),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 14,
                                    color: const Color(0xFF223127),
                                  ),
                                  Tooltip(
                                    message: 'Reset View',
                                    child: InkWell(
                                      onTap: () =>
                                          setState(_resetCameraToModel),
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                        right: Radius.circular(5),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 5,
                                        ),
                                        child: Icon(
                                          Icons.refresh_rounded,
                                          size: 15,
                                          color: Color(0xFFBAC7CE),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),

                            // 5. Prominent Fullscreen Button
                            Tooltip(
                              message: _isFullscreen
                                  ? 'Exit Fullscreen'
                                  : 'Fullscreen Viewport',
                              child: InkWell(
                                onTap: _toggleFullscreen,
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isFullscreen
                                        ? const Color(0x3310B981)
                                        : const Color(0xC0111714),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: _isFullscreen
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF223127),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        size: 14,
                                        color: _isFullscreen
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF34D399),
                                      ),
                                      if (!isCompact) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          _isFullscreen
                                              ? 'EXIT FULL'
                                              : 'FULLSCREEN',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                            color: _isFullscreen
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),

          // ── HUD Telemetry Overlay ─────────────────────────────────────────
          Positioned(
            left: 14,
            bottom: 42,
            child: _TelemetryOverlay(
              azimuth: _azimuth,
              elevation: _elevation,
              distance: _distance,
              model: widget.model,
            ),
          ),

          // ── Bottom Legend & Toggles ───────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.detection != null && widget.detection!.wheels.isNotEmpty) ...[
                    _LegendItem(color: widget.wheelColor, label: 'Wheels'),
                    const SizedBox(width: 8),
                  ],
                  _LegendItem(color: widget.bodyColor, label: 'Body'),
                  const SizedBox(width: 8),
                  _LegendItem(color: widget.wireColor, label: 'Chassis'),
                  const SizedBox(width: 16),
                // Toggle markers (only shown when detection markers are present)
                if (widget.detection != null && widget.detection!.wheels.isNotEmpty)
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: _showMarkers ? 'Hide Markers' : 'Show Markers',
                    icon: Icon(
                      _showMarkers
                          ? Icons.pin_drop_rounded
                          : Icons.pin_drop_outlined,
                      color: _showMarkers
                          ? const Color(0xFF34D399)
                          : const Color(0xFF71818B),
                    ),
                    onPressed: () => setState(() => _showMarkers = !_showMarkers),
                  ),
                // Land Grid Style Selector (CAD, Radial Podium, Cyber Hex, Skidpad, Off)
                PopupMenuButton<GroundGridStyle>(
                  tooltip: 'Land Grid: ${_gridStyle.label} (Click to choose)',
                  initialValue: _gridStyle,
                  onSelected: (style) => setState(() => _gridStyle = style),
                  color: const Color(0xFF111714),
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.black87,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF223127)),
                  ),
                  itemBuilder: (context) => GroundGridStyle.values.map((style) {
                    final isSel = style == _gridStyle;
                    return PopupMenuItem<GroundGridStyle>(
                      value: style,
                      height: 38,
                      child: Row(
                        children: [
                          Icon(
                            style.icon,
                            size: 16,
                            color: isSel
                                ? const Color(0xFF10B981)
                                : const Color(0xFF86978C),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            style.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSel
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFC9D1D9),
                            ),
                          ),
                          if (isSel) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xC0111714),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _gridStyle != GroundGridStyle.off
                            ? const Color(0xFF10B981).withValues(alpha: 0.6)
                            : const Color(0xFF223127),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _gridStyle.icon,
                          size: 14,
                          color: _gridStyle != GroundGridStyle.off
                              ? const Color(0xFF10B981)
                              : const Color(0xFF71818B),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _gridStyle.shortName,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _gridStyle != GroundGridStyle.off
                                ? const Color(0xFF34D399)
                                : const Color(0xFF71818B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 13,
                          color: _gridStyle != GroundGridStyle.off
                              ? const Color(0xFF34D399)
                              : const Color(0xFF71818B),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cycle Land Grid (${_gridStyle.next.label})',
                  icon: const Icon(Icons.swap_horiz_rounded),
                  color: const Color(0xFF8BA2B0),
                  onPressed: () => setState(() => _gridStyle = _gridStyle.next),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: _invertDrag
                      ? 'Controls: Inverted (Click for Natural)'
                      : 'Controls: Natural (Click for Inverted)',
                  icon: Icon(
                    _invertDrag
                        ? Icons.swap_vertical_circle_rounded
                        : Icons.swap_vertical_circle_outlined,
                    color: _invertDrag
                        ? const Color(0xFF10B981)
                        : const Color(0xFF8BA2B0),
                  ),
                  onPressed: () => setState(() => _invertDrag = !_invertDrag),
                ),
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

// ── Small UI Widgets ────────────────────────────────────────────────────────

class _VehicleStatusBadge extends StatelessWidget {
  const _VehicleStatusBadge({
    required this.fileName,
    required this.wheelCount,
    this.compact = false,
  });

  final String fileName;
  final int wheelCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xC0111714),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.view_in_ar_rounded,
            size: 13,
            color: Color(0xFF10B981),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Tooltip(
              message: fileName,
              child: Text(
                fileName,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (wheelCount > 0) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 1,
              height: 10,
              color: const Color(0xFF223127),
            ),
            Icon(
              wheelCount >= 4
                  ? Icons.check_circle_rounded
                  : Icons.pending_rounded,
              size: 11,
              color: wheelCount >= 4
                  ? const Color(0xFF10B981)
                  : const Color(0xFF34D399),
            ),
            const SizedBox(width: 3),
            Text(
              compact ? '$wheelCount/4' : '$wheelCount/4 Rigged',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: wheelCount >= 4
                    ? const Color(0xFF10B981)
                    : const Color(0xFF34D399),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ViewerControl extends StatelessWidget {
  const _ViewerControl({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF10B981) : const Color(0xFF8BA2B0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xC0111714),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: active ? color : const Color(0xFF223127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                color: active ? const Color(0xFF34D399) : const Color(0xFFC9D1D9),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 13, color: color),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8FA0AA),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TelemetryOverlay extends StatelessWidget {
  const _TelemetryOverlay({
    required this.azimuth,
    required this.elevation,
    required this.distance,
    required this.model,
  });

  final double azimuth;
  final double elevation;
  final double distance;
  final ParsedModel? model;

  @override
  Widget build(BuildContext context) {
    final yawDeg = ((azimuth * 180 / pi) % 360).round();
    final pitchDeg = (elevation * 180 / pi).round();
    final bbox = model?.worldBBox;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xC0090D0B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x4410B981)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'YAW $yawDeg°  •  PITCH $pitchDeg°  •  ${distance.toStringAsFixed(1)}m',
            style: const TextStyle(
              color: Color(0xFFB0C4CE),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontFamily: 'monospace',
            ),
          ),
          if (bbox != null) ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 10, color: const Color(0xFF223127)),
            const SizedBox(width: 8),
            Text(
              '${bbox.size.z.abs().toStringAsFixed(1)}L × ${bbox.size.x.abs().toStringAsFixed(1)}W × ${bbox.size.y.abs().toStringAsFixed(1)}H',
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Custom Painter ──────────────────────────────────────────────────────────

class _SolidTriangle {
  const _SolidTriangle({
    this.vertices,
    this.p0,
    this.p1,
    this.p2,
    required this.depth,
    required this.color,
  });

  final List<Vec3>? vertices;
  final Offset? p0;
  final Offset? p1;
  final Offset? p2;
  final double depth;
  final Color color;
}

class _WireframeScenePainter extends CustomPainter {
  static final List<(double, double)> _unitCircle24 = List.generate(
    24,
    (i) => (sin(i * 2 * pi / 24), cos(i * 2 * pi / 24)),
  );

  const _WireframeScenePainter({
    required this.model,
    required this.detection,
    this.bodyNodeIndex,
    required this.selectedNodeIndex,
    required this.azimuth,
    required this.elevation,
    required this.distance,
    required this.target,
    required this.panX,
    required this.panY,
    this.gridStyle = GroundGridStyle.cad,
    this.lighting = ViewerLighting.studio,
    this.renderMode = ViewerRenderMode.solid,
    required this.showGrid,
    required this.showMarkers,
    required this.denseWireframe,
    required this.accentColor,
    required this.bodyColor,
    required this.wheelColor,
    required this.wireColor,
    required this.centerOfMassY,
    this.pulseProgress = 0.0,
  });

  final ParsedModel? model;
  final DetectionResult? detection;
  final int? bodyNodeIndex;
  final int? selectedNodeIndex;
  final double azimuth;
  final double elevation;
  final double distance;
  final Vec3 target;
  final double panX;
  final double panY;
  final GroundGridStyle gridStyle;
  final ViewerLighting lighting;
  final ViewerRenderMode renderMode;
  final bool showGrid;
  final bool showMarkers;
  final bool denseWireframe;
  final Color accentColor;
  final Color bodyColor;
  final Color wheelColor;
  final Color wireColor;
  final double centerOfMassY;
  final double pulseProgress;

  @override
  bool shouldRepaint(covariant _WireframeScenePainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.detection != detection ||
        oldDelegate.bodyNodeIndex != bodyNodeIndex ||
        oldDelegate.selectedNodeIndex != selectedNodeIndex ||
        oldDelegate.azimuth != azimuth ||
        oldDelegate.elevation != elevation ||
        oldDelegate.distance != distance ||
        oldDelegate.target != target ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.gridStyle != gridStyle ||
        oldDelegate.lighting != lighting ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showMarkers != showMarkers ||
        oldDelegate.denseWireframe != denseWireframe ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.bodyColor != bodyColor ||
        oldDelegate.wheelColor != wheelColor ||
        oldDelegate.wireColor != wireColor ||
        oldDelegate.centerOfMassY != centerOfMassY ||
        oldDelegate.pulseProgress != pulseProgress;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final background = switch (lighting) {
      ViewerLighting.studio => const [Color(0xFF141F27), Color(0xFF0C1318)],
      ViewerLighting.daylight => const [Color(0xFF20384A), Color(0xFF10212D)],
      ViewerLighting.night => const [Color(0xFF090B18), Color(0xFF02040A)],
      ViewerLighting.flat => const [Color(0xFF111714), Color(0xFF111714)],
    };

    // Background gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: background,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Compute camera matrices
    final eye = Vec3(
      target.x + distance * cos(elevation) * sin(azimuth),
      target.y + distance * sin(elevation),
      target.z + distance * cos(elevation) * cos(azimuth),
    );

    final view = Mat4.lookAt(eye, target, Vec3(0, 1, 0));
    final aspect = size.width / size.height;
    final proj = Mat4.perspective(60 * pi / 180, aspect, 0.1, 100.0);
    final viewProj = proj * view;

    // Screen projector helper
    Offset? projectPoint(Vec3 p) {
      final clip = viewProj.transformClip(p);
      final w = clip[3];
      if (w <= 0.05) return null; // Behind camera
      final ndcX = clip[0] / w;
      final ndcY = clip[1] / w;
      final sx = (ndcX * 0.5 + 0.5) * size.width + panX;
      final sy = (1.0 - (ndcY * 0.5 + 0.5)) * size.height + panY;
      return Offset(sx, sy);
    }

    // ── 1. Draw 3D Ground Surface Grid ───────────────────────────────────────
    _drawGroundSurface(canvas, size, viewProj, projectPoint);

    // ── 2. Draw Model Preview ────────────────────────────────────────────────
    if (model != null && model!.instances.isNotEmpty) {
      if (renderMode != ViewerRenderMode.wireframe) {
        _drawModelSolid(canvas, size, viewProj, projectPoint, eye);
      }
      if (renderMode != ViewerRenderMode.solid) {
        _drawModelWireframe(canvas, size, projectPoint);
      }
    } else {
      if (renderMode != ViewerRenderMode.wireframe) {
        _drawProceduralSolidCar(canvas, size, viewProj, eye);
      }
      if (renderMode != ViewerRenderMode.solid) {
        _drawProceduralWireframeCar(canvas, size, projectPoint);
      }
    }

    // ── 3. Draw Detected Wheel Markers ──────────────────────────────────────
    if (showMarkers && (detection?.wheels.isNotEmpty ?? false)) {
      _drawMarkers(canvas, size, projectPoint);
    }
  }

  void _drawClippedLine(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    Vec3 p0,
    Vec3 p1,
    Paint paint,
  ) {
    final c0 = viewProj.transformClip(p0);
    final c1 = viewProj.transformClip(p1);
    const wMin = 0.05;

    final in0 = c0[3] >= wMin;
    final in1 = c1[3] >= wMin;

    if (!in0 && !in1) return;

    List<double> final0 = c0;
    List<double> final1 = c1;

    if (in0 && !in1) {
      final t = (wMin - c0[3]) / (c1[3] - c0[3]);
      final1 = [
        c0[0] + t * (c1[0] - c0[0]),
        c0[1] + t * (c1[1] - c0[1]),
        c0[2] + t * (c1[2] - c0[2]),
        wMin,
      ];
    } else if (!in0 && in1) {
      final t = (wMin - c0[3]) / (c1[3] - c0[3]);
      final0 = [
        c0[0] + t * (c1[0] - c0[0]),
        c0[1] + t * (c1[1] - c0[1]),
        c0[2] + t * (c1[2] - c0[2]),
        wMin,
      ];
    }

    final sx0 = (final0[0] / final0[3] * 0.5 + 0.5) * size.width + panX;
    final sy0 =
        (1.0 - (final0[1] / final0[3] * 0.5 + 0.5)) * size.height + panY;
    final sx1 = (final1[0] / final1[3] * 0.5 + 0.5) * size.width + panX;
    final sy1 =
        (1.0 - (final1[1] / final1[3] * 0.5 + 0.5)) * size.height + panY;

    canvas.drawLine(Offset(sx0, sy0), Offset(sx1, sy1), paint);
  }

  void _drawClippedPolygon(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    List<Vec3> worldVertices,
    Paint paint,
  ) {
    const wMin = 0.05;
    final clips = worldVertices.map((v) => viewProj.transformClip(v)).toList();

    final outClips = <List<double>>[];
    for (var i = 0; i < clips.length; i++) {
      final cur = clips[i];
      final next = clips[(i + 1) % clips.length];
      final curIn = cur[3] >= wMin;
      final nextIn = next[3] >= wMin;

      if (curIn && nextIn) {
        outClips.add(next);
      } else if (curIn && !nextIn) {
        final t = (wMin - cur[3]) / (next[3] - cur[3]);
        outClips.add([
          cur[0] + t * (next[0] - cur[0]),
          cur[1] + t * (next[1] - cur[1]),
          cur[2] + t * (next[2] - cur[2]),
          wMin,
        ]);
      } else if (!curIn && nextIn) {
        final t = (wMin - cur[3]) / (next[3] - cur[3]);
        outClips.add([
          cur[0] + t * (next[0] - cur[0]),
          cur[1] + t * (next[1] - cur[1]),
          cur[2] + t * (next[2] - cur[2]),
          wMin,
        ]);
        outClips.add(next);
      }
    }

    if (outClips.length < 3) return;

    final path = Path();
    for (var i = 0; i < outClips.length; i++) {
      final c = outClips[i];
      final w = c[3];
      final sx = (c[0] / w * 0.5 + 0.5) * size.width + panX;
      final sy = (1.0 - (c[1] / w * 0.5 + 0.5)) * size.height + panY;
      if (i == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawGroundSurface(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    final groundY = model?.worldBBox.lo.y ?? 0.0;

    // Contact shadow beneath car chassis is always rendered for depth
    _drawContactShadow(canvas, viewProj, size, groundY);

    if (gridStyle == GroundGridStyle.off) return;

    switch (gridStyle) {
      case GroundGridStyle.cad:
        _drawCadGrid(canvas, viewProj, size, groundY);
      case GroundGridStyle.radial:
        _drawRadialGrid(canvas, viewProj, size, groundY);
      case GroundGridStyle.hex:
        _drawHexGrid(canvas, viewProj, size, groundY);
      case GroundGridStyle.checker:
        _drawCheckerGrid(canvas, viewProj, size, groundY);
      case GroundGridStyle.off:
        break;
    }
  }

  void _drawContactShadow(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
  ) {
    final bbox = model?.worldBBox;
    final minX = bbox != null ? bbox.lo.x * 0.95 : -0.92;
    final maxX = bbox != null ? bbox.hi.x * 0.95 : 0.92;
    final minZ = bbox != null ? bbox.lo.z * 0.95 : -1.80;
    final maxZ = bbox != null ? bbox.hi.z * 0.95 : 1.80;

    final cx = (minX + maxX) * 0.5;
    final cz = (minZ + maxZ) * 0.5;
    final rx = (maxX - minX) * 0.48;
    final rz = (maxZ - minZ) * 0.50;

    // Blender/Sketchfab soft ambient occlusion ground contact shadow
    const segments = 24;
    final outerShadow = <Vec3>[
      for (var i = 0; i < segments; i++)
        Vec3(
          cx + rx * _unitCircle24[i].$1,
          groundY + 0.002,
          cz + rz * _unitCircle24[i].$2,
        ),
    ];
    _drawClippedPolygon(
      canvas,
      viewProj,
      size,
      outerShadow,
      Paint()
        ..color = const Color(0x38000000)
        ..style = PaintingStyle.fill,
    );

    // Inner dark core directly under vehicle chassis
    final innerShadow = <Vec3>[
      for (var i = 0; i < segments; i++)
        Vec3(
          cx + (rx * 0.68) * _unitCircle24[i].$1,
          groundY + 0.004,
          cz + (rz * 0.72) * _unitCircle24[i].$2,
        ),
    ];
    _drawClippedPolygon(
      canvas,
      viewProj,
      size,
      innerShadow,
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCadGrid(Canvas canvas, Mat4 viewProj, Size size, double groundY) {
    final minorGridPaint = Paint()
      ..color = const Color(0x1834D399)
      ..strokeWidth = 1.0;
    final majorGridPaint = Paint()
      ..color = const Color(0x3510B981)
      ..strokeWidth = 1.2;
    final axisXPaint = Paint()
      ..color = const Color(0x7034D399)
      ..strokeWidth = 1.6;
    final axisZPaint = Paint()
      ..color = const Color(0x9010B981)
      ..strokeWidth = 1.8;

    const extent = 5.0;
    const step = 0.5;

    for (var x = -extent; x <= extent; x += step) {
      final isMajor = (x.abs() - x.abs().round()).abs() < 0.05;
      final isAxis = x.abs() < 0.05;
      final paint = isAxis
          ? axisZPaint
          : (isMajor ? majorGridPaint : minorGridPaint);
      _drawClippedLine(
        canvas,
        viewProj,
        size,
        Vec3(x, groundY, -extent),
        Vec3(x, groundY, extent),
        paint,
      );
    }
    for (var z = -extent; z <= extent; z += step) {
      final isMajor = (z.abs() - z.abs().round()).abs() < 0.05;
      final isAxis = z.abs() < 0.05;
      final paint = isAxis
          ? axisXPaint
          : (isMajor ? majorGridPaint : minorGridPaint);
      _drawClippedLine(
        canvas,
        viewProj,
        size,
        Vec3(-extent, groundY, z),
        Vec3(extent, groundY, z),
        paint,
      );
    }

    // Outer boundary frame
    final framePaint = Paint()
      ..color = const Color(0x4010B981)
      ..strokeWidth = 1.3;
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(-extent, groundY, -extent),
      Vec3(extent, groundY, -extent),
      framePaint,
    );
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(extent, groundY, -extent),
      Vec3(extent, groundY, extent),
      framePaint,
    );
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(extent, groundY, extent),
      Vec3(-extent, groundY, extent),
      framePaint,
    );
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(-extent, groundY, extent),
      Vec3(-extent, groundY, -extent),
      framePaint,
    );
  }

  void _drawRadialGrid(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
  ) {
    final ringPaint = Paint()
      ..color = const Color(0x2810B981)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final rimPaint = Paint()
      ..color = const Color(0x6034D399)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final spokePaint = Paint()
      ..color = const Color(0x2034D399)
      ..strokeWidth = 1.0;
    final axisSpokePaint = Paint()
      ..color = const Color(0x5010B981)
      ..strokeWidth = 1.4;

    final radii = [0.8, 1.6, 2.5, 3.5, 4.6];
    const segments = 36;

    // Concentric turntable rings
    for (var rIdx = 0; rIdx < radii.length; rIdx++) {
      final r = radii[rIdx];
      final isOuterRim = rIdx == radii.length - 1;
      final paint = isOuterRim ? rimPaint : ringPaint;

      for (var i = 0; i < segments; i++) {
        final a0 = i * 2 * pi / segments;
        final a1 = (i + 1) * 2 * pi / segments;
        _drawClippedLine(
          canvas,
          viewProj,
          size,
          Vec3(r * cos(a0), groundY, r * sin(a0)),
          Vec3(r * cos(a1), groundY, r * sin(a1)),
          paint,
        );
      }
    }

    // 12 Radial turntable spokes
    const spokeCount = 12;
    final maxR = radii.last;
    for (var i = 0; i < spokeCount; i++) {
      final angle = i * 2 * pi / spokeCount;
      final isCardinal = i % 3 == 0;
      _drawClippedLine(
        canvas,
        viewProj,
        size,
        Vec3(0, groundY, 0),
        Vec3(maxR * cos(angle), groundY, maxR * sin(angle)),
        isCardinal ? axisSpokePaint : spokePaint,
      );
    }

    // Degree tick marks on 3.5m ring
    const tickR1 = 3.35;
    const tickR2 = 3.65;
    const tickCount = 24;
    final tickPaint = Paint()
      ..color = const Color(0x4034D399)
      ..strokeWidth = 1.0;
    for (var i = 0; i < tickCount; i++) {
      final angle = i * 2 * pi / tickCount;
      _drawClippedLine(
        canvas,
        viewProj,
        size,
        Vec3(tickR1 * cos(angle), groundY, tickR1 * sin(angle)),
        Vec3(tickR2 * cos(angle), groundY, tickR2 * sin(angle)),
        tickPaint,
      );
    }
  }

  void _drawHexGrid(Canvas canvas, Mat4 viewProj, Size size, double groundY) {
    final hexPaint = Paint()
      ..color = const Color(0x2210B981)
      ..strokeWidth = 1.0;
    final hexCenterPaint = Paint()
      ..color = const Color(0x4534D399)
      ..strokeWidth = 1.2;

    const r = 0.65;
    const dx = 1.5 * r;
    const dz = 1.73205 * r;
    const range = 3;

    for (var q = -range; q <= range; q++) {
      for (var rCol = -range; rCol <= range; rCol++) {
        final cx = q * dx;
        final cz = (rCol * dz) + (q.abs() % 2 == 1 ? dz * 0.5 : 0.0);
        final dist = sqrt(cx * cx + cz * cz);
        if (dist > 4.5) continue;

        final isCenter = dist < 1.5;
        final currentPaint = isCenter ? hexCenterPaint : hexPaint;

        for (var i = 0; i < 6; i++) {
          final a0 = i * pi / 3.0;
          final a1 = (i + 1) * pi / 3.0;
          _drawClippedLine(
            canvas,
            viewProj,
            size,
            Vec3(cx + r * cos(a0), groundY, cz + r * sin(a0)),
            Vec3(cx + r * cos(a1), groundY, cz + r * sin(a1)),
            currentPaint,
          );
        }
      }
    }
  }

  void _drawCheckerGrid(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
  ) {
    const extent = 4.0;
    const step = 1.0;

    final fillPaintA = Paint()
      ..color = const Color(0x1610B981)
      ..style = PaintingStyle.fill;
    final fillPaintB = Paint()
      ..color = const Color(0x0610B981)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0x2834D399)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final centerCrossPaint = Paint()
      ..color = const Color(0x6010B981)
      ..strokeWidth = 1.6;

    for (var x = -extent; x < extent; x += step) {
      for (var z = -extent; z < extent; z += step) {
        final isEven =
            (((x + extent) / step).round() + ((z + extent) / step).round()) %
                2 ==
            0;
        final poly = [
          Vec3(x, groundY, z),
          Vec3(x + step, groundY, z),
          Vec3(x + step, groundY, z + step),
          Vec3(x, groundY, z + step),
        ];

        _drawClippedPolygon(
          canvas,
          viewProj,
          size,
          poly,
          isEven ? fillPaintA : fillPaintB,
        );
        _drawClippedPolygon(canvas, viewProj, size, poly, borderPaint);
      }
    }

    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(-extent, groundY, 0),
      Vec3(extent, groundY, 0),
      centerCrossPaint,
    );
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(0, groundY, -extent),
      Vec3(0, groundY, extent),
      centerCrossPaint,
    );
  }

  void _drawModelSolid(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
    Vec3 eye,
  ) {
    final totalTriangles = model!.instances.fold<int>(
      0,
      (sum, instance) => sum + instance.triangles.length,
    );

    if (totalTriangles == 0) {
      // Fall back to clean wireframe of the original model if no triangle faces exist.
      _drawModelWireframe(canvas, size, project);
      return;
    }

    // Hard triangle budget: strictly cap processed triangles to 2,400 total.
    // In Flutter Web, 2,400 triangles rendered via drawVertices runs in a single GPU draw call (~0.1ms).
    const triangleBudget = 2400;
    final stride = max(1, (totalTriangles / triangleBudget).ceil());

    // Precalculate lighting directions once outside loop
    final keyLight = switch (lighting) {
      ViewerLighting.studio => const Vec3(-0.50, 0.82, 0.40),
      ViewerLighting.daylight => const Vec3(-0.55, 0.95, 0.15),
      ViewerLighting.night => const Vec3(0.35, 0.55, -0.75),
      ViewerLighting.flat => const Vec3(0, 1, 0),
    }.normalized;
    final fillLight = const Vec3(0.50, -0.30, -0.40).normalized;
    final kx = keyLight.x, ky = keyLight.y, kz = keyLight.z;
    final fx = fillLight.x, fy = fillLight.y, fz = fillLight.z;
    final isFlat = lighting == ViewerLighting.flat;

    final faces = <_SolidTriangle>[];

    for (final instance in model!.instances) {
      final triangles = instance.triangles;
      final numTriangles = triangles.length;
      if (numTriangles == 0) continue;

      final isSelected = instance.nodeIndex == selectedNodeIndex;
      final Color baseMeshColor = isSelected ? const Color(0xFF00E5FF) : bodyColor;

      final verts = instance.worldVertices;
      final numVerts = verts.length;

      for (var i = 0; i < numTriangles; i += stride) {
        final triangle = triangles[i];
        final ia = triangle.a;
        final ib = triangle.b;
        final ic = triangle.c;

        if (ia >= numVerts || ib >= numVerts || ic >= numVerts) {
          continue;
        }

        final v0 = verts[ia];
        final v1 = verts[ib];
        final v2 = verts[ic];

        // Transform 3 vertices to clip space directly (0 list allocations)
        final c0 = viewProj.transformClip(v0);
        final c1 = viewProj.transformClip(v1);
        final c2 = viewProj.transformClip(v2);

        // Near plane culling
        if (c0[3] <= 0.05 && c1[3] <= 0.05 && c2[3] <= 0.05) {
          continue;
        }

        // Face normal in world space
        final e1x = v1.x - v0.x;
        final e1y = v1.y - v0.y;
        final e1z = v1.z - v0.z;
        final e2x = v2.x - v0.x;
        final e2y = v2.y - v0.y;
        final e2z = v2.z - v0.z;

        var nx = e1y * e2z - e1z * e2y;
        var ny = e1z * e2x - e1x * e2z;
        var nz = e1x * e2y - e1y * e2x;
        final nLenSq = nx * nx + ny * ny + nz * nz;
        if (nLenSq < 1e-10) continue;
        final invNLen = 1.0 / sqrt(nLenSq);
        nx *= invNLen;
        ny *= invNLen;
        nz *= invNLen;

        // Centroid & view vector
        final cx = (v0.x + v1.x + v2.x) * (1.0 / 3.0);
        final cy = (v0.y + v1.y + v2.y) * (1.0 / 3.0);
        final cz = (v0.z + v1.z + v2.z) * (1.0 / 3.0);

        final toEyeX = eye.x - cx;
        final toEyeY = eye.y - cy;
        final toEyeZ = eye.z - cz;
        final depthSq = toEyeX * toEyeX + toEyeY * toEyeY + toEyeZ * toEyeZ;
        if (depthSq < 1e-10) continue;
        final invEyeDist = 1.0 / sqrt(depthSq);
        final eyex = toEyeX * invEyeDist;
        final eyey = toEyeY * invEyeDist;
        final eyez = toEyeZ * invEyeDist;

        var ndotEye = nx * eyex + ny * eyey + nz * eyez;
        // Two-sided surface shading matching Blender Solid viewport
        if (ndotEye < 0) {
          nx = -nx;
          ny = -ny;
          nz = -nz;
          ndotEye = -ndotEye;
        }

        Offset? p0;
        Offset? p1;
        Offset? p2;

        if (c0[3] > 0.05 && c1[3] > 0.05 && c2[3] > 0.05) {
          final invW0 = 1.0 / c0[3];
          final sx0 = (c0[0] * invW0 * 0.5 + 0.5) * size.width + panX;
          final sy0 = (1.0 - (c0[1] * invW0 * 0.5 + 0.5)) * size.height + panY;

          final invW1 = 1.0 / c1[3];
          final sx1 = (c1[0] * invW1 * 0.5 + 0.5) * size.width + panX;
          final sy1 = (1.0 - (c1[1] * invW1 * 0.5 + 0.5)) * size.height + panY;

          final invW2 = 1.0 / c2[3];
          final sx2 = (c2[0] * invW2 * 0.5 + 0.5) * size.width + panX;
          final sy2 = (1.0 - (c2[1] * invW2 * 0.5 + 0.5)) * size.height + panY;

          // 2D screen viewport frustum culling
          final minX = min(sx0, min(sx1, sx2));
          final maxX = max(sx0, max(sx1, sx2));
          if (maxX < 0 || minX > size.width) continue;
          final minY = min(sy0, min(sy1, sy2));
          final maxY = max(sy0, max(sy1, sy2));
          if (maxY < 0 || minY > size.height) continue;

          p0 = Offset(sx0, sy0);
          p1 = Offset(sx1, sy1);
          p2 = Offset(sx2, sy2);
        }

        final Color baseColor = isSelected
            ? const Color(0xFF00E5FF)
            : (triangle.color ?? baseMeshColor);

        final Color shadedColor;
        if (isFlat) {
          shadedColor = baseColor;
        } else {
          final dotKey = nx * kx + ny * ky + nz * kz;
          final diffuseKey = dotKey > 0.0 ? dotKey : 0.0;

          final dotFill = nx * fx + ny * fy + nz * fz;
          final diffuseFill = dotFill > 0.0 ? dotFill * 0.22 : 0.0;

          // Blinn-Phong specular highlight via 4 successive squarings
          final hx = kx + eyex;
          final hy = ky + eyey;
          final hz = kz + eyez;
          final hLenSq = hx * hx + hy * hy + hz * hz;
          double specular = 0.0;
          if (hLenSq > 1e-6) {
            final invHLen = 1.0 / sqrt(hLenSq);
            final ndoth = nx * (hx * invHLen) + ny * (hy * invHLen) + nz * (hz * invHLen);
            if (ndoth > 0.0) {
              final x2 = ndoth * ndoth;
              final x4 = x2 * x2;
              final x8 = x4 * x4;
              final x16 = x8 * x8;
              specular = (x16 * x2) * 0.38;
            }
          }

          // Fresnel rim light
          final oneMinusNdot = 1.0 - (ndotEye > 1.0 ? 1.0 : ndotEye);
          final f2 = oneMinusNdot * oneMinusNdot;
          final fresnel = (f2 * sqrt(oneMinusNdot)) * 0.24;

          final factor = (0.32 + diffuseKey * 0.55 + diffuseFill + specular + fresnel)
              .clamp(0.20, 1.25);

          final r = ((baseColor.r * 255.0) * factor).round().clamp(0, 255);
          final g = ((baseColor.g * 255.0) * factor).round().clamp(0, 255);
          final b = ((baseColor.b * 255.0) * factor).round().clamp(0, 255);
          shadedColor = Color.fromARGB((baseColor.a * 255.0).round().clamp(0, 255), r, g, b);
        }

        if (p0 != null && p1 != null && p2 != null) {
          faces.add(
            _SolidTriangle(
              p0: p0,
              p1: p1,
              p2: p2,
              depth: depthSq,
              color: shadedColor,
            ),
          );
        } else {
          faces.add(
            _SolidTriangle(
              vertices: [v0, v1, v2],
              depth: depthSq,
              color: shadedColor,
            ),
          );
        }
      }
    }

    // Painter's algorithm: sort faces from furthest to nearest
    faces.sort((a, b) => b.depth.compareTo(a.depth));

    // Batch all 2D triangles into a single GPU draw call via canvas.drawVertices
    final positions = <Offset>[];
    final colors = <Color>[];
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (final face in faces) {
      if (face.p0 != null && face.p1 != null && face.p2 != null) {
        positions.add(face.p0!);
        positions.add(face.p1!);
        positions.add(face.p2!);
        colors.add(face.color);
        colors.add(face.color);
        colors.add(face.color);
      } else if (face.vertices != null) {
        _drawClippedPolygon(
          canvas,
          viewProj,
          size,
          face.vertices!,
          fillPaint..color = face.color,
        );
      }
    }

    if (positions.isNotEmpty) {
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
      );
      canvas.drawVertices(vertices, BlendMode.src, Paint());
    }
  }

  Color _shadeSolidColor(Color base, Vec3 normal, Vec3 center, Vec3 eye) {
    // Blender 2-light Studio Setup:
    // Key light (dominant upper-left) + Fill light (soft counter-fill) + Specular + Fresnel rim
    final keyLight = switch (lighting) {
      ViewerLighting.studio => const Vec3(-0.50, 0.82, 0.40),
      ViewerLighting.daylight => const Vec3(-0.55, 0.95, 0.15),
      ViewerLighting.night => const Vec3(0.35, 0.55, -0.75),
      ViewerLighting.flat => const Vec3(0, 1, 0),
    }.normalized;

    final fillLight = const Vec3(0.50, -0.30, -0.40).normalized;
    final toEye = (eye - center).normalized;

    final diffuseKey = max(0.0, normal.dot(keyLight));
    final diffuseFill = max(0.0, normal.dot(fillLight)) * 0.22;

    // Specular Blinn-Phong highlight via fast squarings
    final halfVector = (keyLight + toEye).normalized;
    final ndoth = max(0.0, normal.dot(halfVector));
    final x2 = ndoth * ndoth;
    final x4 = x2 * x2;
    final x8 = x4 * x4;
    final x16 = x8 * x8;
    final specular = (x16 * x2) * 0.38;

    // Silhouette Fresnel rim light
    final ndotv = max(0.0, normal.dot(toEye));
    final oneMinusNdot = 1.0 - (ndotv > 1.0 ? 1.0 : ndotv);
    final f2 = oneMinusNdot * oneMinusNdot;
    final fresnel = (f2 * sqrt(oneMinusNdot)) * 0.24;

    final ambient = 0.32;
    final factor = lighting == ViewerLighting.flat
        ? 0.95
        : (ambient + diffuseKey * 0.55 + diffuseFill + specular + fresnel)
            .clamp(0.20, 1.25);

    int ch(double v) => (v * 255.0 * factor).round().clamp(0, 255);
    final a = (base.a * 255.0).round().clamp(0, 255);
    return Color.fromARGB(
      a,
      ch(base.r),
      ch(base.g),
      ch(base.b),
    );
  }

  void _drawModelWireframe(
    Canvas canvas,
    Size size,
    Offset? Function(Vec3) project,
  ) {
    final wheelNodeSet =
        detection?.wheels
            .expand(
              (w) => w.partNodeIndices.isEmpty
                  ? <int>[w.nodeIndex]
                  : w.partNodeIndices,
            )
            .toSet() ??
        {};
    final selectedBodyNodeIndex = bodyNodeIndex ?? detection?.body?.nodeIndex;
    final totalEdges = model!.instances.fold<int>(
      0,
      (sum, instance) => sum + instance.edges.length,
    );
    // Projecting sampled edges bounds browser rendering to solid 60 FPS
    final edgeBudget = denseWireframe ? 4000 : 1800;
    final edgeStride = max(1, (totalEdges / edgeBudget).ceil());

    final path = Path();

    for (final inst in model!.instances) {
      Color edgeColor;
      double strokeWidth = 1.0;

      if (inst.nodeIndex == selectedNodeIndex) {
        edgeColor = const Color(0xFF00E5FF);
        strokeWidth = 1.8;
      } else if (wheelNodeSet.contains(inst.nodeIndex)) {
        edgeColor = wheelColor;
        strokeWidth = 1.3;
      } else if (inst.nodeIndex == selectedBodyNodeIndex) {
        edgeColor = bodyColor;
        strokeWidth = 1.1;
      } else {
        edgeColor = wireColor;
        strokeWidth = 0.9;
      }

      final paint = Paint()
        ..color = edgeColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      final verts = inst.worldVertices;
      final edges = inst.edges;
      final numVerts = verts.length;
      if (numVerts == 0 || edges.isEmpty) continue;

      path.reset();
      var hasLines = false;
      for (var i = 0; i < edges.length; i += edgeStride) {
        final e = edges[i];
        if (e.a < numVerts && e.b < numVerts) {
          final p0 = project(verts[e.a]);
          final p1 = project(verts[e.b]);
          if (p0 != null && p1 != null) {
            path.moveTo(p0.dx, p0.dy);
            path.lineTo(p1.dx, p1.dy);
            hasLines = true;
          }
        }
      }
      if (hasLines) {
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawProceduralSolidCar(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Vec3 eye,
  ) {
    final carPaintColor = bodyColor;
    const trimColor = Color(0xFF141916);
    const grilleColor = Color(0xFF0A0E0C);
    const glassColor = Color(0xFF15252D);
    const headlightColor = Color(0xFFE0F7FD);
    const taillightColor = Color(0xFFFF1E44);
    const exhaustColor = Color(0xFFCBD5E1);
    const diffuserColor = Color(0xFF0F1411);

    // 28 key feature vertices for a modern sports car with aerodynamic curves
    final bodyPoints = [
      // 0-3: Front lower splitter
      const Vec3(-0.92, 0.16, -1.98), // 0: Front-Left splitter
      const Vec3(0.92, 0.16, -1.98),  // 1: Front-Right splitter
      const Vec3(0.00, 0.16, -2.05),  // 2: Front-Center splitter nose
      const Vec3(0.00, 0.34, -2.00),  // 3: Front-Center bumper nose

      // 4-7: Lower bumper & grille intake
      const Vec3(-0.88, 0.36, -1.90), // 4: Front-Left bumper corner
      const Vec3(0.88, 0.36, -1.90),  // 5: Front-Right bumper corner
      const Vec3(-0.55, 0.22, -1.92), // 6: Grille-Left lower
      const Vec3(0.55, 0.22, -1.92),  // 7: Grille-Right lower
      const Vec3(-0.55, 0.44, -1.86), // 8: Grille-Left upper
      const Vec3(0.55, 0.44, -1.86),  // 9: Grille-Right upper

      // 10-13: Headlights & hood front
      const Vec3(-0.84, 0.62, -1.72), // 10: Headlight-Left outer
      const Vec3(-0.48, 0.64, -1.80), // 11: Headlight-Left inner
      const Vec3(0.48, 0.64, -1.80),  // 12: Headlight-Right inner
      const Vec3(0.84, 0.62, -1.72),  // 13: Headlight-Right outer

      // 14-17: Hood cowl & windshield base
      const Vec3(-0.82, 0.84, -0.62), // 14: Windshield base Left
      const Vec3(0.00, 0.88, -0.58),  // 15: Windshield base Center
      const Vec3(0.82, 0.84, -0.62),  // 16: Windshield base Right
      const Vec3(0.00, 0.72, -1.15),  // 17: Hood power-dome center

      // 18-21: Roof & greenhouse
      const Vec3(-0.64, 1.34, -0.15), // 18: Roof front Left
      const Vec3(0.64, 1.34, -0.15),  // 19: Roof front Right
      const Vec3(-0.64, 1.33, 0.78),  // 20: Roof rear Left
      const Vec3(0.64, 1.33, 0.78),   // 21: Roof rear Right

      // 22-25: Rear window base & ducktail spoiler
      const Vec3(-0.80, 0.86, 1.38),  // 22: Rear window base Left
      const Vec3(0.80, 0.86, 1.38),   // 23: Rear window base Right
      const Vec3(-0.86, 0.90, 1.90),  // 24: Ducktail spoiler Left
      const Vec3(0.00, 0.94, 1.94),   // 25: Ducktail spoiler Center
      const Vec3(0.86, 0.90, 1.90),   // 26: Ducktail spoiler Right

      // 27-30: Taillight strip & rear bumper
      const Vec3(-0.86, 0.76, 1.92),  // 27: Taillight Left
      const Vec3(0.86, 0.76, 1.92),   // 28: Taillight Right
      const Vec3(-0.90, 0.22, 1.92),  // 29: Rear diffuser Left
      const Vec3(0.90, 0.22, 1.92),   // 30: Rear diffuser Right

      // 31-42: Realistic wheel arches and sculpted door sills
      // Front-Left wheel arch (centered at z = -1.25, r = 0.35)
      const Vec3(-0.90, 0.22, -1.65), // 31: Front-Left arch forward
      const Vec3(-0.94, 0.74, -1.25), // 32: Front-Left arch apex
      const Vec3(-0.90, 0.22, -0.85), // 33: Front-Left arch aft

      // Rear-Left wheel arch (centered at z = 1.25, r = 0.35)
      const Vec3(-0.90, 0.22, 0.85),  // 34: Rear-Left arch forward
      const Vec3(-0.95, 0.76, 1.25),  // 35: Rear-Left arch apex
      const Vec3(-0.90, 0.22, 1.65),  // 36: Rear-Left arch aft

      // Front-Right wheel arch
      const Vec3(0.90, 0.22, -1.65),  // 37: Front-Right arch forward
      const Vec3(0.94, 0.74, -1.25),  // 38: Front-Right arch apex
      const Vec3(0.90, 0.22, -0.85),  // 39: Front-Right arch aft

      // Rear-Right wheel arch
      const Vec3(0.90, 0.22, 0.85),   // 40: Rear-Right arch forward
      const Vec3(0.95, 0.76, 1.25),   // 41: Rear-Right arch apex
      const Vec3(0.90, 0.22, 1.65),   // 42: Rear-Right arch aft

      // Door sill lower edge center points
      const Vec3(-0.90, 0.20, 0.00),  // 43: Left door sill center
      const Vec3(0.90, 0.20, 0.00),   // 44: Right door sill center
    ];

    final faces = <_SolidTriangle>[];

    void addPolygonFace(List<Vec3> verts, Color baseColor) {
      if (verts.length < 3) return;
      var normal =
          (verts[1] - verts[0]).cross(verts[2] - verts[0]).normalized;
      if (normal.lengthSquared < 1e-10) return;
      var cx = 0.0, cy = 0.0, cz = 0.0;
      for (final v in verts) {
        cx += v.x;
        cy += v.y;
        cz += v.z;
      }
      final center =
          Vec3(cx / verts.length, cy / verts.length, cz / verts.length);
      final toEye = eye - center;

      // Two-sided surface orientation matching Blender Solid viewport
      if (normal.dot(toEye) < 0) {
        normal = -normal;
      }

      final clips = verts.map(viewProj.transformClip).toList();
      if (clips.every((c) => c[3] <= 0.05)) return;

      faces.add(
        _SolidTriangle(
          vertices: verts,
          depth: toEye.lengthSquared,
          color: _shadeSolidColor(baseColor, normal, center, eye),
        ),
      );
    }

    void addQuad(int a, int b, int c, int d, Color color) {
      addPolygonFace([bodyPoints[a], bodyPoints[b], bodyPoints[c], bodyPoints[d]], color);
    }

    void addTri(int a, int b, int c, Color color) {
      addPolygonFace([bodyPoints[a], bodyPoints[b], bodyPoints[c]], color);
    }

    // ── Front Splitter & Air Dam ──────────────────────────────────────────
    addTri(0, 2, 4, trimColor);
    addTri(2, 1, 5, trimColor);
    addTri(2, 3, 4, carPaintColor);
    addTri(2, 5, 3, carPaintColor);

    // ── Front Center Grille Intake ────────────────────────────────────────
    addQuad(6, 7, 9, 8, grilleColor);

    // ── Left Headlight ────────────────────────────────────────────────────
    addTri(4, 10, 11, headlightColor);
    addTri(4, 11, 8, carPaintColor);

    // ── Right Headlight ───────────────────────────────────────────────────
    addTri(5, 12, 13, headlightColor);
    addTri(5, 9, 12, carPaintColor);

    // ── Front Hood with Power Dome ────────────────────────────────────────
    addTri(3, 11, 17, carPaintColor);
    addTri(3, 17, 12, carPaintColor);
    addTri(11, 10, 14, carPaintColor);
    addTri(11, 14, 17, carPaintColor);
    addTri(17, 14, 15, carPaintColor);
    addTri(12, 17, 16, carPaintColor);
    addTri(17, 15, 16, carPaintColor);
    addTri(13, 12, 16, carPaintColor);

    // ── Windshield ────────────────────────────────────────────────────────
    addTri(14, 18, 15, glassColor);
    addTri(16, 15, 19, glassColor);
    addTri(15, 18, 19, glassColor);

    // ── Roof Canopy ───────────────────────────────────────────────────────
    addQuad(18, 20, 21, 19, carPaintColor);

    // ── Side Windows ──────────────────────────────────────────────────────
    addQuad(14, 22, 20, 18, glassColor); // Left window
    addQuad(16, 19, 21, 23, glassColor); // Right window

    // ── Fastback Rear Window ──────────────────────────────────────────────
    addQuad(20, 22, 23, 21, glassColor);

    // ── Trunk & Ducktail Spoiler ──────────────────────────────────────────
    addTri(22, 24, 25, carPaintColor);
    addTri(23, 25, 26, carPaintColor);
    addTri(22, 25, 23, carPaintColor);

    // ── Full-Width LED Red Taillight Strip ────────────────────────────────
    addQuad(24, 27, 28, 26, taillightColor);

    // ── Rear Bumper & Diffuser ────────────────────────────────────────────
    addQuad(27, 29, 30, 28, diffuserColor);

    // Dual Quad Exhaust Tips
    addPolygonFace([
      const Vec3(-0.58, 0.22, 1.94),
      const Vec3(-0.42, 0.22, 1.94),
      const Vec3(-0.42, 0.32, 1.94),
      const Vec3(-0.58, 0.32, 1.94),
    ], exhaustColor);
    addPolygonFace([
      const Vec3(0.42, 0.22, 1.94),
      const Vec3(0.58, 0.22, 1.94),
      const Vec3(0.58, 0.32, 1.94),
      const Vec3(0.42, 0.32, 1.94),
    ], exhaustColor);

    // ── Left Side Body & Fenders with Wheel Arches ─────────────────────────
    addTri(4, 31, 10, carPaintColor); // Front corner to arch front
    addTri(10, 31, 32, carPaintColor); // Front fender over wheel arch
    addTri(10, 32, 14, carPaintColor); // Fender upper to windshield cowl
    addTri(14, 32, 33, carPaintColor); // Arch rear to A-pillar base
    addQuad(33, 34, 22, 14, carPaintColor); // Sculpted door panel
    addTri(33, 43, 34, trimColor); // Door sill rocker skirt
    addTri(22, 34, 35, carPaintColor); // Muscular rear quarter over arch
    addTri(22, 35, 24, carPaintColor); // Quarter upper to spoiler
    addTri(24, 35, 36, carPaintColor); // Quarter rear down to arch aft
    addTri(24, 36, 29, carPaintColor); // Quarter aft to rear diffuser

    // ── Right Side Body & Fenders with Wheel Arches ────────────────────────
    addTri(5, 13, 37, carPaintColor); // Front corner to arch front
    addTri(13, 38, 37, carPaintColor); // Front fender over wheel arch
    addTri(13, 16, 38, carPaintColor); // Fender upper to windshield cowl
    addTri(16, 38, 39, carPaintColor); // Arch rear to A-pillar base
    addQuad(39, 16, 23, 40, carPaintColor); // Sculpted door panel
    addTri(39, 40, 44, trimColor); // Door sill rocker skirt
    addTri(23, 41, 40, carPaintColor); // Muscular rear quarter over arch
    addTri(23, 26, 41, carPaintColor); // Quarter upper to spoiler
    addTri(26, 41, 42, carPaintColor); // Quarter rear down to arch aft
    addTri(26, 42, 30, carPaintColor); // Quarter aft to rear diffuser

    // ── Undercarriage Floor ───────────────────────────────────────────────
    addPolygonFace([
      bodyPoints[0],
      bodyPoints[1],
      bodyPoints[30],
      bodyPoints[29],
    ], const Color(0xFF0C100E));

    // ── 4 Wheels: 3D Solid Alloy Wheels with Rubber Tires & Brake Calipers ─
    final wheelPositions = detection?.wheels.isNotEmpty == true
        ? detection!.wheels.map((w) => w.worldPosition).toList()
        : const [
            Vec3(-0.95, 0.35, -1.25), // FL
            Vec3(0.95, 0.35, -1.25),  // FR
            Vec3(-0.95, 0.35, 1.25),  // RL
            Vec3(0.95, 0.35, 1.25),   // RR
          ];
    const wheelRadius = 0.35;
    const wheelWidth = 0.26;
    const segments = 16;
    const tireColor = Color(0xFF1B201D);
    const rimColor = Color(0xFFBAC7CE);
    const rimPocketColor = Color(0xFF263238);
    const caliperColor = Color(0xFFDC2626); // Sport red brake caliper

    for (var wIdx = 0; wIdx < wheelPositions.length; wIdx++) {
      final center = wheelPositions[wIdx];
      final isLeft = center.x < 0;
      final outerX =
          isLeft ? center.x - wheelWidth / 2 : center.x + wheelWidth / 2;
      final innerX =
          isLeft ? center.x + wheelWidth / 2 : center.x - wheelWidth / 2;

      final outerVerts = <Vec3>[];
      final innerVerts = <Vec3>[];

      for (var i = 0; i < segments; i++) {
        final angle = i * 2 * pi / segments;
        final sy = wheelRadius * sin(angle);
        final sz = wheelRadius * cos(angle);
        outerVerts.add(Vec3(outerX, center.y + sy, center.z + sz));
        innerVerts.add(Vec3(innerX, center.y + sy, center.z + sz));
      }

      // Red brake caliper behind the rim
      final caliperX = outerX + (isLeft ? 0.05 : -0.05);
      addPolygonFace([
        Vec3(caliperX, center.y + 0.10, center.z + 0.12),
        Vec3(caliperX, center.y + 0.24, center.z + 0.08),
        Vec3(caliperX, center.y + 0.22, center.z - 0.06),
        Vec3(caliperX, center.y + 0.08, center.z - 0.04),
      ], caliperColor);

      // Outer disc (5-spoke sculpted alloy rim face)
      final outerCenter = Vec3(outerX, center.y, center.z);
      for (var i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        final triVerts = isLeft
            ? [outerCenter, outerVerts[i], outerVerts[next]]
            : [outerCenter, outerVerts[next], outerVerts[i]];
        // 5-spoke styling with dark pockets
        final isSpoke = (i % 3 == 0);
        addPolygonFace(triVerts, isSpoke ? rimColor : rimPocketColor);
      }

      // Inner disc
      final innerCenter = Vec3(innerX, center.y, center.z);
      for (var i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        final triVerts = isLeft
            ? [innerCenter, innerVerts[next], innerVerts[i]]
            : [innerCenter, innerVerts[i], innerVerts[next]];
        addPolygonFace(triVerts, tireColor);
      }

      // Tread quads connecting outer and inner rims
      for (var i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        final quadVerts = isLeft
            ? [outerVerts[next], outerVerts[i], innerVerts[i], innerVerts[next]]
            : [outerVerts[i], outerVerts[next], innerVerts[next], innerVerts[i]];
        addPolygonFace(quadVerts, tireColor);
      }
    }

    // Sort all faces from furthest to nearest (Painter's algorithm)
    faces.sort((a, b) => b.depth.compareTo(a.depth));

    // Render solid polygons with single reused fill paint
    final fillPaint = Paint()..style = PaintingStyle.fill;
    for (final face in faces) {
      if (face.vertices != null) {
        _drawClippedPolygon(
          canvas,
          viewProj,
          size,
          face.vertices!,
          fillPaint..color = face.color,
        );
      }
    }
  }

  void _drawProceduralWireframeCar(
    Canvas canvas,
    Size size,
    Offset? Function(Vec3) project,
  ) {
    final bodyPaint = Paint()
      ..color = bodyColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    final wheelPaint = Paint()
      ..color = wheelColor
      ..strokeWidth = 1.4;

    // Body chassis wireframe vertices
    final bodyCorners = [
      // Bottom frame: FL, FR, RR, RL
      const Vec3(-0.9, 0.2, -1.8),
      const Vec3(0.9, 0.2, -1.8),
      const Vec3(0.9, 0.2, 1.8),
      const Vec3(-0.9, 0.2, 1.8),
      // Hood line
      const Vec3(-0.85, 0.7, -1.6),
      const Vec3(0.85, 0.7, -1.6),
      // Windshield base
      const Vec3(-0.8, 0.85, -0.6),
      const Vec3(0.8, 0.85, -0.6),
      // Roof top
      const Vec3(-0.65, 1.35, -0.2),
      const Vec3(0.65, 1.35, -0.2),
      const Vec3(-0.65, 1.35, 0.8),
      const Vec3(0.65, 1.35, 0.8),
      // Rear window base
      const Vec3(-0.8, 0.85, 1.3),
      const Vec3(0.8, 0.85, 1.3),
      // Trunk end
      const Vec3(-0.85, 0.75, 1.75),
      const Vec3(0.85, 0.75, 1.75),
    ];

    final bodyLines = [
      // Bottom loop
      [0, 1], [1, 2], [2, 3], [3, 0],
      // Hood
      [0, 4], [1, 5], [4, 5],
      // Windshield
      [4, 6], [5, 7], [6, 7],
      // A-pillars
      [6, 8], [7, 9], [8, 9],
      // Roof
      [8, 10], [9, 11], [10, 11],
      // C-pillars
      [10, 12], [11, 13], [12, 13],
      // Trunk
      [12, 14], [13, 15], [14, 15],
      // Trunk to bottom
      [14, 3], [15, 2],
    ];

    for (final edge in bodyLines) {
      final p0 = project(bodyCorners[edge[0]]);
      final p1 = project(bodyCorners[edge[1]]);
      if (p0 != null && p1 != null) canvas.drawLine(p0, p1, bodyPaint);
    }

    // Four procedural wheels
    final wheelCenters = [
      const Vec3(-0.95, 0.35, -1.2), // FL
      const Vec3(0.95, 0.35, -1.2), // FR
      const Vec3(-0.95, 0.35, 1.2), // RL
      const Vec3(0.95, 0.35, 1.2), // RR
    ];

    for (final wc in wheelCenters) {
      _drawWireWheel(canvas, project, wc, 0.35, wheelPaint);
    }
  }

  void _drawWireWheel(
    Canvas canvas,
    Offset? Function(Vec3) project,
    Vec3 center,
    double radius,
    Paint paint,
  ) {
    const segments = 12;
    for (var i = 0; i < segments; i++) {
      final a0 = i * 2 * pi / segments;
      final a1 = (i + 1) * 2 * pi / segments;
      // Outer rim
      final p0 = project(center + Vec3(0, radius * sin(a0), radius * cos(a0)));
      final p1 = project(center + Vec3(0, radius * sin(a1), radius * cos(a1)));
      if (p0 != null && p1 != null) canvas.drawLine(p0, p1, paint);

      // Spokes
      final hub = project(center);
      if (hub != null && p0 != null && i % 3 == 0) {
        canvas.drawLine(hub, p0, paint);
      }
    }
  }

  void _drawMarkers(Canvas canvas, Size size, Offset? Function(Vec3) project) {
    final wheels = detection?.wheels ?? [];

    for (final w in wheels) {
      final pos = project(w.worldPosition);
      if (pos == null) continue;

      // Marker circle
      final markerPaint = Paint()
        ..color = wheelColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 5, markerPaint);

      final ringPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pos, 8, ringPaint);

      // Pulsing animated ring
      final pulseRadius = 7.0 + pulseProgress * 13.0;
      final pulseAlpha = (1.0 - pulseProgress).clamp(0.0, 1.0);
      final pulsePaint = Paint()
        ..color = wheelColor.withValues(alpha: pulseAlpha * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(pos, pulseRadius, pulsePaint);

      // Label
      final span = TextSpan(
        text: w.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          backgroundColor: Color(0xD017232B),
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, pos + const Offset(10, -7));
    }

    // Center of mass marker
    final comPos = project(Vec3(0, centerOfMassY, 0));
    if (comPos != null) {
      final comPaint = Paint()
        ..color = const Color(0xFFFF5252)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(comPos, 4, comPaint);

      final span = TextSpan(
        text: 'CoM (${centerOfMassY.toStringAsFixed(2)}m)',
        style: const TextStyle(
          color: Color(0xFFFF8A80),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0xD017232B),
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, comPos + const Offset(8, -6));
    }
  }
}
