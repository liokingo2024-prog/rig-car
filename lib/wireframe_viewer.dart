import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'model_data.dart';

// ── 3D Wireframe Viewer ─────────────────────────────────────────────────────
//
// Interactive 3D viewport that renders the parsed model mesh as a wireframe,
// highlights detected wheels and body parts, and renders 3D markers for wheels
// and center of mass. Supports orbit, zoom, pan, and view presets.

enum CameraPreset { iso, front, side, top }

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

  // Camera spherical coordinates
  double _azimuth = 0.785; // 45 degrees
  double _elevation = 0.45; // ~26 degrees
  double _distance = 6.0;
  Vec3 _target = Vec3.zero;
  double _panX = 0;
  double _panY = 0;

  bool _showMarkers = true;
  GroundGridStyle _gridStyle = GroundGridStyle.cad;
  bool get _showGrid => _gridStyle != GroundGridStyle.off;
  bool _invertDrag = false;
  final bool _denseWireframe = true;

  @override
  void initState() {
    super.initState();
    _resetCameraToModel();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(() {
        if (_autoTurntable) {
          setState(() {
            _azimuth += 0.007;
          });
        }
      });
    _animController.repeat();
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
  }

  void _setPreset(CameraPreset preset) {
    setState(() {
      switch (preset) {
        case CameraPreset.iso:
          _azimuth = 0.785;
          _elevation = 0.45;
        case CameraPreset.front:
          _azimuth = 3.14159; // facing -Z
          _elevation = 0.05;
        case CameraPreset.side:
          _azimuth = 1.5708; // facing +X
          _elevation = 0.05;
        case CameraPreset.top:
          _azimuth = 0.0;
          _elevation = 1.56; // near 90 deg up
      }
    });
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
                    return CustomPaint(
                      painter: _WireframeScenePainter(
                        model: widget.model,
                        detection: widget.detection,
                        selectedNodeIndex: widget.selectedNodeIndex,
                        azimuth: _azimuth,
                        elevation: _elevation,
                        distance: _distance,
                        target: _target,
                        panX: _panX,
                        panY: _panY,
                        gridStyle: _gridStyle,
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
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Badge(
                              icon: Icons.view_in_ar_rounded,
                              label: widget.model != null
                                  ? widget.model!.fileName
                                  : 'Procedural 3D Rig',
                              color: widget.model != null
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF34D399),
                            ),
                            const SizedBox(width: 8),
                            if (widget.detection != null &&
                                widget.detection!.wheels.isNotEmpty)
                              _Badge(
                                icon: Icons.check_circle_outline,
                                label:
                                    '${widget.detection!.wheels.length}/4 Wheels Rigged',
                                color: widget.detection!.wheels.length >= 4
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF34D399),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onTestDrive != null) ...[
                              FilledButton.icon(
                                onPressed: widget.onTestDrive,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: const Color(0xFF041D14),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                  elevation: 3,
                                  shadowColor: const Color(0x6010B981),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.sports_motorsports_rounded,
                                    size: 14),
                                label: const Text(
                                  'TEST DRIVE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // View presets
                            _PresetButton(
                                'ISO', () => _setPreset(CameraPreset.iso)),
                            const SizedBox(width: 4),
                            _PresetButton(
                                'TOP', () => _setPreset(CameraPreset.top)),
                            const SizedBox(width: 4),
                            _PresetButton(
                                'SIDE', () => _setPreset(CameraPreset.side)),
                            const SizedBox(width: 4),
                            _PresetButton(
                                'FRONT', () => _setPreset(CameraPreset.front)),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: _autoTurntable
                                  ? 'Pause Turntable'
                                  : 'Auto 360° Turntable',
                              icon: Icon(
                                _autoTurntable
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.rotate_right_rounded,
                                color: _autoTurntable
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFBAC7CE),
                              ),
                              onPressed: () => setState(
                                  () => _autoTurntable = !_autoTurntable),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filledTonal(
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Reset View',
                              icon: const Icon(Icons.refresh_rounded),
                              onPressed: () => setState(_resetCameraToModel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
            child: Row(
              children: [
                _LegendItem(
                  color: widget.wheelColor,
                  label: 'Wheels',
                ),
                const SizedBox(width: 12),
                _LegendItem(
                  color: widget.bodyColor,
                  label: 'Body',
                ),
                const SizedBox(width: 12),
                _LegendItem(
                  color: widget.wireColor,
                  label: 'Chassis / Misc',
                ),
                const Spacer(),
                // Toggle markers
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
                  onPressed: () =>
                      setState(() => _showMarkers = !_showMarkers),
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
                              fontWeight:
                                  isSel ? FontWeight.w700 : FontWeight.w500,
                              color: isSel
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFC9D1D9),
                            ),
                          ),
                          if (isSel) ...[
                            const Spacer(),
                            const Icon(Icons.check,
                                size: 14, color: Color(0xFF10B981)),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
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
                    _invertDrag ? Icons.swap_vertical_circle_rounded : Icons.swap_vertical_circle_outlined,
                    color: _invertDrag
                        ? const Color(0xFF10B981)
                        : const Color(0xFF8BA2B0),
                  ),
                  onPressed: () =>
                      setState(() => _invertDrag = !_invertDrag),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small UI Widgets ────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111714),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC9D1D9),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xC0111714),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF223127)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFB0BCC3),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
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

class _WireframeScenePainter extends CustomPainter {
  const _WireframeScenePainter({
    required this.model,
    required this.detection,
    required this.selectedNodeIndex,
    required this.azimuth,
    required this.elevation,
    required this.distance,
    required this.target,
    required this.panX,
    required this.panY,
    this.gridStyle = GroundGridStyle.cad,
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
  final int? selectedNodeIndex;
  final double azimuth;
  final double elevation;
  final double distance;
  final Vec3 target;
  final double panX;
  final double panY;
  final GroundGridStyle gridStyle;
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
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Background gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF141F27), Color(0xFF0C1318)],
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

    // ── 2. Draw Model Wireframe OR Procedural Rig ────────────────────────────
    if (model != null && model!.instances.isNotEmpty) {
      _drawModelWireframe(canvas, size, projectPoint);
    } else {
      _drawProceduralWireframeCar(canvas, size, projectPoint);
    }

    // ── 3. Draw Detected Wheel Markers ──────────────────────────────────────
    if (showMarkers) {
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
    final sy0 = (1.0 - (final0[1] / final0[3] * 0.5 + 0.5)) * size.height + panY;
    final sx1 = (final1[0] / final1[3] * 0.5 + 0.5) * size.width + panX;
    final sy1 = (1.0 - (final1[1] / final1[3] * 0.5 + 0.5)) * size.height + panY;

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
    final minX = bbox != null ? bbox.lo.x * 0.95 : -0.85;
    final maxX = bbox != null ? bbox.hi.x * 0.95 : 0.85;
    final minZ = bbox != null ? bbox.lo.z * 0.95 : -1.6;
    final maxZ = bbox != null ? bbox.hi.z * 0.95 : 1.6;

    final centerX = (minX + maxX) * 0.5;
    final centerZ = (minZ + maxZ) * 0.5;
    final halfW = (maxX - minX) * 0.5;
    final halfL = (maxZ - minZ) * 0.5;

    // Smooth multi-layer ambient occlusion hull
    List<Vec3> makeHull(double wScale, double lScale, double y) {
      const segs = 16;
      final verts = <Vec3>[];
      for (var i = 0; i < segs; i++) {
        final a = i * 2 * pi / segs;
        final x = centerX + sin(a) * halfW * wScale;
        final z = centerZ + cos(a) * halfL * lScale;
        verts.add(Vec3(x, y, z));
      }
      return verts;
    }

    // Outer soft penumbra
    final outerVerts = makeHull(1.28, 1.22, groundY);
    _drawClippedPolygon(canvas, viewProj, size, outerVerts,
        Paint()..color = const Color(0x18000000)..style = PaintingStyle.fill);

    // Middle ambient occlusion
    final midVerts = makeHull(1.05, 1.05, groundY + 0.001);
    _drawClippedPolygon(canvas, viewProj, size, midVerts,
        Paint()..color = const Color(0x35000000)..style = PaintingStyle.fill);

    // Inner contact core under chassis
    final innerVerts = makeHull(0.82, 0.82, groundY + 0.002);
    _drawClippedPolygon(canvas, viewProj, size, innerVerts,
        Paint()..color = const Color(0x65000000)..style = PaintingStyle.fill);

    // Tire contact footprints directly under the 4 wheels
    final wheelPositions = [
      Vec3(minX * 0.95, groundY + 0.003, minZ * 0.78),
      Vec3(maxX * 0.95, groundY + 0.003, minZ * 0.78),
      Vec3(minX * 0.95, groundY + 0.003, maxZ * 0.78),
      Vec3(maxX * 0.95, groundY + 0.003, maxZ * 0.78),
    ];

    const tireHalfW = 0.14;
    const tireHalfL = 0.28;
    final tirePaint = Paint()
      ..color = const Color(0x95000000)
      ..style = PaintingStyle.fill;

    for (final wp in wheelPositions) {
      _drawClippedPolygon(canvas, viewProj, size, [
        Vec3(wp.x - tireHalfW, wp.y, wp.z - tireHalfL),
        Vec3(wp.x + tireHalfW, wp.y, wp.z - tireHalfL),
        Vec3(wp.x + tireHalfW, wp.y, wp.z + tireHalfL),
        Vec3(wp.x - tireHalfW, wp.y, wp.z + tireHalfL),
      ], tirePaint);
    }
  }

  void _drawCadGrid(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
  ) {
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
      final paint =
          isAxis ? axisZPaint : (isMajor ? majorGridPaint : minorGridPaint);
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
      final paint =
          isAxis ? axisXPaint : (isMajor ? majorGridPaint : minorGridPaint);
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
    _drawClippedLine(canvas, viewProj, size, Vec3(-extent, groundY, -extent),
        Vec3(extent, groundY, -extent), framePaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(extent, groundY, -extent),
        Vec3(extent, groundY, extent), framePaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(extent, groundY, extent),
        Vec3(-extent, groundY, extent), framePaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(-extent, groundY, extent),
        Vec3(-extent, groundY, -extent), framePaint);
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

  void _drawHexGrid(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
  ) {
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

        _drawClippedPolygon(canvas, viewProj, size, poly, isEven ? fillPaintA : fillPaintB);
        _drawClippedPolygon(canvas, viewProj, size, poly, borderPaint);
      }
    }

    _drawClippedLine(canvas, viewProj, size, Vec3(-extent, groundY, 0),
        Vec3(extent, groundY, 0), centerCrossPaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(0, groundY, -extent),
        Vec3(0, groundY, extent), centerCrossPaint);
  }

  void _drawModelWireframe(
    Canvas canvas,
    Size size,
    Offset? Function(Vec3) project,
  ) {
    final wheelNodeSet =
        detection?.wheels.map((w) => w.nodeIndex).toSet() ?? {};
    final bodyNodeIndex = detection?.body?.nodeIndex;

    for (final inst in model!.instances) {
      Color edgeColor;
      double strokeWidth = 1.0;

      if (inst.nodeIndex == selectedNodeIndex) {
        edgeColor = const Color(0xFF00E5FF);
        strokeWidth = 1.8;
      } else if (wheelNodeSet.contains(inst.nodeIndex)) {
        edgeColor = wheelColor;
        strokeWidth = 1.3;
      } else if (inst.nodeIndex == bodyNodeIndex) {
        edgeColor = bodyColor;
        strokeWidth = 1.1;
      } else {
        edgeColor = wireColor;
        strokeWidth = 0.9;
      }

      final paint = Paint()
        ..color = edgeColor
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;

      final verts = inst.worldVertices;
      final edges = inst.edges;

      final step = (!denseWireframe && edges.length > 2000)
          ? (edges.length ~/ 2000)
          : 1;

      for (var i = 0; i < edges.length; i += step) {
        final e = edges[i];
        if (e.a < verts.length && e.b < verts.length) {
          final p0 = project(verts[e.a]);
          final p1 = project(verts[e.b]);
          if (p0 != null && p1 != null) {
            canvas.drawLine(p0, p1, paint);
          }
        }
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
      const Vec3(0.95, 0.35, -1.2),  // FR
      const Vec3(-0.95, 0.35, 1.2),  // RL
      const Vec3(0.95, 0.35, 1.2),   // RR
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
      final p0 = project(
        center + Vec3(0, radius * sin(a0), radius * cos(a0)),
      );
      final p1 = project(
        center + Vec3(0, radius * sin(a1), radius * cos(a1)),
      );
      if (p0 != null && p1 != null) canvas.drawLine(p0, p1, paint);

      // Spokes
      final hub = project(center);
      if (hub != null && p0 != null && i % 3 == 0) {
        canvas.drawLine(hub, p0, paint);
      }
    }
  }

  void _drawMarkers(
    Canvas canvas,
    Size size,
    Offset? Function(Vec3) project,
  ) {
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
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
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
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, comPos + const Offset(8, -6));
    }
  }

  @override
  bool shouldRepaint(covariant _WireframeScenePainter oldDelegate) => true;
}
