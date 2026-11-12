import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'fullscreen.dart';
import 'auto_detector.dart';
import 'model_data.dart';
import 'physics_sim.dart';
import 'sketchfab_viewport.dart';
import 'solid_mesh_lod.dart';

// ── Godot 4 Interactive Test Drive Viewport ─────────────────────────────────
//
// Full-screen real-time driving simulation with Godot 4 VehicleBody3D physics,
// spring chase camera, procedural track with slalom obstacles, tire skid marks,
// drift mechanics, and a glassmorphic cyber racing HUD.

enum CameraMode { chase, orbit, hood }

enum TestDriveRenderMode {
  solid('Solid', Icons.view_in_ar_rounded),
  wireframe('Wireframe', Icons.grid_4x4_rounded),
  hybrid('Hybrid', Icons.layers_rounded);

  const TestDriveRenderMode(this.label, this.icon);
  final String label;
  final IconData icon;

  TestDriveRenderMode get next {
    final idx = (index + 1) % TestDriveRenderMode.values.length;
    return TestDriveRenderMode.values[idx];
  }
}

enum TestDriveLighting {
  day('Day Bright', 'Day', Icons.wb_sunny_rounded),
  sunset('Golden Sunset', 'Sunset', Icons.wb_twilight_rounded),
  night('Night Proving', 'Night', Icons.nightlight_round);

  const TestDriveLighting(this.label, this.shortName, this.icon);
  final String label;
  final String shortName;
  final IconData icon;

  TestDriveLighting get next {
    final idx = (index + 1) % TestDriveLighting.values.length;
    return TestDriveLighting.values[idx];
  }
}

enum TrackSurfaceStyle {
  circuit('Circuit Asphalt', 'Circuit', Icons.sports_score_rounded),
  skidpad('Proving Skidpad', 'Skidpad', Icons.motion_photos_on_rounded),
  dragstrip('Runway Drag Strip', 'Runway', Icons.straighten_rounded),
  cyberGrid('Cyber Matrix', 'Matrix', Icons.hive_rounded);

  const TrackSurfaceStyle(this.label, this.shortName, this.icon);
  final String label;
  final String shortName;
  final IconData icon;

  TrackSurfaceStyle get next {
    final idx = (index + 1) % TrackSurfaceStyle.values.length;
    return TrackSurfaceStyle.values[idx];
  }
}

class TestDriveViewport extends StatefulWidget {
  const TestDriveViewport({
    super.key,
    required this.mass,
    required this.engineForce,
    required this.grip,
    required this.suspension,
    required this.centerOfMass,
    required this.drive,
    required this.frontSteering,
    required this.rearSteering,
    required this.frontTraction,
    required this.rearTraction,
    required this.wheelPositions,
    this.model,
    this.detection,
    this.accentColor = const Color(0xFF10B981),
    this.isFullscreen,
    this.onToggleFullscreen,
    this.onExit,
    this.steerAngle = 36.0,
    this.springRestLength = 0.18,
    this.springStiffness = 42.0,
    this.dampingCompression = 2.4,
    this.assignedWheels = const {},
    this.soundProfile = 'v10',
    this.sirenEnabled = false,
    this.tireSkidAudioEnabled = true,
  });

  final double mass;
  final double engineForce;
  final double grip;
  final double suspension;
  final double centerOfMass;
  final String drive;
  final bool frontSteering;
  final bool rearSteering;
  final bool frontTraction;
  final bool rearTraction;
  final List<Vec3> wheelPositions;
  final ParsedModel? model;
  final DetectionResult? detection;
  final Color accentColor;
  final bool? isFullscreen;
  final ValueChanged<bool>? onToggleFullscreen;
  final VoidCallback? onExit;
  final double steerAngle;
  final double springRestLength;
  final double springStiffness;
  final double dampingCompression;
  final Map<String, DetectedWheel?> assignedWheels;
  final String soundProfile;
  final bool sirenEnabled;
  final bool tireSkidAudioEnabled;

  /// Builds the local transform matrix that rotates a wheel about its true hub center [hub],
  /// applying [roll] along the lateral axle and [steer] around the vertical spindle axis,
  /// and translates to [hub] + [alignOffset].
  static Mat4 buildWheelLocalMatrix(
    Vec3 hub,
    Vec3 alignOffset,
    double steer,
    double roll,
  ) {
    final cs = cos(steer);
    final ss = sin(steer);
    final cr = cos(roll);
    final sr = sin(roll);

    // R = R_steer * R_roll
    // R_steer (about +Y): [cs, 0, ss; 0, 1, 0; -ss, 0, cs]
    // R_roll (about +X):  [1, 0, 0; 0, cr, -sr; 0, sr, cr]
    // Product R = R_steer * R_roll:
    final r00 = cs;
    final r10 = 0.0;
    final r20 = -ss;

    final r01 = ss * sr;
    final r11 = cr;
    final r21 = cs * sr;

    final r02 = ss * cr;
    final r12 = -sr;
    final r22 = cs * cr;

    // R * hub
    final rhX = r00 * hub.x + r01 * hub.y + r02 * hub.z;
    final rhY = r10 * hub.x + r11 * hub.y + r12 * hub.z;
    final rhZ = r20 * hub.x + r21 * hub.y + r22 * hub.z;

    // T = (hub + alignOffset) - R * hub
    final tx = (hub.x + alignOffset.x) - rhX;
    final ty = (hub.y + alignOffset.y) - rhY;
    final tz = (hub.z + alignOffset.z) - rhZ;

    return Mat4([
      r00, r10, r20, 0.0,
      r01, r11, r21, 0.0,
      r02, r12, r22, 0.0,
      tx, ty, tz, 1.0,
    ]);
  }

  /// Multiplies a vector by R^T (the transpose/inverse of R_steer * R_roll)
  /// for lighting and normal transformation.
  static Vec3 applyWheelRotTranspose(Vec3 v, double steer, double roll) {
    final cs = cos(steer);
    final ss = sin(steer);
    final cr = cos(roll);
    final sr = sin(roll);

    final r00 = cs;
    final r20 = -ss;

    final r01 = ss * sr;
    final r11 = cr;
    final r21 = cs * sr;

    final r02 = ss * cr;
    final r12 = -sr;
    final r22 = cs * cr;

    return Vec3(
      r00 * v.x + r20 * v.z,
      r01 * v.x + r11 * v.y + r21 * v.z,
      r02 * v.x + r12 * v.y + r22 * v.z,
    );
  }

  @override
  State<TestDriveViewport> createState() => _TestDriveViewportState();
}

class _TestDriveViewportState extends State<TestDriveViewport>
    with SingleTickerProviderStateMixin {
  late final VehiclePhysicsSimulation _sim;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  bool _internalFullscreen = false;
  bool get _isFullscreen => widget.isFullscreen ?? _internalFullscreen;

  void _toggleFullscreen() {
    final next = !_isFullscreen;
    setState(() => _internalFullscreen = next);
    widget.onToggleFullscreen?.call(next);
    toggleBrowserFullscreen();
  }

  CameraMode _cameraMode = CameraMode.chase;
  TestDriveLighting _lighting = TestDriveLighting.day;
  TrackSurfaceStyle _trackStyle = TrackSurfaceStyle.circuit;
  TestDriveRenderMode _renderMode = TestDriveRenderMode.solid;
  double _orbitAzimuth = 0.785;
  double _orbitElevation = 0.35;
  final double _orbitDistance = 7.5;

  // Chase cam smoothed position
  Vec3 _chaseCamPos = const Vec3(0, 3.2, 32);
  Vec3 _chaseCamTarget = const Vec3(0, 1.0, 24);

  // Time tracking
  Duration _lastTick = Duration.zero;

  // Active keyboard inputs
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  // Touch pedal inputs
  bool _touchGas = false;
  bool _touchBrake = false;
  bool _touchSteerLeft = false;
  bool _touchSteerRight = false;
  bool _touchHandbrake = false;

  // Animated pulse for UI
  double _uiPulse = 0.0;

  @override
  void initState() {
    super.initState();
    _sim = VehiclePhysicsSimulation(
      mass: widget.mass,
      engineForce: widget.engineForce,
      grip: widget.grip,
      suspension: widget.suspension,
      centerOfMass: widget.centerOfMass,
      drive: widget.drive,
      frontSteering: widget.frontSteering,
      rearSteering: widget.rearSteering,
      frontTraction: widget.frontTraction,
      rearTraction: widget.rearTraction,
      wheelPositions: widget.wheelPositions,
      maxSteerAngleDegrees: widget.steerAngle,
      springRestLength: widget.springRestLength,
      springStiffness: widget.springStiffness,
      dampingCompression: widget.dampingCompression,
    );

    // Initial camera position behind car
    _chaseCamPos = _sim.position + const Vec3(0, 2.6, 7.0);
    _chaseCamTarget = _sim.position + const Vec3(0, 0.8, -1.0);

    _ticker = createTicker(_onTick)..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    updateSketchfabSkidAudio(false, false);
    stopSketchfabEngineAudio();
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }

    final dtMs = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    // Clamp dt to avoid physics blowups on lag spikes
    final dt = dtMs.clamp(0.001, 0.045);

    // Determine inputs (keyboard + touch)
    var throttle = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp) ||
        _touchGas) {
      throttle += 1.0;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
        _touchBrake) {
      throttle -= 1.0;
    }

    var steer = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft) ||
        _touchSteerLeft) {
      steer -= 1.0;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight) ||
        _touchSteerRight) {
      steer += 1.0;
    }

    final handbrake = _pressedKeys.contains(LogicalKeyboardKey.space) ||
        _touchHandbrake;

    // Step physics
    _sim.step(
      dt,
      throttleInput: throttle,
      steerInput: steer,
      handbrake: handbrake,
    );

    updateSketchfabSkidAudio(_sim.isDrifting, widget.tireSkidAudioEnabled);
    updateSketchfabEngineAudio(
      _sim.engineRpm,
      throttle,
      widget.soundProfile,
      widget.sirenEnabled,
    );

    // Update chase camera
    _updateChaseCamera(dt);

    // Update UI pulse
    _uiPulse = (_uiPulse + dt * 3.0) % (2 * pi);

    setState(() {});
  }

  void _updateChaseCamera(double dt) {
    final yaw = _sim.yaw;
    final fwd = Vec3(-sin(yaw), 0, -cos(yaw));
    final up = const Vec3(0, 1, 0);

    // Target position is behind and above the car
    final camDistance = 6.2 + (_sim.speedKmh / 160.0).clamp(0.0, 3.0);
    final camHeight = 2.4 - (_sim.speedKmh / 200.0).clamp(0.0, 0.4);
    final desiredPos = _sim.position - (fwd * camDistance) + (up * camHeight);

    // Look slightly ahead of car
    final desiredTarget = _sim.position + (fwd * 2.5) + (up * 0.7);

    // Smooth spring interpolation
    final lerpRate = (dt * 6.5).clamp(0.0, 1.0);
    _chaseCamPos = _chaseCamPos + (desiredPos - _chaseCamPos) * lerpRate;
    _chaseCamTarget = _chaseCamTarget + (desiredTarget - _chaseCamTarget) * lerpRate;
  }

  void _resetCar() {
    _sim.reset();
    _chaseCamPos = _sim.position + const Vec3(0, 2.6, 7.0);
    _chaseCamTarget = _sim.position + const Vec3(0, 0.8, -1.0);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);

      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        _resetCar();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        setState(() {
          _cameraMode = CameraMode.values[
              (_cameraMode.index + 1) % CameraMode.values.length];
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_isFullscreen) {
          _toggleFullscreen();
        } else {
          widget.onExit?.call();
        }
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        onPanUpdate: (details) {
          if (_cameraMode == CameraMode.orbit) {
            setState(() {
              _orbitAzimuth -= details.delta.dx * 0.008;
              _orbitElevation = (_orbitElevation + details.delta.dy * 0.008)
                  .clamp(0.05, 1.4);
            });
          }
        },
        child: Stack(
          children: [
            // 3D Canvas
            Positioned.fill(
              child: CustomPaint(
                painter: _TestDriveScenePainter(
                  sim: _sim,
                  cameraMode: _cameraMode,
                  lighting: _lighting,
                  trackStyle: _trackStyle,
                  renderMode: _renderMode,
                  chaseCamPos: _chaseCamPos,
                  chaseCamTarget: _chaseCamTarget,
                  orbitAzimuth: _orbitAzimuth,
                  orbitElevation: _orbitElevation,
                  orbitDistance: _orbitDistance,
                  model: widget.model,
                  detection: widget.detection,
                  accentColor: widget.accentColor,
                  uiPulse: _uiPulse,
                  assignedWheels: widget.assignedWheels,
                  soundProfile: widget.soundProfile,
                  sirenEnabled: widget.sirenEnabled,
                ),
              ),
            ),

            // Top Control Bar
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: _buildTopBar(),
            ),

            // Telemetry Bottom Panel & Controls
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: _buildBottomHud(),
            ),

            // Keyboard Helper Badge
            Positioned(
              top: 72,
              left: 16,
              child: _buildControlsHint(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xF0111714),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSpecBadge = constraints.maxWidth >= 1400;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Cluster: Exit & Title
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Exit button
                      InkWell(
                        onTap: () => widget.onExit?.call(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back,
                                  size: 14, color: Color(0xFFC9D1D9)),
                              SizedBox(width: 5),
                              Text(
                                'EXIT TEST DRIVE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFC9D1D9),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Godot Engine title & status
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'GODOT 4 VEHICLE SIMULATOR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF0FDF4),
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (showSpecBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: Text(
                            '${_sim.drive} • ${_sim.mass.toInt()}KG • ${_sim.engineForce.toInt()}HP • ${widget.soundProfile.toUpperCase()}${widget.sirenEnabled ? ' • SIREN' : ''}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF86978C),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(width: 12),

                  // Right Cluster: Render Mode, Camera, Surface, Lighting, Fullscreen, Reset
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Render Mode selector (Solid / Wireframe / Hybrid)
                      PopupMenuButton<TestDriveRenderMode>(
                        tooltip: 'Render View: ${_renderMode.label}',
                        initialValue: _renderMode,
                        onSelected: (mode) => setState(() => _renderMode = mode),
                        color: const Color(0xFF111714),
                        surfaceTintColor: Colors.transparent,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF223127)),
                        ),
                        itemBuilder: (context) => TestDriveRenderMode.values.map((mode) {
                          final isSel = mode == _renderMode;
                          return PopupMenuItem<TestDriveRenderMode>(
                            value: mode,
                            height: 38,
                            child: Row(
                              children: [
                                Icon(mode.icon, size: 16, color: isSel ? const Color(0xFF10B981) : const Color(0xFF86978C)),
                                const SizedBox(width: 8),
                                Text(mode.label, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? const Color(0xFFF0FDF4) : const Color(0xFFC9D1D9))),
                                if (isSel) ...[
                                  const Spacer(),
                                  const Icon(Icons.check, size: 14, color: Color(0xFF10B981)),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_renderMode.icon, size: 13, color: const Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                _renderMode.label.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF34D399), letterSpacing: 0.4),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.arrow_drop_down, size: 13, color: Color(0xFF34D399)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Camera selector
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: CameraMode.values.map((mode) {
                          final isSel = _cameraMode == mode;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: InkWell(
                              onTap: () => setState(() => _cameraMode = mode),
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(0xFF1A231E)
                                      : const Color(0xFF111714),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: isSel
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF223127),
                                  ),
                                ),
                                child: Text(
                                  mode.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? const Color(0xFFF0FDF4)
                                        : const Color(0xFF86978C),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(width: 6),

                      // Track Surface Selector (Circuit, Skidpad, Runway, Matrix)
                      PopupMenuButton<TrackSurfaceStyle>(
                        tooltip: 'Track Surface: ${_trackStyle.label}',
                        initialValue: _trackStyle,
                        onSelected: (style) =>
                            setState(() => _trackStyle = style),
                        color: const Color(0xFF111714),
                        surfaceTintColor: Colors.transparent,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF223127)),
                        ),
                        itemBuilder: (context) =>
                            TrackSurfaceStyle.values.map((style) {
                          final isSel = style == _trackStyle;
                          return PopupMenuItem<TrackSurfaceStyle>(
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
                                  const Icon(Icons.check,
                                      size: 14, color: Color(0xFF10B981)),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(5),
                            border:
                                Border.all(color: const Color(0xFF223127)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_trackStyle.icon,
                                  size: 13, color: const Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                _trackStyle.shortName,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34D399),
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.arrow_drop_down,
                                  size: 13, color: Color(0xFF34D399)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Time of Day / Lighting Selector (Day Bright, Sunset, Night)
                      PopupMenuButton<TestDriveLighting>(
                        tooltip: 'Environment Lighting: ${_lighting.label}',
                        initialValue: _lighting,
                        onSelected: (l) => setState(() => _lighting = l),
                        color: const Color(0xFF111714),
                        surfaceTintColor: Colors.transparent,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF223127)),
                        ),
                        itemBuilder: (context) =>
                            TestDriveLighting.values.map((l) {
                          final isSel = l == _lighting;
                          return PopupMenuItem<TestDriveLighting>(
                            value: l,
                            height: 38,
                            child: Row(
                              children: [
                                Icon(
                                  l.icon,
                                  size: 16,
                                  color: isSel
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF86978C),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l.label,
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
                                  const Icon(Icons.check,
                                      size: 14, color: Color(0xFF10B981)),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(5),
                            border:
                                Border.all(color: const Color(0xFF223127)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_lighting.icon,
                                  size: 13, color: const Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                _lighting.shortName,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34D399),
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.arrow_drop_down,
                                  size: 13, color: Color(0xFF34D399)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Fullscreen toggle button
                      InkWell(
                        onTap: _toggleFullscreen,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isFullscreen
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isFullscreen
                                  ? const Color(0xFF34D399)
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
                                size: 15,
                                color: _isFullscreen
                                    ? const Color(0xFF041D14)
                                    : const Color(0xFFF0FDF4),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isFullscreen ? 'EXIT FULL (F)' : 'FULLSCREEN (F)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _isFullscreen
                                      ? const Color(0xFF041D14)
                                      : const Color(0xFFF0FDF4),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Reset button
                      InkWell(
                        onTap: _resetCar,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh,
                                  size: 14, color: Color(0xFFC9D1D9)),
                              SizedBox(width: 4),
                              Text(
                                'RESET (R)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFC9D1D9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlsHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE0111714),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard, size: 13, color: Color(0xFF86978C)),
          SizedBox(width: 6),
          Text(
            'WASD / ARROWS: Drive  •  SPACE: Handbrake  •  C: Camera  •  F: Fullscreen  •  R: Reset  •  ESC: Exit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF86978C),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomHud() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Touch Left Controls: Steering & Handbrake
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildTouchSteeringCluster(),
                    const SizedBox(width: 14),
                    _buildVehicleTelemetryCluster(),
                  ],
                ),

                const SizedBox(width: 14),

                // Right HUD: Drift, Speedometer & Touch Pedals
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_sim.isDrifting) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xE010B981),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x6610B981),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department,
                                color: Color(0xFF041D14), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'DRIFTING',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF041D14),
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    _buildSpeedometerCluster(),
                    const SizedBox(width: 14),
                    _buildTouchPedalCluster(),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTouchSteeringCluster() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xE6111714),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHoldButton(
                icon: Icons.arrow_back,
                label: 'STEER L',
                active: _touchSteerLeft,
                onHold: (v) => setState(() => _touchSteerLeft = v),
              ),
              const SizedBox(width: 8),
              _buildHoldButton(
                icon: Icons.arrow_forward,
                label: 'STEER R',
                active: _touchSteerRight,
                onHold: (v) => setState(() => _touchSteerRight = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildHoldButton(
            icon: Icons.handyman,
            label: 'HANDBRAKE',
            color: const Color(0xFF10B981),
            active: _touchHandbrake,
            width: 140,
            onHold: (v) => setState(() => _touchHandbrake = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTouchPedalCluster() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xE6111714),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHoldButton(
            icon: Icons.arrow_downward,
            label: 'BRAKE/REV',
            color: const Color(0xFFF85149),
            active: _touchBrake,
            width: 72,
            height: 70,
            onHold: (v) => setState(() => _touchBrake = v),
          ),
          const SizedBox(width: 8),
          _buildHoldButton(
            icon: Icons.arrow_upward,
            label: 'GAS',
            color: const Color(0xFF10B981),
            active: _touchGas,
            width: 72,
            height: 70,
            onHold: (v) => setState(() => _touchGas = v),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldButton({
    required IconData icon,
    required String label,
    required bool active,
    required ValueChanged<bool> onHold,
    Color color = const Color(0xFF10B981),
    double width = 66,
    double height = 48,
  }) {
    return Listener(
      onPointerDown: (_) => onHold(true),
      onPointerUp: (_) => onHold(false),
      onPointerCancel: (_) => onHold(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : const Color(0xFF1A231E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : const Color(0xFF223127),
            width: active ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? color : const Color(0xFFC9D1D9)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? color : const Color(0xFF8B949E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTelemetryCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6111714),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // G-Force Vector Meter
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'G-METER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              CustomPaint(
                size: const Size(64, 64),
                painter: _GMeterPainter(
                  latG: _sim.lateralG,
                  longG: _sim.longitudinalG,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_sim.lateralG.abs().toStringAsFixed(2)}G',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF0FDF4),
                ),
              ),
            ],
          ),

          const SizedBox(width: 14),
          Container(width: 1, height: 68, color: const Color(0xFF223127)),
          const SizedBox(width: 14),

          // 4-Wheel Slip & Suspension Telemetry
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TIRE SLIP & SUSPENSION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildWheelBar('FL', _sim.wheelSlips[0],
                      _sim.wheelSuspensionCompressions[0]),
                  const SizedBox(width: 8),
                  _buildWheelBar('FR', _sim.wheelSlips[1],
                      _sim.wheelSuspensionCompressions[1]),
                  const SizedBox(width: 12),
                  _buildWheelBar('RL', _sim.wheelSlips[2],
                      _sim.wheelSuspensionCompressions[2]),
                  const SizedBox(width: 8),
                  _buildWheelBar('RR', _sim.wheelSlips[3],
                      _sim.wheelSuspensionCompressions[3]),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheelBar(String name, double slip, double comp) {
    Color barColor;
    if (slip > 0.6) {
      barColor = const Color(0xFFF85149);
    } else if (slip > 0.3) {
      barColor = const Color(0xFFD29922);
    } else {
      barColor = const Color(0xFF10B981);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: Color(0xFF86978C),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 10,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF1A231E),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 10,
            height: (slip.clamp(0.05, 1.0)) * 38,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(slip * 100).toInt()}%',
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            color: barColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedometerCluster() {
    final gearStr = _sim.currentGear == -1
        ? 'R'
        : (_sim.currentGear == 0 ? 'N' : '${_sim.currentGear}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE6111714),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Speed digits
              Text(
                '${_sim.speedKmh.toInt()}',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF0FDF4),
                  letterSpacing: -1.0,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'KM/H',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 16),

              // Gear badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A231E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF223127),
                  ),
                ),
                child: Text(
                  gearStr,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _sim.currentGear == -1
                        ? const Color(0xFFF85149)
                        : const Color(0xFFF0FDF4),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // RPM Tachometer Bar
          SizedBox(
            width: 195,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_sim.engineRpm.toInt()} RPM',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF86978C),
                      ),
                    ),
                    const Text(
                      'REDLINE 7.5K',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF5252),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_sim.engineRpm / 7800.0).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFF16201B),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _sim.engineRpm > 6500
                          ? const Color(0xFFFF5252)
                          : (_sim.engineRpm > 4800
                              ? const Color(0xFF34D399)
                              : const Color(0xFF10B981)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── G-Meter Painter ─────────────────────────────────────────────────────────

class _GMeterPainter extends CustomPainter {
  final double latG;
  final double longG;
  const _GMeterPainter({required this.latG, required this.longG});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer circle
    final circlePaint = Paint()
      ..color = const Color(0xFF223127)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(c, r, circlePaint);
    canvas.drawCircle(c, r * 0.5, circlePaint);

    // Crosshairs
    final linePaint = Paint()
      ..color = const Color(0xFF16201B)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), linePaint);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), linePaint);

    // G point offset
    // 1G maps to 0.7 * radius
    final dx = (latG * (r * 0.7)).clamp(-r * 0.9, r * 0.9);
    final dy = (-longG * (r * 0.7)).clamp(-r * 0.9, r * 0.9);
    final pt = Offset(c.dx + dx, c.dy + dy);

    // Trail line
    final trailPaint = Paint()
      ..color = const Color(0x6010B981)
      ..strokeWidth = 1.2;
    canvas.drawLine(c, pt, trailPaint);

    // Point
    final gPointPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pt, 3.0, gPointPaint);
  }

  @override
  bool shouldRepaint(covariant _GMeterPainter oldDelegate) =>
      oldDelegate.latG != latG || oldDelegate.longG != longG;
}

// ── 3D Scene CustomPainter ──────────────────────────────────────────────────

class _TestDriveScenePainter extends CustomPainter {
  const _TestDriveScenePainter({
    required this.sim,
    required this.cameraMode,
    this.lighting = TestDriveLighting.day,
    this.trackStyle = TrackSurfaceStyle.circuit,
    this.renderMode = TestDriveRenderMode.solid,
    required this.chaseCamPos,
    required this.chaseCamTarget,
    required this.orbitAzimuth,
    required this.orbitElevation,
    required this.orbitDistance,
    required this.model,
    this.detection,
    required this.accentColor,
    required this.uiPulse,
    this.assignedWheels = const {},
    this.soundProfile = 'v10',
    this.sirenEnabled = false,
  });

  final VehiclePhysicsSimulation sim;
  final CameraMode cameraMode;
  final TestDriveLighting lighting;
  final TrackSurfaceStyle trackStyle;
  final TestDriveRenderMode renderMode;
  final Vec3 chaseCamPos;
  final Vec3 chaseCamTarget;
  final double orbitAzimuth;
  final double orbitElevation;
  final double orbitDistance;
  final ParsedModel? model;
  final DetectionResult? detection;
  final Color accentColor;
  final double uiPulse;
  final Map<String, DetectedWheel?> assignedWheels;
  final String soundProfile;
  final bool sirenEnabled;

  Map<String, DetectedWheel> get _resolvedWheels {
    final result = <String, DetectedWheel>{};
    for (final corner in const ['FL', 'FR', 'RL', 'RR']) {
      final assigned = assignedWheels[corner];
      if (assigned != null) {
        result[corner] = assigned;
        continue;
      }
      if (detection != null) {
        for (final w in detection!.wheels) {
          final isFront = w.axle == 'front';
          final isLeft = w.side == 'left';
          final key = (isFront ? 'F' : 'R') + (isLeft ? 'L' : 'R');
          if (key == corner) {
            result[corner] = w;
            break;
          }
        }
      }
    }
    if (result.length < 4 && model != null) {
      final autoResult = AutoDetector.detect(
        model!,
        pruneUnderWheelObjects: false,
        autoAlignForward: false,
        snapToLand: false,
      );
      for (final corner in const ['FL', 'FR', 'RL', 'RR']) {
        if (!result.containsKey(corner)) {
          for (final w in autoResult.wheels) {
            final isFront = w.axle == 'front';
            final isLeft = w.side == 'left';
            final key = (isFront ? 'F' : 'R') + (isLeft ? 'L' : 'R');
            if (key == corner) {
              result[corner] = w;
              break;
            }
          }
        }
      }
    }

    // Safety Pass: Guard against chassis/body nodes being assigned to wheel transforms
    if (model != null && model!.instances.isNotEmpty) {
      final carBox = model!.worldBBox;
      final fAxisIsZ = carBox.size.z.abs() >= carBox.size.x.abs();
      final carLen = max(carBox.size.z.abs(), carBox.size.x.abs());
      final carW = min(carBox.size.z.abs(), carBox.size.x.abs());
      final carH = carBox.size.y.abs();
      final nonWheel = <int>{};
      if (detection?.body != null) nonWheel.add(detection!.body!.nodeIndex);
      for (final inst in model!.instances) {
        final s = inst.worldBBox.size;
        final maxDim = max(s.x.abs(), max(s.y.abs(), s.z.abs()));
        if (s.z.abs() > carLen * 0.45 ||
            s.x.abs() > carW * 0.48 ||
            s.y.abs() > carH * 0.70 ||
            maxDim > carLen * 0.45) {
          nonWheel.add(inst.nodeIndex);
        }
      }

      for (final entry in result.entries.toList()) {
        final w = entry.value;
        final hasNonWheelPart = w.partNodeIndices.any(nonWheel.contains);
        final isBodyNode = nonWheel.contains(w.nodeIndex);

        var safeParts = w.partNodeIndices.where((n) => !nonWheel.contains(n)).toList();
        var safeSpin = w.spinNodeIndices.where((n) => !nonWheel.contains(n)).toList();
        final safeCaliper = w.caliperHubNodeIndices
            .where((n) => !nonWheel.contains(n))
            .toList();

        if (safeParts.isEmpty || hasNonWheelPart || isBodyNode) {
          final hub = w.worldPosition;
          final r = w.radius > 0.05 ? w.radius : 0.34;
          final matchedParts = <int>{};
          for (final inst in model!.instances) {
            if (nonWheel.contains(inst.nodeIndex)) continue;
            final b = inst.worldBBox;
            final dLong = (fAxisIsZ ? (b.center.z - hub.z) : (b.center.x - hub.x)).abs();
            final dUp = (b.center.y - hub.y).abs();
            if (dLong <= r * 1.10 && dUp <= r * 1.10) {
              matchedParts.add(inst.nodeIndex);
            }
          }

          if (matchedParts.isNotEmpty) {
            safeParts = matchedParts.toList();
            safeSpin = matchedParts.toList();
          }
        }

        if (safeSpin.isEmpty && safeParts.isNotEmpty) {
          final caliperSet = safeCaliper.toSet();
          safeSpin = safeParts.where((n) => !caliperSet.contains(n)).toList();
        }

        final safePrimary = safeSpin.isNotEmpty
            ? safeSpin.first
            : (safeParts.isNotEmpty
                ? safeParts.first
                : (!isBodyNode ? w.nodeIndex : 1));

        // Authoritative Wheel Center & Dimensions directly from mesh geometry
        final candidateNodes = <int>{};
        if (safeSpin.isNotEmpty) {
          candidateNodes.addAll(safeSpin);
        } else if (safeParts.isNotEmpty) {
          candidateNodes.addAll(safeParts);
        } else if (!nonWheel.contains(safePrimary)) {
          candidateNodes.add(safePrimary);
        }

        BBox? wheelMeshBox;
        for (final inst in model!.instances) {
          if (candidateNodes.contains(inst.nodeIndex)) {
            wheelMeshBox = wheelMeshBox == null
                ? inst.worldBBox
                : BBox.union([wheelMeshBox, inst.worldBBox]);
          }
        }

        var authoritativeHub = w.worldPosition;
        var authoritativeRadius = w.radius;
        var authoritativeWidth = w.width;

        if (wheelMeshBox != null && wheelMeshBox.size.y > 0.05) {
          authoritativeHub = wheelMeshBox.center;
          final dLong = (fAxisIsZ ? wheelMeshBox.size.z : wheelMeshBox.size.x).abs();
          final dUp = wheelMeshBox.size.y.abs();
          final meshR = max(dLong, dUp) * 0.5;
          if (meshR >= 0.15 && meshR <= 0.85) authoritativeRadius = meshR;
          final meshW = (fAxisIsZ ? wheelMeshBox.size.x : wheelMeshBox.size.z).abs();
          if (meshW >= 0.08 && meshW <= 0.65) authoritativeWidth = meshW;
        }

        result[entry.key] = DetectedWheel(
          nodeIndex: safePrimary,
          nodeName: w.nodeName,
          worldPosition: authoritativeHub,
          confidence: w.confidence,
          meshIndex: w.meshIndex,
          partNodeIndices: safeParts,
          partIds: w.partIds,
          spinNodeIndices: safeSpin,
          caliperHubNodeIndices: safeCaliper,
          axle: w.axle,
          side: w.side,
          radius: authoritativeRadius,
          width: authoritativeWidth,
          circularity: w.circularity,
          subMeshCount: max(w.subMeshCount, safeParts.length),
        );
      }
    }
    return result;
  }

  static Mat4 _buildWheelLocalMatrix(
    Vec3 hub,
    Vec3 alignOffset,
    double steer,
    double roll,
  ) =>
      TestDriveViewport.buildWheelLocalMatrix(hub, alignOffset, steer, roll);

  static Vec3 _applyWheelRotTranspose(Vec3 v, double steer, double roll) =>
      TestDriveViewport.applyWheelRotTranspose(v, steer, roll);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Determine Camera Matrix
    Vec3 eye;
    Vec3 target;
    double fovY = 60 * pi / 180;

    if (cameraMode == CameraMode.chase) {
      eye = chaseCamPos;
      target = chaseCamTarget;
      fovY = (60 + (sim.speedKmh / 180.0 * 12.0)) * pi / 180;
    } else if (cameraMode == CameraMode.hood) {
      final fwd = Vec3(-sin(sim.yaw), 0, -cos(sim.yaw));
      eye = sim.position + (fwd * 0.8) + const Vec3(0, 0.95, 0);
      target = eye + (fwd * 12.0);
      fovY = 72 * pi / 180;
    } else {
      // Orbit
      target = sim.position + const Vec3(0, 0.6, 0);
      eye = Vec3(
        target.x + orbitDistance * cos(orbitElevation) * sin(orbitAzimuth),
        target.y + orbitDistance * sin(orbitElevation),
        target.z + orbitDistance * cos(orbitElevation) * cos(orbitAzimuth),
      );
    }

    final view = Mat4.lookAt(eye, target, const Vec3(0, 1, 0));
    final aspect = size.width / size.height;
    final proj = Mat4.perspective(fovY, aspect, 0.1, 400.0);
    final viewProj = proj * view;

    Offset? projectPoint(Vec3 p) {
      final clip = viewProj.transformClip(p);
      final w = clip[3];
      if (w <= 0.05) return null;
      final ndcX = clip[0] / w;
      final ndcY = clip[1] / w;
      final sx = (ndcX * 0.5 + 0.5) * size.width;
      final sy = (1.0 - (ndcY * 0.5 + 0.5)) * size.height;
      return Offset(sx, sy);
    }

    // 2. Draw Sky & Atmospheric Environment with Dynamic Horizon & World-Anchored Mountains
    _drawAtmosphere(canvas, size, eye, target, viewProj, projectPoint);

    // 3. Draw 3D Celestial Body (Fixed in World Space: Sun / Sunset / Moon)
    _drawCelestialBody(canvas, size, eye, viewProj);

    // 4. Draw Asphalt Runway & Proving Grounds Land
    _drawTrack(canvas, size, viewProj, projectPoint);

    // 5. Draw Tire Skid Marks
    _drawSkidMarks(canvas, projectPoint);

    // 6. Draw Slalom Cones
    _drawCones(canvas, projectPoint);

    // 7. Draw Vehicle
    _drawVehicle(canvas, size, viewProj, eye, projectPoint);
  }

  void _drawAtmosphere(
    Canvas canvas,
    Size size,
    Vec3 eye,
    Vec3 target,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    final look = (target - eye).normalized;
    final lookH = Vec3(look.x, 0, look.z);
    final lookHLen = sqrt(lookH.x * lookH.x + lookH.z * lookH.z);
    final horizDir = (lookHLen > 0.001)
        ? Vec3(lookH.x / lookHLen, 0, lookH.z / lookHLen)
        : const Vec3(0, 0, -1);

    final horizonWorld = eye + horizDir * 500.0;
    final horizClip = viewProj.transformClip(horizonWorld);
    double horizonY;
    if (horizClip[3] > 0.05) {
      horizonY =
          (1.0 - (horizClip[1] / horizClip[3] * 0.5 + 0.5)) * size.height;
    } else {
      horizonY = size.height * 0.5;
    }
    horizonY = horizonY.clamp(size.height * 0.15, size.height * 0.85);

    switch (lighting) {
      case TestDriveLighting.day:
        final skyPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFF0369A1), // Deep azure zenith
              Color(0xFF0284C7),
              Color(0xFF38BDF8), // Bright daytime sky
              Color(0xFFBAE6FD), // Atmosphere haze
              Color(0xFFF1F5F9), // Horizon line
            ],
            stops: const [0.0, 0.25, 0.55, 0.82, 1.0],
          ).createShader(Rect.fromLTRB(0, 0, size.width, horizonY + 80));
        canvas.drawRect(Offset.zero & size, skyPaint);

        // Distant Mountain Silhouettes (Anchored to 3D World Space)
        _drawWorldAnchoredMountains(
          canvas,
          size,
          eye,
          look,
          horizonY,
          project,
          const Color(0x50475569),
          const Color(0x3064748B),
        );

        // Cumulus Clouds (Anchored to 3D World Space)
        _drawWorldAnchoredClouds(canvas, size, eye, project);

      case TestDriveLighting.sunset:
        final skyPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFF1E1B4B), // Deep indigo dusk zenith
              Color(0xFF4C0519), // Midnight crimson
              Color(0xFF831843), // Rich magenta
              Color(0xFFC2410C), // Deep amber
              Color(0xFFFDE68A), // Glowing golden horizon
            ],
            stops: const [0.0, 0.28, 0.52, 0.78, 1.0],
          ).createShader(Rect.fromLTRB(0, 0, size.width, horizonY + 80));
        canvas.drawRect(Offset.zero & size, skyPaint);

        // Dusk mountain range (Anchored to 3D World Space)
        _drawWorldAnchoredMountains(
          canvas,
          size,
          eye,
          look,
          horizonY,
          project,
          const Color(0x803B0764),
          const Color(0x55581C87),
        );

      case TestDriveLighting.night:
        final skyPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFF020403), // Pure obsidian zenith
              Color(0xFF050B08),
              Color(0xFF09140E),
              Color(0xFF0E1F16), // Horizon starlight rim
            ],
            stops: const [0.0, 0.35, 0.70, 1.0],
          ).createShader(Rect.fromLTRB(0, 0, size.width, horizonY + 80));
        canvas.drawRect(Offset.zero & size, skyPaint);

        // Night mountain silhouette (Anchored to 3D World Space)
        _drawWorldAnchoredMountains(
          canvas,
          size,
          eye,
          look,
          horizonY,
          project,
          const Color(0xA0040705),
          const Color(0x7009100C),
        );
    }
  }

  void _drawWorldAnchoredMountains(
    Canvas canvas,
    Size size,
    Vec3 eye,
    Vec3 look,
    double horizonY,
    Offset? Function(Vec3) project,
    Color frontColor,
    Color backColor,
  ) {
    final camYaw = atan2(look.x, look.z);

    // 1. Distant background peaks layer (radius 900m)
    _drawMountainRidge(
      canvas,
      size,
      eye,
      camYaw,
      horizonY,
      project,
      backColor,
      radius: 900.0,
      scale: 1.3,
      phaseOffset: 1.4,
    );

    // 2. Closer foreground ridge layer (radius 720m)
    _drawMountainRidge(
      canvas,
      size,
      eye,
      camYaw,
      horizonY,
      project,
      frontColor,
      radius: 720.0,
      scale: 0.85,
      phaseOffset: 0.0,
    );
  }

  void _drawMountainRidge(
    Canvas canvas,
    Size size,
    Vec3 eye,
    double camYaw,
    double horizonY,
    Offset? Function(Vec3) project,
    Color color, {
    required double radius,
    required double scale,
    required double phaseOffset,
  }) {
    const fovSpan = 2.4; // approx 137° visible horizontal field of view with safety margins
    const sampleCount = 16;

    final ridgePoints = <Offset>[];

    for (var i = 0; i <= sampleCount; i++) {
      // theta is absolute world compass bearing in radians
      final theta = (camYaw - (fovSpan * 0.5)) + (fovSpan * i / sampleCount);

      // Height function based strictly on absolute world compass bearing theta
      final s1 = sin(theta * 3.0 + phaseOffset);
      final s2 = sin(theta * 7.0 + phaseOffset * 1.5);
      final s3 = sin(theta * 13.0 - phaseOffset);
      final s4 = sin(theta * 23.0);
      final normalizedHeight =
          (s1 * 0.45 + s2 * 0.28 + s3 * 0.18 + s4 * 0.09).abs();
      final heightMeters = (normalizedHeight * 58.0 + 14.0) * scale;

      // 3D world position of the mountain peak at this world bearing
      final peakWorld = Vec3(
        eye.x + radius * sin(theta),
        heightMeters,
        eye.z + radius * cos(theta),
      );

      final screenPt = project(peakWorld);
      if (screenPt != null) {
        ridgePoints.add(screenPt);
      }
    }

    if (ridgePoints.length < 2) return;

    final path = Path();
    path.moveTo(-100, horizonY + 60);
    path.lineTo(ridgePoints.first.dx, horizonY + 60);
    for (final pt in ridgePoints) {
      path.lineTo(pt.dx, pt.dy);
    }
    path.lineTo(ridgePoints.last.dx, horizonY + 60);
    path.lineTo(size.width + 100, horizonY + 60);
    path.close();

    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawWorldAnchoredClouds(
    Canvas canvas,
    Size size,
    Vec3 eye,
    Offset? Function(Vec3) project,
  ) {
    // Stationary clouds at fixed world azimuth bearings
    final clouds = [
      (0.65, 80.0, 0.38, 20.0, 0x24FFFFFF),
      (1.85, 95.0, 0.44, 24.0, 0x20FFFFFF),
      (-1.20, 75.0, 0.34, 18.0, 0x22FFFFFF),
      (-2.40, 90.0, 0.40, 22.0, 0x1EFFFFFF),
    ];

    const cloudRadius = 650.0;
    for (final (azimuth, alt, wFrac, hPx, colorHex) in clouds) {
      final cloudPos = Vec3(
        eye.x + cloudRadius * sin(azimuth),
        alt,
        eye.z + cloudRadius * cos(azimuth),
      );
      final screenPt = project(cloudPos);
      if (screenPt != null) {
        final cloudPaint = Paint()
          ..color = Color(colorHex)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(
            center: screenPt,
            width: size.width * wFrac,
            height: hPx,
          ),
          cloudPaint,
        );
      }
    }
  }

  void _drawCelestialBody(
    Canvas canvas,
    Size size,
    Vec3 eye,
    Mat4 viewProj,
  ) {
    Vec3 celestialDir;
    switch (lighting) {
      case TestDriveLighting.day:
        // Positioned high in the south-west sky
        celestialDir = const Vec3(0.40, 0.58, -0.71).normalized;
      case TestDriveLighting.sunset:
        // Low golden sun just above the horizon in the south-west
        celestialDir = const Vec3(0.52, 0.16, -0.84).normalized;
      case TestDriveLighting.night:
        // Crescent moon high in the north-east sky
        celestialDir = const Vec3(-0.48, 0.60, 0.64).normalized;
    }

    final celestialPos = eye + (celestialDir * 500.0);
    final clip = viewProj.transformClip(celestialPos);

    // Must be in front of camera
    if (clip[3] <= 0.08) return;

    final ndcX = clip[0] / clip[3];
    final ndcY = clip[1] / clip[3];
    final sx = (ndcX * 0.5 + 0.5) * size.width;
    final sy = (1.0 - (ndcY * 0.5 + 0.5)) * size.height;

    const margin = 200.0;
    if (sx < -margin || sx > size.width + margin || sy < -margin || sy > size.height + margin) {
      return;
    }

    final center = Offset(sx, sy);

    switch (lighting) {
      case TestDriveLighting.day:
        // Wide corona glow
        final corona = Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0x60FFFBEB),
              Color(0x28FDE047),
              Color(0x00FDE047),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 130));
        canvas.drawCircle(center, 130, corona);

        // Core glow
        final core = Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0xF0FFFFFF),
              Color(0x80FEF08A),
              Color(0x00FEF08A),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 50));
        canvas.drawCircle(center, 50, core);

        // Solid sun disk
        canvas.drawCircle(center, 18, Paint()..color = const Color(0xFFFFFFFF));

        // Horizontal lens flare streak
        final streak = Paint()
          ..shader = LinearGradient(
            colors: const [
              Color(0x00FFFFFF),
              Color(0x40FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(Rect.fromCenter(center: center, width: size.width * 0.6, height: 4));
        canvas.drawRect(Rect.fromCenter(center: center, width: size.width * 0.6, height: 4), streak);

      case TestDriveLighting.sunset:
        // Broad sunset halo
        final halo = Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0x95FFF7ED),
              Color(0x75F97316),
              Color(0x20EA580C),
              Color(0x00C2410C),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 170));
        canvas.drawCircle(center, 170, halo);

        // Intense inner glow
        final inner = Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0xF5FFFBEB),
              Color(0x85F59E0B),
              Color(0x00F59E0B),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 65));
        canvas.drawCircle(center, 65, inner);

        // Golden sun disk
        canvas.drawCircle(center, 22, Paint()..color = const Color(0xFFFFFBEB));

        // Horizontal golden flare
        final sunsetStreak = Paint()
          ..shader = LinearGradient(
            colors: const [
              Color(0x00F97316),
              Color(0x55F97316),
              Color(0x00F97316),
            ],
          ).createShader(Rect.fromCenter(center: center, width: size.width * 0.75, height: 6));
        canvas.drawRect(Rect.fromCenter(center: center, width: size.width * 0.75, height: 6), sunsetStreak);

      case TestDriveLighting.night:
        // Moon soft glow
        final moonGlow = Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0x4560A5FA),
              Color(0x1538BDF8),
              Color(0x00000000),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 60));
        canvas.drawCircle(center, 60, moonGlow);

        // Moon disk
        canvas.drawCircle(center, 15, Paint()..color = const Color(0xFFE2E8F0));

        // Crescent cutout for realistic moon phase
        final shadowOffset = Offset(center.dx + 4.5, center.dy - 2.5);
        canvas.drawCircle(shadowOffset, 12.5, Paint()..color = const Color(0xFF060B08));
    }
  }

  void _drawTrack(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    switch (trackStyle) {
      case TrackSurfaceStyle.circuit:
        _drawCircuitAsphalt(canvas, size, viewProj, project);
      case TrackSurfaceStyle.skidpad:
        _drawSkidpadAsphalt(canvas, size, viewProj, project);
      case TrackSurfaceStyle.dragstrip:
        _drawDragstripAsphalt(canvas, size, viewProj, project);
      case TrackSurfaceStyle.cyberGrid:
        _drawCyberGridAsphalt(canvas, size, viewProj, project);
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

    final sx0 = (final0[0] / final0[3] * 0.5 + 0.5) * size.width;
    final sy0 = (1.0 - (final0[1] / final0[3] * 0.5 + 0.5)) * size.height;
    final sx1 = (final1[0] / final1[3] * 0.5 + 0.5) * size.width;
    final sy1 = (1.0 - (final1[1] / final1[3] * 0.5 + 0.5)) * size.height;

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
      final sx = (c[0] / w * 0.5 + 0.5) * size.width;
      final sy = (1.0 - (c[1] / w * 0.5 + 0.5)) * size.height;
      if (i == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawQuad(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    Vec3 p0,
    Vec3 p1,
    Vec3 p2,
    Vec3 p3,
    Paint paint,
  ) {
    _drawClippedPolygon(canvas, viewProj, size, [p0, p1, p2, p3], paint);
  }

  void _drawCheckeredLine(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
    double zPos,
    double width,
  ) {
    const rows = 2;
    const cols = 14;
    const len = 1.6;
    final cellW = (width * 2) / cols;

    final whitePaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    final blackPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    for (var r = 0; r < rows; r++) {
      final z0 = zPos + r * (len / rows);
      final z1 = z0 + (len / rows);
      for (var c = 0; c < cols; c++) {
        final x0 = -width + c * cellW;
        final x1 = x0 + cellW;
        final isWhite = (r + c) % 2 == 0;
        _drawQuad(
          canvas,
          viewProj,
          size,
          Vec3(x0, groundY, z0),
          Vec3(x1, groundY, z0),
          Vec3(x1, groundY, z1),
          Vec3(x0, groundY, z1),
          isWhite ? whitePaint : blackPaint,
        );
      }
    }
  }

  void _drawDistanceBoard(
    Canvas canvas,
    Mat4 viewProj,
    Size size,
    double groundY,
    double zPos,
    double xPos,
  ) {
    final postPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.5;
    _drawClippedLine(
      canvas,
      viewProj,
      size,
      Vec3(xPos, groundY, zPos),
      Vec3(xPos, groundY + 1.8, zPos),
      postPaint,
    );

    final boardPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(xPos - 0.7, groundY + 1.0, zPos),
      Vec3(xPos + 0.7, groundY + 1.0, zPos),
      Vec3(xPos + 0.7, groundY + 2.2, zPos),
      Vec3(xPos - 0.7, groundY + 2.2, zPos),
      boardPaint,
    );
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(xPos - 0.7, groundY + 1.0, zPos),
      Vec3(xPos + 0.7, groundY + 1.0, zPos),
      Vec3(xPos + 0.7, groundY + 2.2, zPos),
      Vec3(xPos - 0.7, groundY + 2.2, zPos),
      borderPaint,
    );
  }

  void _drawCircuitAsphalt(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    const groundY = 0.0;
    const trackWidth = 14.0;
    const curbWidth = 1.4;
    const shoulderWidth = 14.0;

    final isDay = lighting == TestDriveLighting.day;
    final isSunset = lighting == TestDriveLighting.sunset;

    // Center dynamically around car so track is infinite in both directions
    final carZ = sim.position.z;
    const sliceLen = 16.0;
    final centerZ = (carZ / sliceLen).round() * sliceLen;
    final zStart = centerZ - 180.0;
    final zEnd = centerZ + 70.0;

    // 1. Solid Terrain Base underneath everything (Natural Green Turf / Prairie)
    final terrainColor = isDay
        ? const Color(0xFF1E3A2B)
        : (isSunset ? const Color(0xFF281C16) : const Color(0xFF070B09));
    final terrainPaint = Paint()
      ..color = terrainColor
      ..style = PaintingStyle.fill;

    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-500, groundY - 0.05, zStart - 80),
      Vec3(500, groundY - 0.05, zStart - 80),
      Vec3(500, groundY - 0.05, zEnd + 80),
      Vec3(-500, groundY - 0.05, zEnd + 80),
      terrainPaint,
    );

    final asphaltColor = isDay
        ? const Color(0xFF1E293B)
        : (isSunset ? const Color(0xFF18181B) : const Color(0xFF0F1713));
    final shoulderColor = isDay
        ? const Color(0xFF475569) // Gravel runoff shoulder
        : (isSunset ? const Color(0xFF2E2724) : const Color(0xFF141916));

    final asphaltPaint = Paint()
      ..color = asphaltColor
      ..style = PaintingStyle.fill;
    final shoulderPaint = Paint()
      ..color = shoulderColor
      ..style = PaintingStyle.fill;
    final edgeLinePaint = Paint()
      ..color = isDay ? const Color(0xFFF8FAFC) : const Color(0xC0FFFFFF)
      ..strokeWidth = 2.0;
    final centerDashPaint = Paint()
      ..color = isDay ? const Color(0xFFFDE047) : const Color(0x90FFFFFF)
      ..strokeWidth = 2.2;
    final redCurbPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    final whiteCurbPaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;

    // 2. Continuous Runoff Shoulders (Left & Right)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-trackWidth - curbWidth - shoulderWidth, groundY, zStart),
      Vec3(-trackWidth - curbWidth, groundY, zStart),
      Vec3(-trackWidth - curbWidth, groundY, zEnd),
      Vec3(-trackWidth - curbWidth - shoulderWidth, groundY, zEnd),
      shoulderPaint,
    );
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(trackWidth + curbWidth, groundY, zStart),
      Vec3(trackWidth + curbWidth + shoulderWidth, groundY, zStart),
      Vec3(trackWidth + curbWidth + shoulderWidth, groundY, zEnd),
      Vec3(trackWidth + curbWidth, groundY, zEnd),
      shoulderPaint,
    );

    // 3. Continuous Main Asphalt Roadbed
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-trackWidth, groundY, zStart),
      Vec3(trackWidth, groundY, zStart),
      Vec3(trackWidth, groundY, zEnd),
      Vec3(-trackWidth, groundY, zEnd),
      asphaltPaint,
    );

    // 4. White boundary lines (continuous)
    _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, zStart),
        Vec3(-trackWidth, groundY, zEnd), edgeLinePaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(trackWidth, groundY, zStart),
        Vec3(trackWidth, groundY, zEnd), edgeLinePaint);

    // 5. FIA Curbs: only drawn in visible range near the vehicle (saving 80+ draw calls)
    final curbZStart = (centerZ - 42.0).clamp(zStart, zEnd);
    final curbZEnd = (centerZ + 28.0).clamp(zStart, zEnd);
    const curbStep = 2.8;
    for (var cz = curbZStart; cz < curbZEnd; cz += curbStep) {
      final cz1 = cz + curbStep;
      final isRed = ((cz / curbStep).round() % 2 == 0);
      final curbColor = isRed ? redCurbPaint : whiteCurbPaint;

      _drawQuad(
        canvas,
        viewProj,
        size,
        Vec3(-trackWidth - curbWidth, groundY, cz),
        Vec3(-trackWidth, groundY, cz),
        Vec3(-trackWidth, groundY, cz1),
        Vec3(-trackWidth - curbWidth, groundY, cz1),
        curbColor,
      );
      _drawQuad(
        canvas,
        viewProj,
        size,
        Vec3(trackWidth, groundY, cz),
        Vec3(trackWidth + curbWidth, groundY, cz),
        Vec3(trackWidth + curbWidth, groundY, cz1),
        Vec3(trackWidth, groundY, cz1),
        curbColor,
      );
    }

    // 6. Transverse road surface seams every 6.0m for realistic ground roll optical flow
    const jointCycle = 6.0;
    final minJointZ = (zStart / jointCycle).floor() * jointCycle;
    final maxJointZ = (zEnd / jointCycle).ceil() * jointCycle;
    final jointPaint = Paint()
      ..color = isDay ? const Color(0x35000000) : const Color(0x28FFFFFF)
      ..strokeWidth = 1.6;
    for (var jz = minJointZ; jz <= maxJointZ; jz += jointCycle) {
      if ((jz - centerZ).abs() < 55.0) {
        _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, jz),
            Vec3(trackWidth, groundY, jz), jointPaint);
      }
    }

    // 7. Center dashed line: within visible range
    final dashZStart = (centerZ - 54.0).clamp(zStart, zEnd);
    final dashZEnd = (centerZ + 36.0).clamp(zStart, zEnd);
    const dashLen = 4.5;
    const dashGap = 4.5;
    const dashCycle = dashLen + dashGap;
    final firstDash = (dashZStart / dashCycle).floor() * dashCycle;
    for (var dz = firstDash; dz < dashZEnd; dz += dashCycle) {
      _drawClippedLine(canvas, viewProj, size, Vec3(0, groundY, dz),
          Vec3(0, groundY, dz + dashLen), centerDashPaint);
    }

    // 7. Checkered Start Line (if within range of start grid at Z = 24)
    if ((centerZ - 24.0).abs() < 100.0) {
      _drawCheckeredLine(canvas, viewProj, size, groundY, 24.0, trackWidth);
    }

    // 8. Distance marker boards (in view range)
    final minBoardZ = ((zStart / 50).floor() * 50).toDouble();
    final maxBoardZ = ((zEnd / 50).ceil() * 50).toDouble();
    for (var bz = minBoardZ; bz <= maxBoardZ; bz += 50.0) {
      if ((bz - centerZ).abs() < 90.0) {
        _drawDistanceBoard(
            canvas, viewProj, size, groundY, bz, trackWidth + curbWidth + 2.5);
      }
    }
  }

  void _drawSkidpadAsphalt(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    const groundY = 0.0;
    const padWidth = 70.0; // 140-meter wide expansive dynamic proving pad
    const runoffWidth = 16.0;

    final isDay = lighting == TestDriveLighting.day;
    final isSunset = lighting == TestDriveLighting.sunset;
    final carZ = sim.position.z;
    const sliceLen = 10.0;
    final centerZ = (carZ / sliceLen).round() * sliceLen;
    final zStart = centerZ - 200.0;
    final zEnd = centerZ + 80.0;

    // 1. Solid Natural Landscape Base
    final terrainColor = isDay
        ? const Color(0xFF1E3A2B)
        : (isSunset ? const Color(0xFF281C16) : const Color(0xFF070B09));
    final terrainPaint = Paint()
      ..color = terrainColor
      ..style = PaintingStyle.fill;

    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-600, groundY - 0.05, zStart - 100),
      Vec3(600, groundY - 0.05, zStart - 100),
      Vec3(600, groundY - 0.05, zEnd + 100),
      Vec3(-600, groundY - 0.05, zEnd + 100),
      terrainPaint,
    );

    // 2. High-Grade Dynamic Proving Ground Tarmac
    final asphaltColor = isDay
        ? const Color(0xFF1E2832)
        : (isSunset ? const Color(0xFF18171B) : const Color(0xFF0D1210));
    final gravelColor = isDay
        ? const Color(0xFF475569)
        : (isSunset ? const Color(0xFF2B2522) : const Color(0xFF141916));

    final asphaltPaint = Paint()
      ..color = asphaltColor
      ..style = PaintingStyle.fill;
    final gravelPaint = Paint()
      ..color = gravelColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = isDay ? const Color(0xFFF8FAFC) : const Color(0x90FFFFFF)
      ..strokeWidth = 2.4;
    final guidePaint = Paint()
      ..color = const Color(0x4094A3B8)
      ..strokeWidth = 1.4;

    // Gravel Safety Runoff Shoulders (Continuous Quads)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-padWidth - runoffWidth, groundY, zStart),
      Vec3(-padWidth, groundY, zStart),
      Vec3(-padWidth, groundY, zEnd),
      Vec3(-padWidth - runoffWidth, groundY, zEnd),
      gravelPaint,
    );
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(padWidth, groundY, zStart),
      Vec3(padWidth + runoffWidth, groundY, zStart),
      Vec3(padWidth + runoffWidth, groundY, zEnd),
      Vec3(padWidth, groundY, zEnd),
      gravelPaint,
    );

    // Main Proving Tarmac Pad (Continuous Quad)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-padWidth, groundY, zStart),
      Vec3(padWidth, groundY, zStart),
      Vec3(padWidth, groundY, zEnd),
      Vec3(-padWidth, groundY, zEnd),
      asphaltPaint,
    );

    // Perimeter boundary lines (Continuous Lines)
    _drawClippedLine(canvas, viewProj, size, Vec3(-padWidth, groundY, zStart),
        Vec3(-padWidth, groundY, zEnd), borderPaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(padWidth, groundY, zStart),
        Vec3(padWidth, groundY, zEnd), borderPaint);

    // Slalom & Sprint lane dashed dividers (Rendered only within visible proximity)
    final dashZStart = (centerZ - 60.0).clamp(zStart, zEnd);
    final dashZEnd = (centerZ + 40.0).clamp(zStart, zEnd);
    const dashLen = 5.0;
    const dashGap = 5.0;
    const dashCycle = dashLen + dashGap;
    final firstDash = (dashZStart / dashCycle).floor() * dashCycle;
    for (var dz = firstDash; dz < dashZEnd; dz += dashCycle) {
      _drawClippedLine(canvas, viewProj, size, Vec3(-35.0, groundY, dz),
          Vec3(-35.0, groundY, dz + dashLen), guidePaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(35.0, groundY, dz),
          Vec3(35.0, groundY, dz + dashLen), guidePaint);
    }

    // Transverse Distance Marks every 40m across the pad
    final minGridZ = ((zStart / 40).floor() * 40).toDouble();
    final maxGridZ = ((zEnd / 40).ceil() * 40).toDouble();
    final transPaint = Paint()
      ..color = const Color(0x3094A3B8)
      ..strokeWidth = 1.2;
    for (var tz = minGridZ; tz <= maxGridZ; tz += 40.0) {
      _drawClippedLine(canvas, viewProj, size, Vec3(-padWidth, groundY, tz),
          Vec3(padWidth, groundY, tz), transPaint);
    }

    // ── FIXED WORLD PROVING FACILITIES (Stationary Coordinates) ──────────────
    // 3. Main Central Dynamics Skidpad at World Origin (0, 0, 0)
    if ((centerZ - 0.0).abs() < 220.0) {
      // Inner Wet Low-Friction Drift Pad (Polished Epoxy Slick Ring, R <= 26m)
      const wetR = 26.0;
      const wetSegments = 24;
      final wetColor = isDay
          ? const Color(0xFF26394D)
          : (isSunset ? const Color(0xFF1E2836) : const Color(0xFF111A24));
      final wetPaint = Paint()
        ..color = wetColor
        ..style = PaintingStyle.fill;

      final wetPoly = <Vec3>[];
      for (var i = 0; i < wetSegments; i++) {
        final a = i * 2 * pi / wetSegments;
        wetPoly.add(Vec3(wetR * cos(a), groundY + 0.002, wetR * sin(a)));
      }
      _drawClippedPolygon(canvas, viewProj, size, wetPoly, wetPaint);

      // Stationary Concentric Guidance Drift Rings
      final rings = [
        (14.0, const Color(0xFFF59E0B), 2.2), // Inner Drift guidance
        (26.0, const Color(0xFFF8FAFC), 2.4), // Low-friction boundary
        (42.0, const Color(0xFFF59E0B), 2.2), // Outer High-G drift ring
        (58.0, const Color(0xFF38BDF8), 2.8), // Skidpad perimeter ring
      ];

      const ringSegs = 36;
      for (final (r, color, width) in rings) {
        final p = Paint()
          ..color = color
          ..strokeWidth = width;
        for (var i = 0; i < ringSegs; i++) {
          final a0 = i * 2 * pi / ringSegs;
          final a1 = (i + 1) * 2 * pi / ringSegs;
          _drawClippedLine(
            canvas,
            viewProj,
            size,
            Vec3(r * cos(a0), groundY + 0.003, r * sin(a0)),
            Vec3(r * cos(a1), groundY + 0.003, r * sin(a1)),
            p,
          );
        }
      }

      // Circular Red & White Runoff Curbing around the 58m perimeter
      const curbSegs = 36;
      final redCurb = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      final whiteCurb = Paint()
        ..color = const Color(0xFFF8FAFC)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < curbSegs; i++) {
        final a0 = i * 2 * pi / curbSegs;
        final a1 = (i + 1) * 2 * pi / curbSegs;
        final isRed = (i % 2 == 0);
        _drawQuad(
          canvas,
          viewProj,
          size,
          Vec3(58.0 * cos(a0), groundY + 0.004, 58.0 * sin(a0)),
          Vec3(59.6 * cos(a0), groundY + 0.004, 59.6 * sin(a0)),
          Vec3(59.6 * cos(a1), groundY + 0.004, 59.6 * sin(a1)),
          Vec3(58.0 * cos(a1), groundY + 0.004, 58.0 * sin(a1)),
          isRed ? redCurb : whiteCurb,
        );
      }

      // 12 Radial Azimuth Graduation Spokes (every 30°)
      final spokePaint = Paint()
        ..color = const Color(0x6094A3B8)
        ..strokeWidth = 1.4;
      for (var deg = 0; deg < 360; deg += 30) {
        final rad = deg * pi / 180;
        _drawClippedLine(
          canvas,
          viewProj,
          size,
          Vec3(5.0 * cos(rad), groundY + 0.003, 5.0 * sin(rad)),
          Vec3(58.0 * cos(rad), groundY + 0.003, 58.0 * sin(rad)),
          spokePaint,
        );
      }

      // Center Origin Crosshairs & Rosette
      final crossPaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..strokeWidth = 2.0;
      _drawClippedLine(canvas, viewProj, size, Vec3(-58, groundY + 0.004, 0),
          Vec3(58, groundY + 0.004, 0), crossPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(0, groundY + 0.004, -58),
          Vec3(0, groundY + 0.004, 58), crossPaint);
    }

    // 4. Secondary Figure-8 Drift Circle at World (0, 0, -110)
    if ((centerZ - (-110.0)).abs() < 220.0) {
      const f8Center = Vec3(0, groundY + 0.003, -110.0);
      const f8R = 34.0;
      const f8Segs = 32;
      final f8Paint = Paint()
        ..color = const Color(0x95F59E0B)
        ..strokeWidth = 2.2;
      for (var i = 0; i < f8Segs; i++) {
        final a0 = i * 2 * pi / f8Segs;
        final a1 = (i + 1) * 2 * pi / f8Segs;
        _drawClippedLine(
          canvas,
          viewProj,
          size,
          Vec3(f8Center.x + f8R * cos(a0), f8Center.y,
              f8Center.z + f8R * sin(a0)),
          Vec3(f8Center.x + f8R * cos(a1), f8Center.y,
              f8Center.z + f8R * sin(a1)),
          f8Paint,
        );
      }

      // Figure-8 connecting transition lines to center pad
      final transLine = Paint()
        ..color = const Color(0x70F8FAFC)
        ..strokeWidth = 2.0;
      _drawClippedLine(canvas, viewProj, size, const Vec3(-20, groundY + 0.003, -58),
          const Vec3(20, groundY + 0.003, -76), transLine);
      _drawClippedLine(canvas, viewProj, size, const Vec3(20, groundY + 0.003, -58),
          const Vec3(-20, groundY + 0.003, -76), transLine);
    }
  }

  void _drawDragstripAsphalt(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    const groundY = 0.0;
    const stripWidth = 11.0;
    const shoulderWidth = 5.0;
    const gravelWidth = 14.0;

    final isDay = lighting == TestDriveLighting.day;
    final isSunset = lighting == TestDriveLighting.sunset;
    final carZ = sim.position.z;
    const sliceLen = 10.0;
    final centerZ = (carZ / sliceLen).round() * sliceLen;
    final zStart = centerZ - 200.0;
    final zEnd = centerZ + 80.0;

    // Solid Terrain Base underneath (Natural Landscape)
    final terrainColor = isDay
        ? const Color(0xFF1E3A2B)
        : (isSunset ? const Color(0xFF281C16) : const Color(0xFF070B09));
    final terrainPaint = Paint()
      ..color = terrainColor
      ..style = PaintingStyle.fill;

    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-600, groundY - 0.05, zStart - 100),
      Vec3(600, groundY - 0.05, zStart - 100),
      Vec3(600, groundY - 0.05, zEnd + 100),
      Vec3(-600, groundY - 0.05, zEnd + 100),
      terrainPaint,
    );

    final asphaltColor = isDay
        ? const Color(0xFF0F172A)
        : const Color(0xFF070B0E);
    final shoulderColor = isDay
        ? const Color(0xFF334155)
        : const Color(0xFF161F26);
    final gravelColor = isDay
        ? const Color(0xFF475569)
        : const Color(0xFF1E1B18);

    final asphaltPaint = Paint()
      ..color = asphaltColor
      ..style = PaintingStyle.fill;
    final shoulderPaint = Paint()
      ..color = shoulderColor
      ..style = PaintingStyle.fill;
    final gravelPaint = Paint()
      ..color = gravelColor
      ..style = PaintingStyle.fill;
    final yellowLinePaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..strokeWidth = 2.4;
    final whiteLinePaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..strokeWidth = 2.0;

    // Outer Gravel Trap (Continuous Quads)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-stripWidth - shoulderWidth - gravelWidth, groundY, zStart),
      Vec3(-stripWidth - shoulderWidth, groundY, zStart),
      Vec3(-stripWidth - shoulderWidth, groundY, zEnd),
      Vec3(-stripWidth - shoulderWidth - gravelWidth, groundY, zEnd),
      gravelPaint,
    );
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(stripWidth + shoulderWidth, groundY, zStart),
      Vec3(stripWidth + shoulderWidth + gravelWidth, groundY, zStart),
      Vec3(stripWidth + shoulderWidth + gravelWidth, groundY, zEnd),
      Vec3(stripWidth + shoulderWidth, groundY, zEnd),
      gravelPaint,
    );

    // Runway Shoulder (Continuous Quads)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-stripWidth - shoulderWidth, groundY, zStart),
      Vec3(-stripWidth, groundY, zStart),
      Vec3(-stripWidth, groundY, zEnd),
      Vec3(-stripWidth - shoulderWidth, groundY, zEnd),
      shoulderPaint,
    );
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(stripWidth, groundY, zStart),
      Vec3(stripWidth + shoulderWidth, groundY, zStart),
      Vec3(stripWidth + shoulderWidth, groundY, zEnd),
      Vec3(stripWidth, groundY, zEnd),
      shoulderPaint,
    );

    // Main strip (Continuous Quad)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-stripWidth, groundY, zStart),
      Vec3(stripWidth, groundY, zStart),
      Vec3(stripWidth, groundY, zEnd),
      Vec3(-stripWidth, groundY, zEnd),
      asphaltPaint,
    );

    // Center divider solid line
    _drawClippedLine(canvas, viewProj, size, Vec3(0, groundY, zStart),
        Vec3(0, groundY, zEnd), yellowLinePaint);

    // Outer boundary white lines
    _drawClippedLine(canvas, viewProj, size, Vec3(-stripWidth, groundY, zStart),
        Vec3(-stripWidth, groundY, zEnd), whiteLinePaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(stripWidth, groundY, zStart),
        Vec3(stripWidth, groundY, zEnd), whiteLinePaint);

    // Staging launch box at Z = 24 if in range
    if ((centerZ - 24.0).abs() < 140.0) {
      _drawCheckeredLine(canvas, viewProj, size, groundY, 24.0, stripWidth);
    }

    // Speed trap lines every 50m
    final minTrapZ = ((zStart / 50).floor() * 50).toDouble();
    final maxTrapZ = ((zEnd / 50).ceil() * 50).toDouble();
    final trapPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..strokeWidth = 3.0;
    for (var tz = minTrapZ; tz <= maxTrapZ; tz += 50.0) {
      _drawClippedLine(canvas, viewProj, size, Vec3(-stripWidth, groundY, tz),
          Vec3(stripWidth, groundY, tz), trapPaint);
    }
  }

  void _drawCyberGridAsphalt(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Offset? Function(Vec3) project,
  ) {
    const groundY = 0.0;
    const trackWidth = 12.0; // 24-meter wide high-tech cyber corridor

    final carZ = sim.position.z;
    const sliceLen = 8.0;
    final centerZ = (carZ / sliceLen).round() * sliceLen;
    final zStart = centerZ - 200.0;
    final zEnd = centerZ + 80.0;

    // 1. Solid Deep Obsidian Matrix Floor (No empty air!)
    final groundPaint = Paint()
      ..color = const Color(0xFF020504)
      ..style = PaintingStyle.fill;

    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-350, groundY - 0.05, zStart - 50),
      Vec3(350, groundY - 0.05, zStart - 50),
      Vec3(350, groundY - 0.05, zEnd + 50),
      Vec3(-350, groundY - 0.05, zEnd + 50),
      groundPaint,
    );

    // 2. Outlying Matrix Grid lines extending to +/- 100m
    final outerGridPaint = Paint()
      ..color = const Color(0x1510B981)
      ..strokeWidth = 1.0;
    for (var x = -100.0; x <= 100.0; x += 16.0) {
      if (x.abs() > trackWidth) {
        _drawClippedLine(canvas, viewProj, size, Vec3(x, groundY, zStart),
            Vec3(x, groundY, zEnd), outerGridPaint);
      }
    }

    // 3. Main Cyber Track Corridor Slices & Glowing Neon Cells
    final trackBasePaint = Paint()
      ..color = const Color(0xFF05120A)
      ..style = PaintingStyle.fill;

    final glowBorderPaint = Paint()
      ..color = const Color(0x5534D399)
      ..strokeWidth = 6.0;
    final laserBorderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.8;

    final centerPulsePaint = Paint()
      ..color = Color.lerp(
        const Color(0x8010B981),
        const Color(0xFF34D399),
        uiPulse,
      )!
      ..strokeWidth = 2.4;
    final laneDividerPaint = Paint()
      ..color = const Color(0x5006B6D4)
      ..strokeWidth = 1.2;

    // Dark carbon road bed (Continuous Quad)
    _drawQuad(
      canvas,
      viewProj,
      size,
      Vec3(-trackWidth, groundY, zStart),
      Vec3(trackWidth, groundY, zStart),
      Vec3(trackWidth, groundY, zEnd),
      Vec3(-trackWidth, groundY, zEnd),
      trackBasePaint,
    );

    // Glowing Neon Boundary Laser Lines (Continuous Lines)
    _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, zStart),
        Vec3(-trackWidth, groundY, zEnd), glowBorderPaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, zStart),
        Vec3(-trackWidth, groundY, zEnd), laserBorderPaint);

    _drawClippedLine(canvas, viewProj, size, Vec3(trackWidth, groundY, zStart),
        Vec3(trackWidth, groundY, zEnd), glowBorderPaint);
    _drawClippedLine(canvas, viewProj, size, Vec3(trackWidth, groundY, zStart),
        Vec3(trackWidth, groundY, zEnd), laserBorderPaint);

    // Center glowing pulse line & lane lines (Visible range only)
    final cyberZStart = (centerZ - 50.0).clamp(zStart, zEnd);
    final cyberZEnd = (centerZ + 35.0).clamp(zStart, zEnd);
    final firstCyber = (cyberZStart / sliceLen).floor() * sliceLen;
    for (var cz = firstCyber; cz < cyberZEnd; cz += sliceLen) {
      _drawClippedLine(canvas, viewProj, size, Vec3(0, groundY, cz),
          Vec3(0, groundY, cz + sliceLen * 0.6), centerPulsePaint);

      _drawClippedLine(canvas, viewProj, size, Vec3(-6.0, groundY, cz),
          Vec3(-6.0, groundY, cz + sliceLen * 0.45), laneDividerPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(6.0, groundY, cz),
          Vec3(6.0, groundY, cz + sliceLen * 0.45), laneDividerPaint);
    }

    // 4. Holographic Directional Chevrons every 32m
    final minChevZ = ((zStart / 32).floor() * 32).toDouble();
    final maxChevZ = ((zEnd / 32).ceil() * 32).toDouble();
    final chevPaint = Paint()
      ..color = const Color(0x9510B981)
      ..strokeWidth = 2.4;
    for (var cz = minChevZ; cz <= maxChevZ; cz += 32.0) {
      // Left lane chevron
      _drawClippedLine(canvas, viewProj, size, Vec3(-8.0, groundY + 0.005, cz),
          Vec3(-6.0, groundY + 0.005, cz - 2.5), chevPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(-4.0, groundY + 0.005, cz),
          Vec3(-6.0, groundY + 0.005, cz - 2.5), chevPaint);

      // Right lane chevron
      _drawClippedLine(canvas, viewProj, size, Vec3(4.0, groundY + 0.005, cz),
          Vec3(6.0, groundY + 0.005, cz - 2.5), chevPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(8.0, groundY + 0.005, cz),
          Vec3(6.0, groundY + 0.005, cz - 2.5), chevPaint);
    }

    // 5. Vertical Holographic Light Pillars along boundaries every 24m
    final minPillarZ = ((zStart / 24).floor() * 24).toDouble();
    final maxPillarZ = ((zEnd / 24).ceil() * 24).toDouble();
    final pillarLaserPaint = Paint()
      ..color = const Color(0xC010B981)
      ..strokeWidth = 2.2;
    final pillarGlowPaint = Paint()
      ..color = const Color(0x4034D399)
      ..strokeWidth = 5.0;

    for (var pz = minPillarZ; pz <= maxPillarZ; pz += 24.0) {
      // Left pillar
      _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, pz),
          Vec3(-trackWidth, groundY + 3.4, pz), pillarGlowPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(-trackWidth, groundY, pz),
          Vec3(-trackWidth, groundY + 3.4, pz), pillarLaserPaint);

      // Right pillar
      _drawClippedLine(canvas, viewProj, size, Vec3(trackWidth, groundY, pz),
          Vec3(trackWidth, groundY + 3.4, pz), pillarGlowPaint);
      _drawClippedLine(canvas, viewProj, size, Vec3(trackWidth, groundY, pz),
          Vec3(trackWidth, groundY + 3.4, pz), pillarLaserPaint);

      // Glowing emitter beacon head at the top of each pillar
      final pL = project(Vec3(-trackWidth, groundY + 3.4, pz));
      if (pL != null) {
        canvas.drawCircle(pL, 3.5, Paint()..color = const Color(0xFF34D399));
      }
      final pR = project(Vec3(trackWidth, groundY + 3.4, pz));
      if (pR != null) {
        canvas.drawCircle(pR, 3.5, Paint()..color = const Color(0xFF34D399));
      }
    }
  }

  void _drawSkidMarks(
    Canvas canvas,
    Offset? Function(Vec3) project,
  ) {
    if (sim.leftSkidMarks.length < 2) return;

    for (var i = 0; i < sim.leftSkidMarks.length - 1; i++) {
      final sp0 = sim.leftSkidMarks[i];
      final sp1 = sim.leftSkidMarks[i + 1];

      final p0 = project(sp0.pos);
      final p1 = project(sp1.pos);
      if (p0 != null && p1 != null) {
        final skidPaint = Paint()
          ..color = Color.fromRGBO(20, 20, 24, sp0.alpha)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p0, p1, skidPaint);
      }
    }

    for (var i = 0; i < sim.rightSkidMarks.length - 1; i++) {
      final sp0 = sim.rightSkidMarks[i];
      final sp1 = sim.rightSkidMarks[i + 1];

      final p0 = project(sp0.pos);
      final p1 = project(sp1.pos);
      if (p0 != null && p1 != null) {
        final skidPaint = Paint()
          ..color = Color.fromRGBO(20, 20, 24, sp0.alpha)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p0, p1, skidPaint);
      }
    }
  }

  void _drawCones(
    Canvas canvas,
    Offset? Function(Vec3) project,
  ) {
    final conePaint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 1.6;

    for (final c in sim.cones) {
      final base = c.position;
      final apex = Vec3(base.x, base.y + 0.65, base.z);

      const r = 0.22;
      final b0 = Vec3(base.x - r, base.y, base.z - r);
      final b1 = Vec3(base.x + r, base.y, base.z - r);
      final b2 = Vec3(base.x + r, base.y, base.z + r);
      final b3 = Vec3(base.x - r, base.y, base.z + r);

      final pb0 = project(b0);
      final pb1 = project(b1);
      final pb2 = project(b2);
      final pb3 = project(b3);
      final pa = project(apex);

      if (pa != null) {
        if (pb0 != null) canvas.drawLine(pa, pb0, conePaint);
        if (pb1 != null) canvas.drawLine(pa, pb1, conePaint);
        if (pb2 != null) canvas.drawLine(pa, pb2, conePaint);
        if (pb3 != null) canvas.drawLine(pa, pb3, conePaint);
      }
      if (pb0 != null && pb1 != null) canvas.drawLine(pb0, pb1, conePaint);
      if (pb1 != null && pb2 != null) canvas.drawLine(pb1, pb2, conePaint);
      if (pb2 != null && pb3 != null) canvas.drawLine(pb2, pb3, conePaint);
      if (pb3 != null && pb0 != null) canvas.drawLine(pb3, pb0, conePaint);
    }
  }

  void _drawVehicle(
    Canvas canvas,
    Size size,
    Mat4 viewProj,
    Vec3 eye,
    Offset? Function(Vec3) project,
  ) {
    // Construct vehicle world transformation matrix
    // Rotation order: Y (yaw) -> X (pitch) -> Z (roll)
    final cy = cos(sim.yaw);
    final sy = sin(sim.yaw);
    final cp = cos(sim.pitch);
    final sp = sin(sim.pitch);
    final cr = cos(sim.roll);
    final sr = sin(sim.roll);

    // Ry * Rx * Rz
    final rot = Mat4([
      cy * cr + sy * sp * sr, cp * sr, -sy * cr + cy * sp * sr, 0,
      -cy * sr + sy * sp * cr, cp * cr, sy * sr + cy * sp * cr, 0,
      sy * cp, -sp, cy * cp, 0,
      0, 0, 0, 1,
    ]);

    final trans = Mat4([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      sim.position.x, sim.position.y, sim.position.z, 1,
    ]);

    final vehicleMatrix = trans * rot;
    final wheels = _resolvedWheels;

    // Contact shadow under vehicle chassis onto asphalt (ground pinned)
    _drawVehicleContactShadow(canvas, project, wheels);

    final showSolid = renderMode == TestDriveRenderMode.solid ||
        renderMode == TestDriveRenderMode.hybrid;
    final showWire = renderMode == TestDriveRenderMode.wireframe ||
        renderMode == TestDriveRenderMode.hybrid;

    if (showSolid) {
      if (model != null && model!.instances.isNotEmpty) {
        _drawModelSolid(
            canvas, size, vehicleMatrix, rot, viewProj, eye, wheels);
      } else {
        _drawProceduralSolidCar(
            canvas, size, vehicleMatrix, rot, viewProj, eye, project, wheels);
      }
    }

    if (showWire) {
      if (model != null && model!.instances.isNotEmpty) {
        _drawModelGeometry(canvas, vehicleMatrix, project, wheels);
      } else {
        _drawProceduralSportsCar(canvas, vehicleMatrix, project, wheels);
      }
    }

    // Emergency Siren Strobe (Police / Safety Car lights)
    if (sirenEnabled) {
      _drawEmergencySirenStrobe(canvas, vehicleMatrix, project);
    }

    // Draw headlight glow beams
    if (lighting != TestDriveLighting.day) {
      _drawHeadlightBeams(canvas, vehicleMatrix, project);
    }
  }

  void _drawEmergencySirenStrobe(
    Canvas canvas,
    Mat4 vehicleMatrix,
    Offset? Function(Vec3) project,
  ) {
    // Red on left (-0.28), Blue on right (+0.28)
    final timeMs = DateTime.now().millisecondsSinceEpoch;
    final flashCycle = (timeMs / 120).floor() % 4;
    final redActive = flashCycle == 0 || flashCycle == 1;
    final blueActive = flashCycle == 2 || flashCycle == 3;

    final redPos = vehicleMatrix.transformPoint(const Vec3(-0.30, 1.35, 0.28));
    final bluePos = vehicleMatrix.transformPoint(const Vec3(0.30, 1.35, 0.28));
    final barMid = vehicleMatrix.transformPoint(const Vec3(0.0, 1.33, 0.28));

    final pRed = project(redPos);
    final pBlue = project(bluePos);
    final pBar = project(barMid);

    if (pBar != null) {
      final barPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..strokeWidth = 3.5;
      if (pRed != null && pBlue != null) {
        canvas.drawLine(pRed, pBlue, barPaint);
      }

      if (pRed != null) {
        final redColor = redActive ? const Color(0xFFFF1744) : const Color(0x60800010);
        final redGlow = Paint()
          ..color = redActive ? const Color(0x90FF1744) : const Color(0x00000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        if (redActive) {
          canvas.drawCircle(pRed, 12, redGlow);
        }
        canvas.drawCircle(pRed, 4.5, Paint()..color = redColor);
      }

      if (pBlue != null) {
        final blueColor = blueActive ? const Color(0xFF00E5FF) : const Color(0x60002860);
        final blueGlow = Paint()
          ..color = blueActive ? const Color(0x9000E5FF) : const Color(0x00000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        if (blueActive) {
          canvas.drawCircle(pBlue, 12, blueGlow);
        }
        canvas.drawCircle(pBlue, 4.5, Paint()..color = blueColor);
      }
    }
  }

  void _drawModelSolid(
    Canvas canvas,
    Size size,
    Mat4 vehicleMatrix,
    Mat4 rot,
    Mat4 viewProj,
    Vec3 eye,
    Map<String, DetectedWheel> wheels,
  ) {
    final scene = SolidScene.of(model!);
    if (scene.isEmpty) {
      _drawModelGeometry(canvas, vehicleMatrix, (p) {
        final clip = viewProj.transformClip(p);
        if (clip[3] <= 0.05) return null;
        final sx = (clip[0] / clip[3] * 0.5 + 0.5) * size.width;
        final sy = (1.0 - (clip[1] / clip[3] * 0.5 + 0.5)) * size.height;
        return Offset(sx, sy);
      }, wheels);
      return;
    }

    final mesh = scene.interactive;
    final triCount = mesh.triangleCount;
    if (triCount == 0) return;

    final mbb = model!.worldBBox;
    final lowestTireY = wheels.isNotEmpty
        ? wheels.values.map((w) => w.worldPosition.y - w.radius).reduce(min)
        : mbb.lo.y;
    final alignOffset = Vec3(-mbb.center.x, -lowestTireY, -mbb.center.z);
    final alignMatrix = Mat4([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      alignOffset.x, alignOffset.y, alignOffset.z, 1,
    ]);

    final carModelMatrix = vehicleMatrix * alignMatrix;
    final carViewProj = viewProj * carModelMatrix;

    // Lighting setup according to TestDriveLighting
    final (
      worldKeyLight,
      worldFillLight,
      worldRimLight,
      keyIntensity,
      fillIntensity,
      rimIntensity,
      ambientBase,
      ambientScale,
    ) = switch (lighting) {
      TestDriveLighting.day => (
        const Vec3(-0.55, 0.90, 0.20).normalized,
        const Vec3(0.50, 0.35, -0.40).normalized,
        const Vec3(0.20, 0.45, -0.80).normalized,
        0.82,
        0.30,
        0.22,
        0.32,
        0.16,
      ),
      TestDriveLighting.sunset => (
        const Vec3(-0.70, 0.40, 0.50).normalized,
        const Vec3(0.60, 0.30, -0.30).normalized,
        const Vec3(0.10, 0.50, -0.70).normalized,
        0.78,
        0.25,
        0.30,
        0.26,
        0.12,
      ),
      TestDriveLighting.night => (
        const Vec3(0.35, 0.65, -0.65).normalized,
        const Vec3(-0.45, 0.35, 0.40).normalized,
        const Vec3(-0.20, 0.50, -0.80).normalized,
        0.65,
        0.15,
        0.35,
        0.15,
        0.08,
      ),
    };

    // Transform directional lights to model local space via rot.transpose
    final rm = rot.m;
    Vec3 rotTranspose(Vec3 v) => Vec3(
      rm[0] * v.x + rm[1] * v.y + rm[2] * v.z,
      rm[4] * v.x + rm[5] * v.y + rm[6] * v.z,
      rm[8] * v.x + rm[9] * v.y + rm[10] * v.z,
    );

    final keyLight = rotTranspose(worldKeyLight);
    final fillLight = rotTranspose(worldFillLight);
    final rimLight = rotTranspose(worldRimLight);

    // Transform camera eye to model local space
    final dEye = eye - sim.position;
    final localEyeUnshifted = rotTranspose(dEye);
    final localEye = localEyeUnshifted - alignOffset;

    // Build the 9 transforms:
    // 0..3: spinning wheel parts (steer + roll)
    // 4..7: caliper & hub frame parts (steer only)
    // 8: chassis / vehicle body
    final wvpMatrices = List<Mat4>.filled(9, carViewProj);
    final keyLights = List<Vec3>.filled(9, keyLight);
    final fillLights = List<Vec3>.filled(9, fillLight);
    final rimLights = List<Vec3>.filled(9, rimLight);
    final eyes = List<Vec3>.filled(9, localEye);

    final nonWheelNodes = <int>{};
    if (detection?.body != null) {
      nonWheelNodes.add(detection!.body!.nodeIndex);
    }
    final carBox = model!.worldBBox;
    final carLen = max(carBox.size.z.abs(), carBox.size.x.abs());
    final carW = min(carBox.size.z.abs(), carBox.size.x.abs());
    final carH = carBox.size.y.abs();
    for (final inst in model!.instances) {
      final s = inst.worldBBox.size;
      final maxDim = max(s.x.abs(), max(s.y.abs(), s.z.abs()));
      if (s.z.abs() > carLen * 0.45 ||
          s.x.abs() > carW * 0.48 ||
          s.y.abs() > carH * 0.70 ||
          maxDim > carLen * 0.45) {
        nonWheelNodes.add(inst.nodeIndex);
      }
    }

    final sharedOrBodyNodes = <int>{
      if (detection?.body != null) detection!.body!.nodeIndex,
    };
    for (final inst in model!.instances) {
      final s = inst.worldBBox.size;
      if (max(s.x.abs(), s.z.abs()) > carLen * 0.42) {
        sharedOrBodyNodes.add(inst.nodeIndex);
      }
    }
    for (final w in wheels.values) {
      for (final n in [
        ...w.partNodeIndices,
        ...w.spinNodeIndices,
        ...w.caliperHubNodeIndices,
        w.nodeIndex
      ]) {
        if (!sharedOrBodyNodes.contains(n)) {
          nonWheelNodes.remove(n);
        }
      }
    }

    final nodeToTransform = <int, int>{};
    void assignSolidTransform(int nodeIdx, int transformIdx) {
      if (nonWheelNodes.contains(nodeIdx)) return;
      nodeToTransform[nodeIdx] = transformIdx;
    }

    const corners = ['FL', 'FR', 'RL', 'RR'];
    for (var c = 0; c < 4; c++) {
      final corner = corners[c];
      final w = wheels[corner];
      if (w == null) continue;

      final spinIdx = c;
      final calIdx = c + 4;

      final isFront = corner.startsWith('F') || w.axle == 'front';
      final steer = isFront
          ? (sim.frontSteering ? sim.steerAngle : 0.0)
          : (sim.rearSteering ? -sim.steerAngle * 0.5 : 0.0);
      final r = w.radius > 0.05 ? w.radius : 0.34;
      final roll = -sim.wheelRoll / r;
      final hub = w.worldPosition;

      // Spinning matrix (steer + roll)
      final spinLocalMat = _buildWheelLocalMatrix(hub, alignOffset, steer, roll);
      wvpMatrices[spinIdx] = viewProj * (vehicleMatrix * spinLocalMat);
      keyLights[spinIdx] = _applyWheelRotTranspose(keyLight, steer, roll);
      fillLights[spinIdx] = _applyWheelRotTranspose(fillLight, steer, roll);
      rimLights[spinIdx] = _applyWheelRotTranspose(rimLight, steer, roll);
      final dVehHubSpin = localEyeUnshifted - (hub + alignOffset);
      eyes[spinIdx] = hub + _applyWheelRotTranspose(dVehHubSpin, steer, roll);

      // Caliper matrix (steer only)
      final calLocalMat = _buildWheelLocalMatrix(hub, alignOffset, steer, 0.0);
      wvpMatrices[calIdx] = viewProj * (vehicleMatrix * calLocalMat);
      keyLights[calIdx] = _applyWheelRotTranspose(keyLight, steer, 0.0);
      fillLights[calIdx] = _applyWheelRotTranspose(fillLight, steer, 0.0);
      rimLights[calIdx] = _applyWheelRotTranspose(rimLight, steer, 0.0);
      final dVehHubCal = localEyeUnshifted - (hub + alignOffset);
      eyes[calIdx] = hub + _applyWheelRotTranspose(dVehHubCal, steer, 0.0);

      // Map nodes to transforms with strict body/chassis guard
      if (w.spinNodeIndices.isNotEmpty || w.caliperHubNodeIndices.isNotEmpty) {
        for (final n in w.spinNodeIndices) {
          assignSolidTransform(n, spinIdx);
        }
        for (final n in w.caliperHubNodeIndices) {
          assignSolidTransform(n, calIdx);
        }
      } else if (w.partNodeIndices.isNotEmpty) {
        for (final n in w.partNodeIndices) {
          assignSolidTransform(n, spinIdx);
        }
      } else if (!nonWheelNodes.contains(w.nodeIndex)) {
        assignSolidTransform(w.nodeIndex, spinIdx);
      }
    }

    // Pre-calculate cylinder bounds for wheel corners. The half-width is
    // clamped so an inflated tire width can never grab fenders or mudflaps,
    // and each corner tracks whether it already has a dedicated wheel node.
    final wheelEnvelopes = <int, ({
      Vec3 hub,
      double rMaxSq,
      double halfW,
      bool hasDedicatedNode,
    })>{};
    for (var c = 0; c < 4; c++) {
      final corner = corners[c];
      final w = wheels[corner];
      if (w != null) {
        final baseR = w.radius > 0.05 ? w.radius : 0.34;
        final r = baseR * 1.08;
        final clampedW = min(w.width > 0.05 ? w.width : 0.28, baseR * 0.95);
        final halfW = max(clampedW * 0.52, baseR * 0.28);
        final candidateNodes = <int>{
          ...w.spinNodeIndices,
          ...w.caliperHubNodeIndices,
          ...w.partNodeIndices,
          w.nodeIndex,
        };
        final hasDedicatedNode = candidateNodes.any(
          (n) => n >= 0 && nodeToTransform.containsKey(n),
        );
        wheelEnvelopes[c] = (
          hub: w.worldPosition,
          rMaxSq: r * r,
          halfW: halfW,
          hasDedicatedNode: hasDedicatedNode,
        );
      }
    }

    final triTransform = Uint8List(triCount);
    final indices = mesh.indices;
    final triNode = mesh.triNode;
    final triKind = mesh.triKind;
    final centroids = mesh.centroids;
    for (var t = 0; t < triCount; t++) {
      final n = triNode[t];
      final kind = triKind[t];
      final cx = centroids[t * 3];
      final cy = centroids[t * 3 + 1];
      final cz = centroids[t * 3 + 2];
      var k = 8;

      if (!nonWheelNodes.contains(n)) {
        final cand = nodeToTransform[n];
        if (cand != null) {
          if (kind == solidKindBody ||
              kind == solidKindGlass ||
              kind == solidKindInterior ||
              kind == solidKindHeadlight ||
              kind == solidKindTaillight) {
            k = 8;
          } else {
            // Verify the triangle is actually near the assigned wheel hub so
            // non-wheel islands sharing the node stay on the chassis.
            final env = wheelEnvelopes[cand % 4];
            if (env != null) {
              final dx = (cx - env.hub.x).abs();
              final dy = cy - env.hub.y;
              final dz = cz - env.hub.z;
              if (dx <= env.halfW * 1.35 &&
                  (dy * dy + dz * dz) <= env.rMaxSq * 1.25) {
                k = cand;
              }
            } else {
              k = cand;
            }
          }
        }
      }

      // Per-triangle cylinder fallback only for corners without a dedicated
      // wheel node (single-mesh STL/OBJ), and never on body/glass/interior.
      if (k == 8 &&
          kind != solidKindBody &&
          kind != solidKindGlass &&
          kind != solidKindInterior &&
          kind != solidKindHeadlight &&
          kind != solidKindTaillight &&
          wheelEnvelopes.isNotEmpty) {
        for (final entry in wheelEnvelopes.entries) {
          final env = entry.value;
          if (env.hasDedicatedNode) continue;
          final dx = (cx - env.hub.x).abs();
          if (dx <= env.halfW) {
            final dy = cy - env.hub.y;
            final dz = cz - env.hub.z;
            if (dy * dy + dz * dz <= env.rMaxSq) {
              k = entry.key; // spinIdx for wheel c (0..3)
              break;
            }
          }
        }
      }
      triTransform[t] = k;
    }

    // 1. Cull, shade, project and record visible triangles with per-triangle transformation
    final width = size.width;
    final height = size.height;
    const near = 0.05;

    final pos = mesh.positions;
    final normals = mesh.normals;
    final triColor = mesh.triColor;
    final visTri = mesh.visTri;
    final visColor = mesh.visColor;
    final visDepth = mesh.visDepth;
    final triCoords = Float32List(triCount * 6);

    // Imported models keep a neutral silver-white body so their authored
    // material/UV tints read correctly; the accent only paints demo cars.
    final bodyPaintRgb = model != null ? 0xFFD6DBDF : accentColor.toARGB32();
    final kindColors = <int>[
      bodyPaintRgb, // 0: solidKindBody
      0xCC162832,   // 1: solidKindGlass
      0xFF1E2225,   // 2: solidKindWheel
      0xFFCBD5E1,   // 3: solidKindRim
      0xFF1F2327,   // 4: solidKindInterior
      0xFF202428,   // 5: solidKindTrim
      0xFFE8F4FC,   // 6: solidKindHeadlight
      0xFFDC2626,   // 7: solidKindTaillight
      0xFF181A1C,   // 8: solidKindChassis
    ];

    var visCount = 0;
    var minDepth = double.infinity;
    var maxDepth = double.negativeInfinity;

    for (var t = 0; t < triCount; t++) {
      final k = triTransform[t];
      final m = wvpMatrices[k].m;
      final t3 = t * 3;
      final ia = indices[t3], ib = indices[t3 + 1], ic = indices[t3 + 2];

      final pa = ia * 3;
      final xa = pos[pa], ya = pos[pa + 1], za = pos[pa + 2];
      final wa = m[3] * xa + m[7] * ya + m[11] * za + m[15];
      if (wa <= near) continue;

      final pb = ib * 3;
      final xb = pos[pb], yb = pos[pb + 1], zb = pos[pb + 2];
      final wb = m[3] * xb + m[7] * yb + m[11] * zb + m[15];
      if (wb <= near) continue;

      final pc = ic * 3;
      final xc = pos[pc], yc = pos[pc + 1], zc = pos[pc + 2];
      final wc = m[3] * xc + m[7] * yc + m[11] * zc + m[15];
      if (wc <= near) continue;

      final invWa = 1.0 / wa;
      final x0 = ((m[0] * xa + m[4] * ya + m[8] * za + m[12]) * invWa * 0.5 + 0.5) * width;
      final y0 = (1.0 - ((m[1] * xa + m[5] * ya + m[9] * za + m[13]) * invWa * 0.5 + 0.5)) * height;

      final invWb = 1.0 / wb;
      final x1 = ((m[0] * xb + m[4] * yb + m[8] * zb + m[12]) * invWb * 0.5 + 0.5) * width;
      final y1 = (1.0 - ((m[1] * xb + m[5] * yb + m[9] * zb + m[13]) * invWb * 0.5 + 0.5)) * height;

      final invWc = 1.0 / wc;
      final x2 = ((m[0] * xc + m[4] * yc + m[8] * zc + m[12]) * invWc * 0.5 + 0.5) * width;
      final y2 = (1.0 - ((m[1] * xc + m[5] * yc + m[9] * zc + m[13]) * invWc * 0.5 + 0.5)) * height;

      // Off-screen culling
      if (max(x0, max(x1, x2)) < 0 || min(x0, min(x1, x2)) > width) continue;
      if (max(y0, max(y1, y2)) < 0 || min(y0, min(y1, y2)) > height) continue;

      final area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
      if (area.abs() < 1e-6) continue;

      final nx = normals[t3], ny = normals[t3 + 1], nz = normals[t3 + 2];
      final cx = centroids[t3], cy = centroids[t3 + 1], cz = centroids[t3 + 2];

      final eyeL = eyes[k];
      final toEyeX = eyeL.x - cx;
      final toEyeY = eyeL.y - cy;
      final toEyeZ = eyeL.z - cz;

      final dotEye = nx * toEyeX + ny * toEyeY + nz * toEyeZ;
      final isDoubleSided = triKind[t] == 1 ||
          triKind[t] == 4 ||
          triKind[t] == 5 ||
          triKind[t] == 6 ||
          triKind[t] == 7 ||
          triKind[t] == 8 ||
          (triColor[t] != 0 && (triColor[t] & 0xFF000000) != 0xFF000000);
      if (dotEye <= 0.0 && !isDoubleSided) continue;

      final effNx = dotEye < 0.0 ? -nx : nx;
      final effNy = dotEye < 0.0 ? -ny : ny;
      final effNz = dotEye < 0.0 ? -nz : nz;

      final eyeDistSq = toEyeX * toEyeX + toEyeY * toEyeY + toEyeZ * toEyeZ;
      if (eyeDistSq < 1e-12) continue;
      final invEye = 1.0 / sqrt(eyeDistSq);
      final ex = toEyeX * invEye;
      final ey = toEyeY * invEye;
      final ez = toEyeZ * invEye;

      final materialColor = triColor[t];
      final kind = triKind[t];
      final nodeIdx = triNode[t];
      final isBodyNode = nonWheelNodes.contains(nodeIdx);

      final int base;
      if (materialColor != 0) {
        base = materialColor;
      } else {
        if (kind == solidKindBody || (isBodyNode && kind == solidKindChassis)) {
          base = bodyPaintRgb;
        } else if (kind < kindColors.length) {
          base = kindColors[kind];
        } else {
          base = bodyPaintRgb;
        }
      }

      final keyL = keyLights[k];
      final fillL = fillLights[k];
      final rimL = rimLights[k];

      final dotKey = effNx * keyL.x + effNy * keyL.y + effNz * keyL.z;
      final diffuseKey = dotKey > 0.0 ? dotKey : 0.0;
      final dotFill = effNx * fillL.x + effNy * fillL.y + effNz * fillL.z;
      final diffuseFill = dotFill > 0.0 ? dotFill : 0.0;
      final dotRim = effNx * rimL.x + effNy * rimL.y + effNz * rimL.z;
      final diffuseRim = dotRim > 0.0 ? dotRim : 0.0;

      var ambient = ambientBase + ambientScale * effNy;
      if (ambient < 0.20) ambient = 0.20;
      if (ambient > 0.45) ambient = 0.45;

      var diffuse = ambient +
          diffuseKey * keyIntensity +
          diffuseFill * fillIntensity +
          diffuseRim * rimIntensity;
      if (diffuse < 0.25) diffuse = 0.25;
      if (diffuse > 1.05) diffuse = 1.05;

      // Specular highlight with clearcoat luster on vehicle body
      final hx = keyL.x + ex, hy = keyL.y + ey, hz = keyL.z + ez;
      final hLenSq = hx * hx + hy * hy + hz * hz;
      var specKey = 0.0;
      if (hLenSq > 1e-6) {
        final invH = 1.0 / sqrt(hLenSq);
        final ndoth = effNx * hx * invH + effNy * hy * invH + effNz * hz * invH;
        if (ndoth > 0.0) {
          final s2 = ndoth * ndoth;
          final s4 = s2 * s2;
          final s8 = s4 * s4;
          final s16 = s8 * s8;
          final s32 = s16 * s16;
          final isBody = (kind == solidKindBody || (isBodyNode && kind == solidKindChassis));
          specKey = s32 * (isBody ? 0.45 : 0.30);
        }
      }

      final whiteGloss = specKey * 255.0;
      final baseR = (base >> 16) & 0xFF;
      final baseG = (base >> 8) & 0xFF;
      final baseB = base & 0xFF;

      final r = (baseR * diffuse + whiteGloss).round().clamp(0, 255);
      final g = (baseG * diffuse + whiteGloss).round().clamp(0, 255);
      final b = (baseB * diffuse + whiteGloss).round().clamp(0, 255);
      final argb = (base & 0xFF000000) | (r << 16) | (g << 8) | b;

      final wm = wvpMatrices[k].m;
      final depth = wm[3] * cx + wm[7] * cy + wm[11] * cz + wm[15];
      visTri[visCount] = t;
      visColor[visCount] = argb;
      visDepth[visCount] = depth;
      final p6 = visCount * 6;
      triCoords[p6] = x0;
      triCoords[p6 + 1] = y0;
      triCoords[p6 + 2] = x1;
      triCoords[p6 + 3] = y1;
      triCoords[p6 + 4] = x2;
      triCoords[p6 + 5] = y2;
      if (depth < minDepth) minDepth = depth;
      if (depth > maxDepth) maxDepth = depth;
      visCount++;
    }

    if (visCount == 0) return;

    // 3. Bucket sort on view depth (O(n))
    const bucketCount = 16384;
    final range = maxDepth - minDepth;
    final scale = range > 1e-9 ? (bucketCount - 1) / range : 0.0;
    final visBucket = mesh.visBucket;
    final cursor = Int32List(bucketCount + 1);
    for (var i = 0; i < visCount; i++) {
      var bucket = ((maxDepth - visDepth[i]) * scale).toInt();
      if (bucket < 0) bucket = 0;
      if (bucket > bucketCount - 1) bucket = bucketCount - 1;
      visBucket[i] = bucket;
      cursor[bucket + 1]++;
    }
    for (var b = 0; b < bucketCount; b++) {
      cursor[b + 1] += cursor[b];
    }
    final order = mesh.sortedOrder;
    for (var i = 0; i < visCount; i++) {
      order[cursor[visBucket[i]]++] = i;
    }

    // 4. Emit sorted triangles to hardware vertex buffer
    final drawPos = mesh.drawPositions;
    final drawCol = mesh.drawColors;
    for (var k = 0; k < visCount; k++) {
      final i = order[k];
      final src = i * 6;
      final dst = k * 6;
      drawPos[dst] = triCoords[src];
      drawPos[dst + 1] = triCoords[src + 1];
      drawPos[dst + 2] = triCoords[src + 2];
      drawPos[dst + 3] = triCoords[src + 3];
      drawPos[dst + 4] = triCoords[src + 4];
      drawPos[dst + 5] = triCoords[src + 5];
      final c = k * 3;
      final argb = visColor[i];
      drawCol[c] = argb;
      drawCol[c + 1] = argb;
      drawCol[c + 2] = argb;
    }

    final paint = Paint();
    const chunk = 20000;
    for (var start = 0; start < visCount; start += chunk) {
      final count = min(chunk, visCount - start);
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(drawPos, start * 6, (start + count) * 6),
        colors: Int32List.sublistView(drawCol, start * 3, (start + count) * 3),
      );
      canvas.drawVertices(vertices, BlendMode.dst, paint);
    }
  }

  void _drawProceduralSolidCar(
    Canvas canvas,
    Size size,
    Mat4 vehicleMatrix,
    Mat4 rot,
    Mat4 viewProj,
    Vec3 eye,
    Offset? Function(Vec3) project,
    Map<String, DetectedWheel> wheels,
  ) {
    final isDay = lighting == TestDriveLighting.day;
    final isSunset = lighting == TestDriveLighting.sunset;

    final rm = rot.m;
    Vec3 rotTranspose(Vec3 v) => Vec3(
      rm[0] * v.x + rm[1] * v.y + rm[2] * v.z,
      rm[4] * v.x + rm[5] * v.y + rm[6] * v.z,
      rm[8] * v.x + rm[9] * v.y + rm[10] * v.z,
    );

    final worldKey = switch (lighting) {
      TestDriveLighting.day => const Vec3(-0.55, 0.90, 0.20).normalized,
      TestDriveLighting.sunset => const Vec3(-0.70, 0.40, 0.50).normalized,
      TestDriveLighting.night => const Vec3(0.35, 0.65, -0.65).normalized,
    };
    final localKey = rotTranspose(worldKey);

    Paint makeShadedPaint(Color base, Vec3 normal, {double shininess = 0.25}) {
      final dot = (normal.x * localKey.x + normal.y * localKey.y + normal.z * localKey.z).clamp(0.0, 1.0);
      final ambient = isDay ? 0.35 : (isSunset ? 0.25 : 0.15);
      final diffuse = ambient + dot * (isDay ? 0.65 : (isSunset ? 0.55 : 0.45));
      final baseVal = base.toARGB32();
      final baseA = (baseVal >> 24) & 0xFF;
      final baseR = (baseVal >> 16) & 0xFF;
      final baseG = (baseVal >> 8) & 0xFF;
      final baseB = baseVal & 0xFF;
      final r = ((baseR * diffuse) + (dot > 0.85 ? 40 * shininess : 0)).round().clamp(0, 255);
      final g = ((baseG * diffuse) + (dot > 0.85 ? 40 * shininess : 0)).round().clamp(0, 255);
      final b = ((baseB * diffuse) + (dot > 0.85 ? 40 * shininess : 0)).round().clamp(0, 255);
      return Paint()
        ..color = Color.fromARGB(baseA, r, g, b)
        ..style = PaintingStyle.fill;
    }

    final bodyColor = accentColor;
    final glassColor = const Color(0xDD162832);
    final darkTrimColor = const Color(0xFF1E293B);

    // 1. Hood / Front Nose
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.68, -1.7)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.68, -1.7)),
      vehicleMatrix.transformPoint(const Vec3(0.85, 0.85, -0.6)),
      vehicleMatrix.transformPoint(const Vec3(-0.85, 0.85, -0.6)),
      makeShadedPaint(bodyColor, const Vec3(0, 0.95, -0.3)),
    );

    // Front Bumper / Splitter Face
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.95, 0.22, -1.9)),
      vehicleMatrix.transformPoint(const Vec3(0.95, 0.22, -1.9)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.68, -1.7)),
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.68, -1.7)),
      makeShadedPaint(darkTrimColor, const Vec3(0, 0.2, -0.98)),
    );

    // 2. Windshield
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.85, 0.85, -0.6)),
      vehicleMatrix.transformPoint(const Vec3(0.85, 0.85, -0.6)),
      vehicleMatrix.transformPoint(const Vec3(0.68, 1.32, -0.2)),
      vehicleMatrix.transformPoint(const Vec3(-0.68, 1.32, -0.2)),
      makeShadedPaint(glassColor, const Vec3(0, 0.7, -0.7)),
    );

    // 3. Roof
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.68, 1.32, -0.2)),
      vehicleMatrix.transformPoint(const Vec3(0.68, 1.32, -0.2)),
      vehicleMatrix.transformPoint(const Vec3(0.68, 1.32, 0.75)),
      vehicleMatrix.transformPoint(const Vec3(-0.68, 1.32, 0.75)),
      makeShadedPaint(bodyColor, const Vec3(0, 1.0, 0)),
    );

    // 4. Rear Window
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.68, 1.32, 0.75)),
      vehicleMatrix.transformPoint(const Vec3(0.68, 1.32, 0.75)),
      vehicleMatrix.transformPoint(const Vec3(0.85, 0.85, 1.3)),
      vehicleMatrix.transformPoint(const Vec3(-0.85, 0.85, 1.3)),
      makeShadedPaint(glassColor, const Vec3(0, 0.7, 0.7)),
    );

    // 5. Engine Deck & Spoiler
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.85, 0.85, 1.3)),
      vehicleMatrix.transformPoint(const Vec3(0.85, 0.85, 1.3)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.88, 1.85)),
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.88, 1.85)),
      makeShadedPaint(bodyColor, const Vec3(0, 0.95, 0.3)),
    );

    // 6. Rear Bumper & Diffuser
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.88, 1.85)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.88, 1.85)),
      vehicleMatrix.transformPoint(const Vec3(0.95, 0.22, 1.9)),
      vehicleMatrix.transformPoint(const Vec3(-0.95, 0.22, 1.9)),
      makeShadedPaint(darkTrimColor, const Vec3(0, -0.1, 0.99)),
    );

    // 7. Left Side Flank
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(-0.95, 0.22, -1.9)),
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.68, -1.7)),
      vehicleMatrix.transformPoint(const Vec3(-0.90, 0.88, 1.85)),
      vehicleMatrix.transformPoint(const Vec3(-0.95, 0.22, 1.9)),
      makeShadedPaint(bodyColor, const Vec3(-1.0, 0, 0)),
    );

    // 8. Right Side Flank
    _drawQuad(
      canvas,
      viewProj,
      size,
      vehicleMatrix.transformPoint(const Vec3(0.95, 0.22, -1.9)),
      vehicleMatrix.transformPoint(const Vec3(0.95, 0.22, 1.9)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.88, 1.85)),
      vehicleMatrix.transformPoint(const Vec3(0.90, 0.68, -1.7)),
      makeShadedPaint(bodyColor, const Vec3(1.0, 0, 0)),
    );

    // 9. 4 Solid 3D Wheels with Alloy Rims, Calipers, Steering and Roll
    final wheelPositions = [
      wheels['FL']?.worldPosition ?? (sim.wheelPositions.isNotEmpty ? sim.wheelPositions[0] : const Vec3(-0.95, 0.36, -1.25)),
      wheels['FR']?.worldPosition ?? (sim.wheelPositions.length > 1 ? sim.wheelPositions[1] : const Vec3(0.95, 0.36, -1.25)),
      wheels['RL']?.worldPosition ?? (sim.wheelPositions.length > 2 ? sim.wheelPositions[2] : const Vec3(-0.95, 0.36, 1.25)),
      wheels['RR']?.worldPosition ?? (sim.wheelPositions.length > 3 ? sim.wheelPositions[3] : const Vec3(0.95, 0.36, 1.25)),
    ];

    final wheelRadii = [
      wheels['FL']?.radius ?? 0.36,
      wheels['FR']?.radius ?? 0.36,
      wheels['RL']?.radius ?? 0.36,
      wheels['RR']?.radius ?? 0.36,
    ];

    final wheelWidths = [
      wheels['FL']?.width ?? 0.26,
      wheels['FR']?.width ?? 0.26,
      wheels['RL']?.width ?? 0.26,
      wheels['RR']?.width ?? 0.26,
    ];

    for (var i = 0; i < 4; i++) {
      final isFront = i < 2;
      final isLeft = (i % 2 == 0);
      final r = wheelRadii[i].clamp(0.20, 0.55);
      final w = wheelWidths[i].clamp(0.12, 0.40);
      final roll = -sim.wheelRoll / r;
      final steer = isFront
          ? (sim.frontSteering ? sim.steerAngle : 0.0)
          : (sim.rearSteering ? -sim.steerAngle * 0.5 : 0.0);

      _drawSolidProceduralWheel(
        canvas: canvas,
        viewProj: viewProj,
        size: size,
        vehicleMatrix: vehicleMatrix,
        localCenter: wheelPositions[i],
        radius: r,
        width: w,
        steerAngle: steer,
        rollAngle: roll,
        isLeft: isLeft,
      );
    }
  }

  void _drawSolidProceduralWheel({
    required Canvas canvas,
    required Mat4 viewProj,
    required Size size,
    required Mat4 vehicleMatrix,
    required Vec3 localCenter,
    required double radius,
    required double width,
    required double steerAngle,
    required double rollAngle,
    required bool isLeft,
  }) {
    final cs = cos(steerAngle);
    final ss = sin(steerAngle);
    final hw = width * 0.5;

    Vec3 toVehicleSpace(double x, double y, double z) {
      final rx = x * cs + z * ss;
      final rz = -x * ss + z * cs;
      return Vec3(localCenter.x + rx, localCenter.y + y, localCenter.z + rz);
    }

    final tirePaint = Paint()
      ..color = const Color(0xFF1E2225)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;
    final hubPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.fill;
    final caliperPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;

    // 1. Red Brake Caliper
    final outX = isLeft ? -hw - 0.02 : hw + 0.02;
    final inX = isLeft ? -0.02 : 0.02;
    final cal0 = vehicleMatrix.transformPoint(toVehicleSpace(inX, radius * 0.45, -radius * 0.45));
    final cal1 = vehicleMatrix.transformPoint(toVehicleSpace(outX, radius * 0.45, -radius * 0.45));
    final cal2 = vehicleMatrix.transformPoint(toVehicleSpace(outX, radius * 0.75, -radius * 0.15));
    final cal3 = vehicleMatrix.transformPoint(toVehicleSpace(inX, radius * 0.75, -radius * 0.15));
    _drawQuad(canvas, viewProj, size, cal0, cal1, cal2, cal3, caliperPaint);

    // 2. Outer Tire Tread Cylinder (10 segments)
    const segments = 10;
    final rimRadius = radius * 0.68;
    final outerX = isLeft ? -hw : hw;
    final innerX = isLeft ? hw : -hw;

    for (var i = 0; i < segments; i++) {
      final a0 = rollAngle + (i * 2 * pi / segments);
      final a1 = rollAngle + ((i + 1) * 2 * pi / segments);

      final y0 = radius * cos(a0);
      final z0 = radius * sin(a0);
      final y1 = radius * cos(a1);
      final z1 = radius * sin(a1);

      // Tread quad
      final p0 = vehicleMatrix.transformPoint(toVehicleSpace(innerX, y0, z0));
      final p1 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, y0, z0));
      final p2 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, y1, z1));
      final p3 = vehicleMatrix.transformPoint(toVehicleSpace(innerX, y1, z1));
      _drawQuad(canvas, viewProj, size, p0, p1, p2, p3, tirePaint);

      // Sidewall rim quad
      final ry0 = rimRadius * cos(a0);
      final rz0 = rimRadius * sin(a0);
      final ry1 = rimRadius * cos(a1);
      final rz1 = rimRadius * sin(a1);

      final s0 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, ry0, rz0));
      final s1 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, y0, z0));
      final s2 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, y1, z1));
      final s3 = vehicleMatrix.transformPoint(toVehicleSpace(outerX, ry1, rz1));
      _drawQuad(canvas, viewProj, size, s0, s1, s2, s3, tirePaint);

      // Rim Face sector
      final hubY0 = radius * 0.18 * cos(a0);
      final hubZ0 = radius * 0.18 * sin(a0);
      final hubY1 = radius * 0.18 * cos(a1);
      final hubZ1 = radius * 0.18 * sin(a1);

      final isSpoke = (i % 2 == 0);
      final r0 = vehicleMatrix.transformPoint(toVehicleSpace(outerX + (isLeft ? -0.01 : 0.01), hubY0, hubZ0));
      final r1 = vehicleMatrix.transformPoint(toVehicleSpace(outerX + (isLeft ? -0.01 : 0.01), ry0, rz0));
      final r2 = vehicleMatrix.transformPoint(toVehicleSpace(outerX + (isLeft ? -0.01 : 0.01), ry1, rz1));
      final r3 = vehicleMatrix.transformPoint(toVehicleSpace(outerX + (isLeft ? -0.01 : 0.01), hubY1, hubZ1));
      _drawQuad(canvas, viewProj, size, r0, r1, r2, r3, isSpoke ? rimPaint : hubPaint);
    }
  }

  void _drawVehicleContactShadow(
    Canvas canvas,
    Offset? Function(Vec3) project,
    Map<String, DetectedWheel> wheels,
  ) {
    // Pinned strictly to ground plane Y = 0.003 (never tilts with pitch or roll)
    const groundY = 0.003;
    final carX = sim.position.x;
    final carZ = sim.position.z;
    final groundPos = Vec3(carX, groundY, carZ);

    // Ground forward and right vectors (strictly horizontal)
    final fwd = Vec3(-sin(sim.yaw), 0.0, -cos(sim.yaw));
    final right = Vec3(cos(sim.yaw), 0.0, -sin(sim.yaw));

    // Vehicle dimensions
    double halfL;
    double halfW;
    if (model != null) {
      final size = model!.worldBBox.size;
      halfL = (max(size.x.abs(), size.z.abs()) * 0.48).clamp(1.6, 2.8);
      halfW = (min(size.x.abs(), size.z.abs()) * 0.50).clamp(0.75, 1.25);
    } else {
      halfL = 2.15;
      halfW = 1.05;
    }

    final isDay = lighting == TestDriveLighting.day;
    final isSunset = lighting == TestDriveLighting.sunset;
    final penumbraAlpha = isDay ? 0.35 : (isSunset ? 0.45 : 0.60);
    final coreAlpha = isDay ? 0.55 : (isSunset ? 0.65 : 0.78);

    // 1. Soft Penumbra Shadow (Rounded aerodynamic envelope on ground)
    final penumbraPoints = [
      groundPos + (fwd * (halfL + 0.12)),
      groundPos + (fwd * (halfL * 0.92)) - (right * (halfW * 0.88)),
      groundPos + (fwd * (halfL * 0.55)) - (right * (halfW + 0.08)),
      groundPos - (fwd * (halfL * 0.60)) - (right * (halfW + 0.06)),
      groundPos - (fwd * (halfL * 0.95)) - (right * (halfW * 0.85)),
      groundPos - (fwd * (halfL + 0.10)),
      groundPos - (fwd * (halfL * 0.95)) + (right * (halfW * 0.85)),
      groundPos - (fwd * (halfL * 0.60)) + (right * (halfW + 0.06)),
      groundPos + (fwd * (halfL * 0.55)) + (right * (halfW + 0.08)),
      groundPos + (fwd * (halfL * 0.92)) + (right * (halfW * 0.88)),
    ];

    final penumbraPath = Path();
    var firstPoint = true;
    var allPenValid = true;
    for (final pt in penumbraPoints) {
      final p = project(pt);
      if (p == null) {
        allPenValid = false;
        break;
      }
      if (firstPoint) {
        penumbraPath.moveTo(p.dx, p.dy);
        firstPoint = false;
      } else {
        penumbraPath.lineTo(p.dx, p.dy);
      }
    }
    if (allPenValid && !firstPoint) {
      penumbraPath.close();
      final penumbraPaint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, penumbraAlpha)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawPath(penumbraPath, penumbraPaint);
    }

    // 2. Dense Core Underbody Ambient Occlusion Shadow
    final corePoints = [
      groundPos + (fwd * (halfL * 0.82)) - (right * (halfW * 0.75)),
      groundPos + (fwd * (halfL * 0.82)) + (right * (halfW * 0.75)),
      groundPos - (fwd * (halfL * 0.85)) + (right * (halfW * 0.72)),
      groundPos - (fwd * (halfL * 0.85)) - (right * (halfW * 0.72)),
    ];

    final corePath = Path();
    var coreFirst = true;
    var allCoreValid = true;
    for (final pt in corePoints) {
      final p = project(pt);
      if (p == null) {
        allCoreValid = false;
        break;
      }
      if (coreFirst) {
        corePath.moveTo(p.dx, p.dy);
        coreFirst = false;
      } else {
        corePath.lineTo(p.dx, p.dy);
      }
    }
    if (allCoreValid && !coreFirst) {
      corePath.close();
      final corePaint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, coreAlpha)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(corePath, corePaint);
    }

    // 3. Four Steered Dark Tire Contact Footprints (Tire Patches)
    final tirePatchPaint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, isDay ? 0.85 : 0.95)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final corners = const ['FL', 'FR', 'RL', 'RR'];
    final defaultPos = [
      const Vec3(-0.95, 0.35, -1.25),
      const Vec3(0.95, 0.35, -1.25),
      const Vec3(-0.95, 0.35, 1.25),
      const Vec3(0.95, 0.35, 1.25),
    ];

    for (var i = 0; i < 4; i++) {
      final corner = corners[i];
      final w = wheels[corner];
      final isFront = corner.startsWith('F');

      double localX;
      double localZ;
      double radius;
      double tireW;

      if (w != null) {
        if (model != null) {
          final mbb = model!.worldBBox;
          localX = w.worldPosition.x - mbb.center.x;
          localZ = w.worldPosition.z - mbb.center.z;
        } else {
          localX = w.worldPosition.x;
          localZ = w.worldPosition.z;
        }
        radius = w.radius.clamp(0.20, 0.55);
        tireW = w.width.clamp(0.15, 0.45);
      } else {
        final def = defaultPos[i];
        localX = def.x;
        localZ = def.z;
        radius = 0.35;
        tireW = 0.26;
      }

      final steer = isFront
          ? (sim.frontSteering ? sim.steerAngle : 0.0)
          : (sim.rearSteering ? -sim.steerAngle * 0.5 : 0.0);
      final wheelYaw = sim.yaw + steer;
      final tireFwd = Vec3(-sin(wheelYaw), 0.0, -cos(wheelYaw));
      final tireRight = Vec3(cos(wheelYaw), 0.0, -sin(wheelYaw));

      final tireCenter = groundPos + (right * localX) - (fwd * localZ) + const Vec3(0.0, 0.001, 0.0);
      final patchL = radius * 0.55;
      final hw = tireW * 0.5;
      final hl = patchL * 0.5;

      final p0 = project(tireCenter - (tireRight * hw) - (tireFwd * hl));
      final p1 = project(tireCenter + (tireRight * hw) - (tireFwd * hl));
      final p2 = project(tireCenter + (tireRight * hw) + (tireFwd * hl));
      final p3 = project(tireCenter - (tireRight * hw) + (tireFwd * hl));

      if (p0 != null && p1 != null && p2 != null && p3 != null) {
        final patchPath = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close();
        canvas.drawPath(patchPath, tirePatchPaint);
      }
    }
  }

  void _drawModelGeometry(
    Canvas canvas,
    Mat4 vehicleMatrix,
    Offset? Function(Vec3) project,
    Map<String, DetectedWheel> wheels,
  ) {
    final modelCenter = model!.worldBBox.center;
    final lowestTireY = wheels.isNotEmpty
        ? wheels.values.map((w) => w.worldPosition.y - w.radius).reduce(min)
        : model!.worldBBox.lo.y;
    final alignOffset = Vec3(-modelCenter.x, -lowestTireY, -modelCenter.z);

    final alignMatrix = Mat4([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      alignOffset.x, alignOffset.y, alignOffset.z, 1,
    ]);
    final carModelMatrix = vehicleMatrix * alignMatrix;

    final worldMatrices = List<Mat4>.filled(9, carModelMatrix);

    final nonWheelNodes = <int>{};
    if (detection?.body != null) {
      nonWheelNodes.add(detection!.body!.nodeIndex);
    }
    final carBox = model!.worldBBox;
    final carLen = max(carBox.size.z.abs(), carBox.size.x.abs());
    final carW = min(carBox.size.z.abs(), carBox.size.x.abs());
    final carH = carBox.size.y.abs();
    for (final inst in model!.instances) {
      final s = inst.worldBBox.size;
      final maxDim = max(s.x.abs(), max(s.y.abs(), s.z.abs()));
      if (s.z.abs() > carLen * 0.45 ||
          s.x.abs() > carW * 0.48 ||
          s.y.abs() > carH * 0.70 ||
          maxDim > carLen * 0.45) {
        nonWheelNodes.add(inst.nodeIndex);
      }
    }
    final sharedOrBodyNodes = <int>{
      if (detection?.body != null) detection!.body!.nodeIndex,
    };
    for (final inst in model!.instances) {
      final s = inst.worldBBox.size;
      if (max(s.x.abs(), s.z.abs()) > carLen * 0.42) {
        sharedOrBodyNodes.add(inst.nodeIndex);
      }
    }
    for (final w in wheels.values) {
      for (final n in [
        ...w.partNodeIndices,
        ...w.spinNodeIndices,
        ...w.caliperHubNodeIndices,
        w.nodeIndex
      ]) {
        if (!sharedOrBodyNodes.contains(n)) {
          nonWheelNodes.remove(n);
        }
      }
    }

    final nodeToTransform = <int, int>{};
    const corners = ['FL', 'FR', 'RL', 'RR'];

    void assignWireTransform(int nodeIdx, int transformIdx) {
      if (nonWheelNodes.contains(nodeIdx)) return;
      nodeToTransform[nodeIdx] = transformIdx;
    }

    for (var c = 0; c < 4; c++) {
      final corner = corners[c];
      final w = wheels[corner];
      if (w == null) continue;

      final spinIdx = c;
      final calIdx = c + 4;

      final isFront = corner.startsWith('F') || w.axle == 'front';
      final steer = isFront
          ? (sim.frontSteering ? sim.steerAngle : 0.0)
          : (sim.rearSteering ? -sim.steerAngle * 0.5 : 0.0);
      final r = w.radius > 0.05 ? w.radius : 0.34;
      final roll = -sim.wheelRoll / r;
      final hub = w.worldPosition;

      final spinLocalMat = _buildWheelLocalMatrix(hub, alignOffset, steer, roll);
      worldMatrices[spinIdx] = vehicleMatrix * spinLocalMat;

      final calLocalMat = _buildWheelLocalMatrix(hub, alignOffset, steer, 0.0);
      worldMatrices[calIdx] = vehicleMatrix * calLocalMat;

      if (w.spinNodeIndices.isNotEmpty || w.caliperHubNodeIndices.isNotEmpty) {
        for (final n in w.spinNodeIndices) {
          assignWireTransform(n, spinIdx);
        }
        for (final n in w.caliperHubNodeIndices) {
          assignWireTransform(n, calIdx);
        }
      } else if (w.partNodeIndices.isNotEmpty) {
        for (final n in w.partNodeIndices) {
          assignWireTransform(n, spinIdx);
        }
      } else if (!nonWheelNodes.contains(w.nodeIndex)) {
        assignWireTransform(w.nodeIndex, spinIdx);
      }
    }

    final wirePaint = Paint()
      ..color = const Color(0xFF64B5F6)
      ..strokeWidth = 1.0;

    for (final inst in model!.instances) {
      final verts = inst.worldVertices;
      final edges = inst.edges;
      final k = nodeToTransform[inst.nodeIndex] ?? 8;
      final transMat = worldMatrices[k];

      final step = (edges.length > 2500) ? (edges.length ~/ 2500) : 1;

      for (var i = 0; i < edges.length; i += step) {
        final e = edges[i];
        if (e.a < verts.length && e.b < verts.length) {
          final v0 = verts[e.a];
          final v1 = verts[e.b];

          final world0 = transMat.transformPoint(v0);
          final world1 = transMat.transformPoint(v1);

          final p0 = project(world0);
          final p1 = project(world1);
          if (p0 != null && p1 != null) {
            canvas.drawLine(p0, p1, wirePaint);
          }
        }
      }
    }
  }

  void _drawProceduralSportsCar(
    Canvas canvas,
    Mat4 vehicleMatrix,
    Offset? Function(Vec3) project,
    Map<String, DetectedWheel> wheels,
  ) {
    final bodyPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.2;

    // Body vertices in local car coordinates
    final bodyCorners = [
      // Bottom frame: FL, FR, RR, RL
      const Vec3(-0.95, 0.22, -1.9),
      const Vec3(0.95, 0.22, -1.9),
      const Vec3(0.95, 0.22, 1.9),
      const Vec3(-0.95, 0.22, 1.9),
      // Hood line
      const Vec3(-0.9, 0.68, -1.7),
      const Vec3(0.9, 0.68, -1.7),
      // Windshield base
      const Vec3(-0.85, 0.85, -0.6),
      const Vec3(0.85, 0.85, -0.6),
      // Roof top
      const Vec3(-0.68, 1.32, -0.2),
      const Vec3(0.68, 1.32, -0.2),
      const Vec3(-0.68, 1.32, 0.75),
      const Vec3(0.68, 1.32, 0.75),
      // Rear window base
      const Vec3(-0.85, 0.85, 1.3),
      const Vec3(0.85, 0.85, 1.3),
      // Trunk spoiler
      const Vec3(-0.9, 0.88, 1.85),
      const Vec3(0.9, 0.88, 1.85),
    ];

    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0], // Bottom chassis
      [0, 4], [1, 5], [4, 5], // Hood
      [4, 6], [5, 7], [6, 7], // Windshield lower
      [6, 8], [7, 9], [8, 9], // Windshield upper
      [8, 10], [9, 11], [10, 11], // Roof
      [10, 12], [11, 13], [12, 13], // Rear window
      [12, 14], [13, 15], [14, 15], // Trunk / spoiler
      [14, 3], [15, 2], // Rear bumper
    ];

    for (final e in edges) {
      final w0 = vehicleMatrix.transformPoint(bodyCorners[e[0]]);
      final w1 = vehicleMatrix.transformPoint(bodyCorners[e[1]]);
      final p0 = project(w0);
      final p1 = project(w1);
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, bodyPaint);
      }
    }

    // 4 Wheels
    final wheelCenters = [
      wheels['FL']?.worldPosition ?? const Vec3(-1.0, 0.36, -1.25),
      wheels['FR']?.worldPosition ?? const Vec3(1.0, 0.36, -1.25),
      wheels['RL']?.worldPosition ?? const Vec3(-1.0, 0.36, 1.25),
      wheels['RR']?.worldPosition ?? const Vec3(1.0, 0.36, 1.25),
    ];

    final wheelRadii = [
      wheels['FL']?.radius ?? 0.36,
      wheels['FR']?.radius ?? 0.36,
      wheels['RL']?.radius ?? 0.36,
      wheels['RR']?.radius ?? 0.36,
    ];

    for (var i = 0; i < wheelCenters.length; i++) {
      final isFront = i < 2;
      final wc = wheelCenters[i];
      final r = wheelRadii[i].clamp(0.20, 0.55);
      _drawDynamicWheel(
        canvas: canvas,
        vehicleMatrix: vehicleMatrix,
        project: project,
        localCenter: wc,
        radius: r,
        steerAngle: isFront
            ? (sim.frontSteering ? sim.steerAngle : 0.0)
            : (sim.rearSteering ? -sim.steerAngle * 0.5 : 0.0),
        rollAngle: -sim.wheelRoll / r,
      );
    }
  }

  void _drawDynamicWheel({
    required Canvas canvas,
    required Mat4 vehicleMatrix,
    required Offset? Function(Vec3) project,
    required Vec3 localCenter,
    required double radius,
    required double steerAngle,
    required double rollAngle,
  }) {
    final wheelPaint = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 1.4;
    final spokePaint = Paint()
      ..color = const Color(0x9934D399)
      ..strokeWidth = 1.0;

    // Steer rotation matrix around Y
    final cs = cos(steerAngle);
    final ss = sin(steerAngle);

    const segments = 12;
    for (var i = 0; i < segments; i++) {
      final a0 = rollAngle + (i * 2 * pi / segments);
      final a1 = rollAngle + ((i + 1) * 2 * pi / segments);

      // Unsteered rim point in wheel local space
      final ry0 = radius * cos(a0);
      final rz0 = radius * sin(a0);
      final ry1 = radius * cos(a1);
      final rz1 = radius * sin(a1);

      // Rotate rim points by steerAngle around Y
      final sx0 = rz0 * ss;
      final sz0 = rz0 * cs;
      final sx1 = rz1 * ss;
      final sz1 = rz1 * cs;

      final w0 = vehicleMatrix.transformPoint(
        Vec3(localCenter.x + sx0, localCenter.y + ry0, localCenter.z + sz0),
      );
      final w1 = vehicleMatrix.transformPoint(
        Vec3(localCenter.x + sx1, localCenter.y + ry1, localCenter.z + sz1),
      );

      final p0 = project(w0);
      final p1 = project(w1);
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, wheelPaint);
      }
    }

    // 5 Spokes from hub to rim
    final centerWorld = vehicleMatrix.transformPoint(localCenter);
    final pCenter = project(centerWorld);
    if (pCenter != null) {
      for (var s = 0; s < 5; s++) {
        final sa = rollAngle + (s * 2 * pi / 5);
        final sy = radius * sin(sa);
        final sz = radius * cos(sa);
        final sx = sz * ss;
        final szSteered = sz * cs;
        final wSpoke = vehicleMatrix.transformPoint(
          Vec3(localCenter.x + sx, localCenter.y + sy, localCenter.z + szSteered),
        );
        final pSpoke = project(wSpoke);
        if (pSpoke != null) {
          canvas.drawLine(pCenter, pSpoke, spokePaint);
        }
      }
    }
  }

  void _drawHeadlightBeams(
    Canvas canvas,
    Mat4 vehicleMatrix,
    Offset? Function(Vec3) project,
  ) {
    final beamPaint = Paint()
      ..color = const Color(0x3500E5FF)
      ..strokeWidth = 1.5;

    final leftLight = vehicleMatrix.transformPoint(const Vec3(-0.7, 0.45, -1.9));
    final leftTarget = vehicleMatrix.transformPoint(const Vec3(-1.4, 0.05, -9.0));

    final rightLight = vehicleMatrix.transformPoint(const Vec3(0.7, 0.45, -1.9));
    final rightTarget = vehicleMatrix.transformPoint(const Vec3(1.4, 0.05, -9.0));

    final pL0 = project(leftLight);
    final pL1 = project(leftTarget);
    if (pL0 != null && pL1 != null) canvas.drawLine(pL0, pL1, beamPaint);

    final pR0 = project(rightLight);
    final pR1 = project(rightTarget);
    if (pR0 != null && pR1 != null) canvas.drawLine(pR0, pR1, beamPaint);
  }

  @override
  bool shouldRepaint(covariant _TestDriveScenePainter oldDelegate) => true;
}
