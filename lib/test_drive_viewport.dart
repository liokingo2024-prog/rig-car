import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'fullscreen.dart';
import 'model_data.dart';
import 'physics_sim.dart';
import 'sketchfab_viewport.dart';

// ── Godot 4 Interactive Test Drive Viewport ─────────────────────────────────
//
// Full-screen real-time driving simulation with Godot 4 VehicleBody3D physics,
// spring chase camera, procedural track with slalom obstacles, tire skid marks,
// drift mechanics, and a glassmorphic cyber racing HUD.

enum CameraMode { chase, orbit, hood }

enum TestDriveRenderMode {
  solid('Solid', Icons.view_in_ar_rounded),
  wireframe('Wireframe', Icons.grid_4x4_rounded),
  hybrid('Hybrid', Icons.layers_rounded),
  webgl('WebGL PBR', Icons.auto_awesome_rounded);

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

typedef LivePhysicsUpdated = void Function({
  required double mass,
  required double engineForce,
  required double grip,
  required double springStiffness,
  required double dampingCompression,
  required String drive,
});

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
    this.onPhysicsUpdated,
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

  /// Syncs values tuned live in Test Drive back to the workbench on exit.
  final LivePhysicsUpdated? onPhysicsUpdated;

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
  TestDriveLighting _lighting = TestDriveLighting.sunset;
  TrackSurfaceStyle _trackStyle = TrackSurfaceStyle.circuit;
  final TestDriveRenderMode _renderMode = TestDriveRenderMode.webgl;
  Timer? _webglRetryTimer;
  double _orbitAzimuth = 0.65;
  double _orbitElevation = 0.32;
  double _orbitDistance = 7.2;

  // Angular spring-tethered chase camera state. The camera is stored relative
  // to the car in polar coordinates so it can never lag behind or cut the
  // chord of a corner at speed.
  double _camYaw = 0.0;
  double _camDist = 5.45;
  double _camHeight = 1.82;
  double _camLookAhead = 0.0;
  double _camSteerSwing = 0.0;
  double _camSlip = 0.0;
  double _camRoll = 0.0;
  double _fovDeg = 54.0;
  double _gearShiftKick = 0.0;
  int _lastGear = 1;
  double _chaseUserYaw = 0.0;
  double _chaseUserPitch = 0.0;
  double _timeSinceChaseDrag = 10.0;
  bool _showTouchControls = false;

  Vec3 _chaseCamPos = const Vec3(0, 1.82, 30.0);
  Vec3 _chaseCamTarget = const Vec3(0, 0.72, 21.6);

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

  // Live tuning & performance telemetry
  bool _showLiveTuning = false;
  bool _webglActive = kIsWeb;
  double _best0to100 = 0.0;
  double _topSpeedKmh = 0.0;
  double _accelRunTime = 0.0;
  bool _accelRunActive = false;
  bool _accelRunDone = false;
  int _slalomGates = 0;
  final Set<int> _passedCones = {};

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
    _camYaw = _sim.yaw;
    _camDist = 5.45;
    _camHeight = 1.82;
    _chaseCamPos = _sim.position + const Vec3(0, 1.82, 5.45);
    _chaseCamTarget = _sim.position + const Vec3(0, 0.72, -2.6);

    if (kIsWeb) {
      _webglActive = true;
      enterSketchfabTestDrive();
      setSketchfabTestDriveWorld(_lighting.name, _trackStyle.name);
      _pushWebglState();
    }

    _ticker = createTicker(_onTick)..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
      _syncWebglMode();
    });
  }

  @override
  void dispose() {
    _webglRetryTimer?.cancel();
    _webglRetryTimer = null;
    if (_webglActive) exitSketchfabTestDrive();
    _notifyPhysicsUpdated();
    updateSketchfabSkidAudio(false, false);
    stopSketchfabSkidAudio();
    stopSketchfabEngineAudio();
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      if (_webglActive) _pushWebglState();
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

    _updatePerformanceTelemetry(dt, throttle);
    updateSketchfabSkidAudio(_sim.isDrifting, widget.tireSkidAudioEnabled);
    updateSketchfabEngineAudio(
      _sim.engineRpm,
      throttle,
      widget.soundProfile,
      widget.sirenEnabled,
    );

    // Update chase camera
    _updateChaseCamera(dt);
    if (_webglActive) _pushWebglState();

    // Update UI pulse
    _uiPulse = (_uiPulse + dt * 3.0) % (2 * pi);

    setState(() {});
  }

  static double _wrapAngle(double a) {
    while (a > pi) {
      a -= 2 * pi;
    }
    while (a < -pi) {
      a += 2 * pi;
    }
    return a;
  }

  void _updatePerformanceTelemetry(double dt, double throttle) {
    if (_sim.speedKmh > _topSpeedKmh) _topSpeedKmh = _sim.speedKmh;

    // Reset 0-100 run when parked or stopped at idle
    if (_sim.speedKmh < 1.2 && throttle <= 0.05) {
      _accelRunActive = false;
      _accelRunTime = 0.0;
      _accelRunDone = false;
    }

    // 0-100 km/h: arm from a standstill on throttle, capture the best run.
    if (!_accelRunActive && !_accelRunDone && throttle > 0.1 && _sim.speedKmh < 1.0) {
      _accelRunActive = true;
      _accelRunTime = 0.0;
    }
    if (_accelRunActive) {
      _accelRunTime += dt;
      if (_accelRunTime > 45.0) {
        _accelRunActive = false;
        _accelRunTime = 0.0;
      } else if (_sim.speedKmh >= 100.0) {
        _accelRunActive = false;
        _accelRunDone = true;
        if (_best0to100 <= 0 || _accelRunTime < _best0to100) {
          _best0to100 = _accelRunTime;
        }
      }
    }

    // Slalom gates: count each course cone as it passes under the car.
    for (var i = 0; i < _sim.cones.length; i++) {
      if (_passedCones.contains(i)) continue;
      final c = _sim.cones[i].position;
      final dx = _sim.position.x - c.x;
      final dz = _sim.position.z - c.z;
      if (dx * dx + dz * dz < 16.0) {
        _passedCones.add(i);
        _slalomGates++;
      }
    }
  }

  /// Hands the physics state to the live Three.js scene for WebGL Test Drive.
  void _pushWebglState() {
    final (eye, target) = _testDriveEyeTarget();
    final r = _sim.wheelSuspensionCompressions;
    final flR = widget.assignedWheels['FL']?.radius ?? 0.34;
    final effR = flR > 0.05 ? flR : 0.34;
    updateSketchfabTestDriveState(
      x: _sim.position.x,
      y: _sim.position.y,
      z: _sim.position.z,
      yaw: _sim.yaw,
      pitch: _sim.pitch,
      roll: _sim.roll,
      steerAngle: _sim.frontSteering ? _sim.steerAngle : 0.0,
      rearSteerAngle: _sim.rearSteering ? -_sim.steerAngle * 0.5 : 0.0,
      wheelRollRad: -_sim.wheelRoll / effR,
      compressions: r,
      camX: eye.x,
      camY: eye.y,
      camZ: eye.z,
      targetX: target.x,
      targetY: target.y,
      targetZ: target.z,
      fovDeg: _fovDeg,
      camRoll: _camRoll,
    );
  }

  (Vec3, Vec3) _testDriveEyeTarget() {
    switch (_cameraMode) {
      case CameraMode.chase:
        return (_chaseCamPos, _chaseCamTarget);
      case CameraMode.hood:
        final fwd =
            Vec3(-sin(_sim.yaw), -sin(_sim.pitch) * 0.65, -cos(_sim.yaw))
                .normalized;
        final right = Vec3(cos(_sim.yaw), 0, -sin(_sim.yaw));
        final eye = _sim.position + (fwd * 0.55) + const Vec3(0, 1.02, 0);
        final target = eye + (fwd * 14.0) - (right * (_sim.steerAngle * 2.8));
        return (eye, target);
      case CameraMode.orbit:
        final totalAz = _sim.yaw + _orbitAzimuth;
        final target = _sim.position + const Vec3(0, 0.68, 0);
        final eye = Vec3(
          target.x + _orbitDistance * cos(_orbitElevation) * sin(totalAz),
          target.y + _orbitDistance * sin(_orbitElevation),
          target.z + _orbitDistance * cos(_orbitElevation) * cos(totalAz),
        );
        return (eye, target);
    }
  }

  int _webglRetries = 0;

  /// Enters/leaves the Three.js drivable mode as the render mode changes.
  /// Falls back to the CPU solid renderer when the JS scene is unavailable.
  void _syncWebglMode() {
    if (!mounted || !kIsWeb) return;
    if (enterSketchfabTestDrive()) {
      _webglActive = true;
      setSketchfabTestDriveWorld(_lighting.name, _trackStyle.name);
      _pushWebglState();
      return;
    }
    if (_webglRetries < 12) {
      _webglRetries++;
      _webglRetryTimer?.cancel();
      _webglRetryTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _renderMode == TestDriveRenderMode.webgl) {
          _syncWebglMode();
        }
      });
    }
  }

  void _notifyPhysicsUpdated() {
    widget.onPhysicsUpdated?.call(
      mass: _sim.mass,
      engineForce: _sim.engineForce,
      grip: _sim.grip,
      springStiffness: _sim.springStiffness,
      dampingCompression: _sim.dampingCompression,
      drive: _sim.drive,
    );
  }

  void _updateChaseCamera(double dt) {
    _timeSinceChaseDrag += dt;
    if (_timeSinceChaseDrag > 1.1) {
      final recenter = (dt * 4.5).clamp(0.0, 1.0);
      _chaseUserYaw += (0.0 - _chaseUserYaw) * recenter;
      _chaseUserPitch += (0.0 - _chaseUserPitch) * recenter;
    }

    // Detect upshift impulse under throttle
    if (_sim.currentGear > _lastGear &&
        _sim.currentGear > 1 &&
        _sim.longitudinalG > -0.05) {
      _gearShiftKick = 1.0;
    }
    _lastGear = _sim.currentGear;
    _gearShiftKick *= exp(-dt * 6.5);

    var targetYaw = _sim.yaw;
    var slipDiff = 0.0;
    final horizSpeed = sqrt(
      _sim.velocity.x * _sim.velocity.x + _sim.velocity.z * _sim.velocity.z,
    );
    if (horizSpeed > 1.8) {
      final velYaw = atan2(-_sim.velocity.x, -_sim.velocity.z);
      slipDiff = _wrapAngle(velYaw - _sim.yaw);
      final blend = _sim.isDrifting ? 0.52 : 0.22;
      targetYaw = _sim.yaw + slipDiff * blend;
    }

    final speedNorm = (_sim.speedKmh / 180.0).clamp(0.0, 1.0);
    final yawFollowRate =
        1.0 - exp(-dt * (6.2 + (_sim.speedKmh / 65.0).clamp(0.0, 6.5)));
    _camYaw = _wrapAngle(_camYaw + _wrapAngle(targetYaw - _camYaw) * yawFollowRate);

    final effectiveYaw = _camYaw + _chaseUserYaw;
    final camFwd = Vec3(-sin(effectiveYaw), 0, -cos(effectiveYaw));
    final camRight = Vec3(cos(effectiveYaw), 0, -sin(effectiveYaw));
    const up = Vec3(0, 1, 0);

    final pitchClamped = _chaseUserPitch.clamp(-0.22, 0.62);
    final smooth = 1.0 - exp(-dt * 10.0);

    // Weight-transfer distance & height
    final accelPull =
        (_sim.longitudinalG * 0.45).clamp(-0.42, 0.60) + (_gearShiftKick * 0.30);
    final targetDist = (5.45 + speedNorm * 1.25 + accelPull) * cos(pitchClamped);
    final targetHeight =
        (1.82 + speedNorm * 0.30 - (_sim.pitch * 1.1)) + 4.8 * sin(pitchClamped);

    _camDist += (targetDist - _camDist) * smooth;
    _camHeight += (targetHeight - _camHeight) * smooth;

    // Dynamic FOV warp (54° -> 76°)
    final speedCurve = pow(speedNorm, 1.12).toDouble();
    final targetFov = (54.0 +
            speedCurve * 17.5 +
            (_sim.longitudinalG * 3.8).clamp(-3.0, 4.5) +
            _gearShiftKick * 2.4)
        .clamp(50.0, 76.0);
    _fovDeg += (targetFov - _fovDeg) * (1.0 - exp(-dt * 8.5));

    // Steering apex look-ahead + outer camera swing
    final targetLookAhead =
        (-_sim.steerAngle * (1.95 + speedNorm * 0.45)).clamp(-1.6, 1.6);
    _camLookAhead += (targetLookAhead - _camLookAhead) * (1.0 - exp(-dt * 9.0));

    final targetSteerSwing =
        (_sim.steerAngle * (0.48 + speedNorm * 0.30)).clamp(-0.65, 0.65);
    _camSteerSwing += (targetSteerSwing - _camSteerSwing) * (1.0 - exp(-dt * 8.0));

    final targetSlip = (slipDiff * (_sim.isDrifting ? 1.55 : 0.45)).clamp(-1.35, 1.35);
    _camSlip += (targetSlip - _camSlip) * (1.0 - exp(-dt * 5.5));

    // Horizon corner banking
    final targetRoll =
        (-_sim.steerAngle * 0.085 + _sim.lateralG * 0.028 + _sim.roll * 0.40)
            .clamp(-0.14, 0.14);
    _camRoll += (targetRoll - _camRoll) * (1.0 - exp(-dt * 7.5));

    final vibAmp = ((_sim.speedKmh - 65.0) / 140.0).clamp(0.0, 1.0) * 0.014;
    final shakeY = cos(_uiPulse * 27.0) * vibAmp;

    final camPos = _sim.position -
        (camFwd * _camDist) +
        (camRight * (_camSlip + _camSteerSwing)) +
        (up * (_camHeight + shakeY).clamp(0.55, 5.5));
    _chaseCamPos = Vec3(camPos.x, max(camPos.y, 0.62), camPos.z);
    _chaseCamTarget = _sim.position +
        (camFwd * (2.6 + speedNorm * 1.1)) +
        (camRight * (_camLookAhead + _camSlip * 0.35)) +
        (up * (0.72 + shakeY * 0.5));
  }

  void _resetCar() {
    _sim.reset();
    _camYaw = _sim.yaw;
    _camDist = 5.45;
    _camHeight = 1.82;
    _camLookAhead = 0.0;
    _camSteerSwing = 0.0;
    _camSlip = 0.0;
    _camRoll = 0.0;
    _gearShiftKick = 0.0;
    _lastGear = 1;
    _accelRunActive = false;
    _accelRunDone = false;
    _accelRunTime = 0.0;
    _topSpeedKmh = 0.0;
    _slalomGates = 0;
    _passedCones.clear();
    _chaseUserYaw = 0.0;
    _chaseUserPitch = 0.0;
    _timeSinceChaseDrag = 10.0;
    _chaseCamPos = _sim.position + const Vec3(0, 1.82, 5.45);
    _chaseCamTarget = _sim.position + const Vec3(0, 0.72, -2.6);
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
          setState(() {
            if (_cameraMode == CameraMode.orbit) {
              _orbitAzimuth -= details.delta.dx * 0.008;
              _orbitElevation = (_orbitElevation + details.delta.dy * 0.008)
                  .clamp(0.05, 1.4);
            } else if (_cameraMode == CameraMode.chase) {
              _timeSinceChaseDrag = 0.0;
              _chaseUserYaw -= details.delta.dx * 0.007;
              _chaseUserPitch =
                  (_chaseUserPitch + details.delta.dy * 0.006).clamp(-0.20, 0.60);
            }
          });
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && _cameraMode == CameraMode.orbit) {
              setState(() {
                _orbitDistance = (_orbitDistance + event.scrollDelta.dy * 0.012)
                    .clamp(3.2, 18.0);
              });
            }
          },
          child: Stack(
            children: [
              // Hardware-accelerated Three.js canvas (WebGL PBR mode)
              if (_renderMode == TestDriveRenderMode.webgl)
                Positioned.fill(
                  child: SketchfabViewport(
                    attachOnly: true,
                    renderMode: 'webgl',
                    lighting: switch (_lighting) {
                      TestDriveLighting.day => 'daylight',
                      TestDriveLighting.sunset => 'sunset',
                      TestDriveLighting.night => 'night',
                    },
                    gridStyle: 'off',
                    showForwardArrow: false,
                    autoTurntable: false,
                    cameraPreset: 'iso',
                  ),
                ),

              // 3D Canvas
              Positioned.fill(
                child:                  CustomPaint(
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
                    cameraRoll: _camRoll,
                    overlayOnly: true,
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

              // Live in-drive tuning drawer
              if (_showLiveTuning)
                Positioned(
                  top: 72,
                  right: 16,
                  child: _buildLiveTuningPanel(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xB80B120E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2D23)),
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
                      if (constraints.maxWidth >= 940) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x661A231E),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: const Text(
                            'WASD: Drive · SPACE: Drift · C: Cam · R: Reset',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF86978C),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
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

                  // Right Cluster: Camera, Surface, Lighting, Fullscreen, Reset
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        onSelected: (style) {
                          setState(() => _trackStyle = style);
                          if (_webglActive) {
                            setSketchfabTestDriveWorld(
                              _lighting.name,
                              style.name,
                            );
                          }
                        },
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
                        onSelected: (l) {
                          setState(() => _lighting = l);
                          if (_webglActive) {
                            setSketchfabTestDriveWorld(
                              l.name,
                              _trackStyle.name,
                            );
                          }
                        },
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

                      // Live tuning drawer toggle
                      InkWell(
                        onTap: () =>
                            setState(() => _showLiveTuning = !_showLiveTuning),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: _showLiveTuning
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _showLiveTuning
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF223127),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 14,
                                color: _showLiveTuning
                                    ? const Color(0xFF041D14)
                                    : const Color(0xFFC9D1D9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'TUNE',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _showLiveTuning
                                      ? const Color(0xFF041D14)
                                      : const Color(0xFFC9D1D9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Touch controls toggle button
                      InkWell(
                        onTap: () => setState(() => _showTouchControls = !_showTouchControls),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: _showTouchControls
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _showTouchControls
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF223127),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sports_esports,
                                size: 14,
                                color: _showTouchControls
                                    ? const Color(0xFF041D14)
                                    : const Color(0xFFC9D1D9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'PADS',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _showTouchControls
                                      ? const Color(0xFF041D14)
                                      : const Color(0xFFC9D1D9),
                                ),
                              ),
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

  Widget _buildLiveTuningPanel() {
    return Container(
      width: 268,
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: const Color(0xF2111714),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF27392F)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 14, color: Color(0xFF34D399)),
                const SizedBox(width: 6),
                const Text(
                  'LIVE TUNING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF0FDF4),
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showLiveTuning = false),
                  child: const Icon(Icons.close,
                      size: 15, color: Color(0xFF86978C)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildTuningSlider(
              'MASS',
              _sim.mass,
              700,
              2200,
              30,
              'kg',
              (v) => setState(() => _sim.mass = v),
            ),
            _buildTuningSlider(
              'ENGINE FORCE',
              _sim.engineForce,
              150,
              1200,
              35,
              'N',
              (v) => setState(() => _sim.engineForce = v),
            ),
            _buildTuningSlider(
              'TIRE GRIP',
              _sim.grip,
              0.6,
              1.8,
              24,
              'g',
              (v) => setState(() => _sim.grip = v),
            ),
            _buildTuningSlider(
              'SPRING STIFFNESS',
              _sim.springStiffness,
              15,
              90,
              30,
              'N/m',
              (v) => setState(() => _sim.springStiffness = v),
            ),
            _buildTuningSlider(
              'DAMPING',
              _sim.dampingCompression,
              0.5,
              6.0,
              22,
              '',
              (v) => setState(() => _sim.dampingCompression = v),
            ),
            const SizedBox(height: 6),
            const Text(
              'DRIVETRAIN',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF86978C),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final d in const ['AWD', 'RWD', 'FWD'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() {
                        _sim.drive = d;
                        _sim.frontTraction = d != 'RWD';
                        _sim.rearTraction = d != 'FWD';
                      }),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _sim.drive == d
                              ? const Color(0xFF10B981)
                              : const Color(0xFF1A231E),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _sim.drive == d
                                ? const Color(0xFF34D399)
                                : const Color(0xFF223127),
                          ),
                        ),
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _sim.drive == d
                                ? const Color(0xFF041D14)
                                : const Color(0xFFC9D1D9),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF223127), height: 1),
            const SizedBox(height: 10),
            Text(
              '0-100 km/h   ${_best0to100 > 0 ? '${_best0to100.toStringAsFixed(2)}s' : '--'}\n'
              'TOP SPEED    ${_topSpeedKmh.toStringAsFixed(0)} km/h\n'
              'SLALOM GATES ${_slalomGates.toString()}',
              style: const TextStyle(
                fontSize: 10,
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: Color(0xFF86978C),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTuningSlider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    String unit,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              Text(
                '${value.toStringAsFixed(value < 10 ? 2 : 0)}$unit',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF34D399),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFF10B981),
              inactiveTrackColor: const Color(0xFF223127),
              thumbColor: const Color(0xFF34D399),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomHud() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showTouch = _showTouchControls || constraints.maxWidth < 860;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left HUD: (Optional touch steering) + Vehicle Telemetry Pill
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showTouch) ...[
                      _buildTouchSteeringCluster(),
                      const SizedBox(width: 8),
                    ],
                    _buildVehicleTelemetryCluster(),
                  ],
                ),

                const SizedBox(width: 8),

                // Right HUD: Drift, Speedometer & (Optional touch pedals)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_sim.isDrifting) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xE010B981),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x6610B981),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department,
                                color: Color(0xFF041D14), size: 14),
                            SizedBox(width: 4),
                            Text(
                              'DRIFT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF041D14),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildSpeedometerCluster(),
                    if (showTouch) ...[
                      const SizedBox(width: 8),
                      _buildTouchPedalCluster(),
                    ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xB80B120E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2D23)),
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
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              CustomPaint(
                size: const Size(38, 38),
                painter: _GMeterPainter(
                  latG: _sim.lateralG,
                  longG: _sim.longitudinalG,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_sim.lateralG.abs().toStringAsFixed(2)}G',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF0FDF4),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),
          Container(width: 1, height: 42, color: const Color(0xFF1E2D23)),
          const SizedBox(width: 10),

          // 4-Wheel Slip & Suspension Telemetry
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TIRE SLIP & SUSPENSION',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildWheelBar('FL', _sim.wheelSlips[0],
                      _sim.wheelSuspensionCompressions[0]),
                  const SizedBox(width: 6),
                  _buildWheelBar('FR', _sim.wheelSlips[1],
                      _sim.wheelSuspensionCompressions[1]),
                  const SizedBox(width: 8),
                  _buildWheelBar('RL', _sim.wheelSlips[2],
                      _sim.wheelSuspensionCompressions[2]),
                  const SizedBox(width: 6),
                  _buildWheelBar('RR', _sim.wheelSlips[3],
                      _sim.wheelSuspensionCompressions[3]),
                ],
              ),
            ],
          ),

          const SizedBox(width: 10),
          Container(width: 1, height: 42, color: const Color(0xFF1E2D23)),
          const SizedBox(width: 8),

          // Drag-strip performance telemetry
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PERFORMANCE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              _buildPerfRow(
                '0-100',
                _best0to100 > 0
                    ? '${_best0to100.toStringAsFixed(2)}s'
                    : (_accelRunActive
                        ? '${_accelRunTime.toStringAsFixed(2)}s'
                        : '--'),
                _accelRunActive ? const Color(0xFFFDE047) : const Color(0xFFF0FDF4),
              ),
              _buildPerfRow(
                'V-MAX',
                '${_topSpeedKmh.toStringAsFixed(0)} km/h',
                const Color(0xFFF0FDF4),
              ),
              _buildPerfRow(
                'GATES',
                '$_slalomGates',
                const Color(0xFF34D399),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerfRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF86978C),
                letterSpacing: 0.4,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontFamily: 'monospace',
            ),
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
            fontSize: 7.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF86978C),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 9,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF1A231E),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 9,
            height: (slip.clamp(0.05, 1.0)) * 22,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(slip * 100).toInt()}%',
          style: TextStyle(
            fontSize: 6.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xB80B120E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2D23)),
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
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF0FDF4),
                  letterSpacing: -1.0,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'KM/H',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF86978C),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 12),

              // Gear badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A231E),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: const Color(0xFF223127),
                  ),
                ),
                child: Text(
                  gearStr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _sim.currentGear == -1
                        ? const Color(0xFFF85149)
                        : const Color(0xFFF0FDF4),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // RPM Tachometer Bar
          SizedBox(
            width: 152,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_sim.engineRpm.toInt()} RPM',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF86978C),
                      ),
                    ),
                    const Text(
                      'REDLINE 7.5K',
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF5252),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_sim.engineRpm / 7800.0).clamp(0.0, 1.0),
                    minHeight: 4,
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
    this.lighting = TestDriveLighting.sunset,
    this.trackStyle = TrackSurfaceStyle.circuit,
    this.renderMode = TestDriveRenderMode.webgl,
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
    this.cameraRoll = 0.0,
    this.overlayOnly = true,
  });

  final VehiclePhysicsSimulation sim;
  final CameraMode cameraMode;
  final double cameraRoll;
  final bool overlayOnly;
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

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (sim.speedKmh > 68.0) {
      _drawSpeedLinesOverlay(canvas, size);
    }
  }

  void _drawSpeedLinesOverlay(Canvas canvas, Size size) {
    final speedFactor = ((sim.speedKmh - 68.0) / 130.0).clamp(0.0, 1.0);
    final alpha = (speedFactor * 0.28).clamp(0.0, 0.35);
    final linePaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, alpha)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final cy = size.height * 0.52;
    final rngSeed = (uiPulse * 12.0).toInt();
    for (var i = 0; i < 7; i++) {
      final hash = ((rngSeed + i * 17) % 100) / 100.0;
      final y = size.height * (0.15 + hash * 0.70);
      final len = 40.0 + speedFactor * 80.0 + hash * 30.0;
      final dy = (cy - y) * 0.15;

      // Left edge streak
      canvas.drawLine(Offset(0.0, y), Offset(len, y + dy), linePaint);
      // Right edge streak
      canvas.drawLine(
        Offset(size.width, y),
        Offset(size.width - len, y + dy),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TestDriveScenePainter oldDelegate) => true;
}
