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
  bool _showGrid = true;
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
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: _showGrid ? 'Hide Grid' : 'Show Grid',
                  icon: Icon(
                    _showGrid ? Icons.grid_4x4_rounded : Icons.grid_off_rounded,
                    color: _showGrid
                        ? const Color(0xFF8BA2B0)
                        : const Color(0xFF71818B),
                  ),
                  onPressed: () => setState(() => _showGrid = !_showGrid),
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

    // ── 1. Draw 3D Ground Grid ──────────────────────────────────────────────
    if (showGrid) {
      final gridPaint = Paint()
        ..color = const Color(0x1F455A64)
        ..strokeWidth = 1.0;
      final axisPaint = Paint()
        ..color = const Color(0x35607D8B)
        ..strokeWidth = 1.2;

      final groundY = model?.worldBBox.lo.y ?? 0.0;
      const extent = 4.0;
      const step = 0.5;

      for (var x = -extent; x <= extent; x += step) {
        final p0 = projectPoint(Vec3(x, groundY, -extent));
        final p1 = projectPoint(Vec3(x, groundY, extent));
        if (p0 != null && p1 != null) {
          canvas.drawLine(p0, p1, x == 0 ? axisPaint : gridPaint);
        }
      }
      for (var z = -extent; z <= extent; z += step) {
        final p0 = projectPoint(Vec3(-extent, groundY, z));
        final p1 = projectPoint(Vec3(extent, groundY, z));
        if (p0 != null && p1 != null) {
          canvas.drawLine(p0, p1, z == 0 ? axisPaint : gridPaint);
        }
      }
    }

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
