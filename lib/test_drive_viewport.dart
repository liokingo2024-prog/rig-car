import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'model_data.dart';
import 'physics_sim.dart';

// ── Godot 4 Interactive Test Drive Viewport ─────────────────────────────────
//
// Full-screen real-time driving simulation with Godot 4 VehicleBody3D physics,
// spring chase camera, procedural track with slalom obstacles, tire skid marks,
// drift mechanics, and a glassmorphic cyber racing HUD.

enum CameraMode { chase, orbit, hood }

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
    this.onExit,
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
  final VoidCallback? onExit;

  @override
  State<TestDriveViewport> createState() => _TestDriveViewportState();
}

class _TestDriveViewportState extends State<TestDriveViewport>
    with SingleTickerProviderStateMixin {
  late final VehiclePhysicsSimulation _sim;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  CameraMode _cameraMode = CameraMode.chase;
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
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onExit?.call();
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
              _orbitElevation = (_orbitElevation - details.delta.dy * 0.008)
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
                  chaseCamPos: _chaseCamPos,
                  chaseCamTarget: _chaseCamTarget,
                  orbitAzimuth: _orbitAzimuth,
                  orbitElevation: _orbitElevation,
                  orbitDistance: _orbitDistance,
                  model: widget.model,
                  accentColor: widget.accentColor,
                  uiPulse: _uiPulse,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF0111714),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                              horizontal: 10, vertical: 6),
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
                              SizedBox(width: 6),
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
                      const SizedBox(width: 14),

                      // Godot Engine title & status
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'GODOT 4 VEHICLE SIMULATOR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF0FDF4),
                          letterSpacing: 0.8,
                        ),
                      ),
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
                          '${_sim.drive} • ${_sim.mass.toInt()}KG • ${_sim.engineForce.toInt()}HP',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF86978C),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  // Right Cluster: Camera & Reset
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Camera selector
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: CameraMode.values.map((mode) {
                          final isSel = _cameraMode == mode;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: InkWell(
                              onTap: () => setState(() => _cameraMode = mode),
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
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
                                    fontSize: 10,
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

                      const SizedBox(width: 12),

                      // Reset button
                      InkWell(
                        onTap: _resetCar,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
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
                              SizedBox(width: 5),
                              Text(
                                'RESET (R)',
                                style: TextStyle(
                                  fontSize: 11,
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
            'WASD / ARROWS: Drive  •  SPACE: Handbrake  •  C: Camera  •  R: Reset  •  ESC: Exit',
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
            width: 170,
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
    required this.chaseCamPos,
    required this.chaseCamTarget,
    required this.orbitAzimuth,
    required this.orbitElevation,
    required this.orbitDistance,
    required this.model,
    required this.accentColor,
    required this.uiPulse,
  });

  final VehiclePhysicsSimulation sim;
  final CameraMode cameraMode;
  final Vec3 chaseCamPos;
  final Vec3 chaseCamTarget;
  final double orbitAzimuth;
  final double orbitElevation;
  final double orbitDistance;
  final ParsedModel? model;
  final Color accentColor;
  final double uiPulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Background sky gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A1016), Color(0xFF05080B)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

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

    // 2. Draw Asphalt Runway & Grid
    _drawTrack(canvas, size, projectPoint);

    // 3. Draw Tire Skid Marks
    _drawSkidMarks(canvas, projectPoint);

    // 4. Draw Slalom Cones
    _drawCones(canvas, projectPoint);

    // 5. Draw Vehicle
    _drawVehicle(canvas, size, projectPoint);
  }

  void _drawTrack(
    Canvas canvas,
    Size size,
    Offset? Function(Vec3) project,
  ) {
    const groundY = 0.0;
    const trackZMin = -160.0;
    const trackZMax = 40.0;
    const trackWidth = 14.0;

    // Track boundary edges
    final boundaryPaint = Paint()
      ..color = const Color(0x5000E5FF)
      ..strokeWidth = 2.0;

    final bL0 = project(const Vec3(-trackWidth, groundY, trackZMin));
    final bL1 = project(const Vec3(-trackWidth, groundY, trackZMax));
    if (bL0 != null && bL1 != null) canvas.drawLine(bL0, bL1, boundaryPaint);

    final bR0 = project(const Vec3(trackWidth, groundY, trackZMin));
    final bR1 = project(const Vec3(trackWidth, groundY, trackZMax));
    if (bR0 != null && bR1 != null) canvas.drawLine(bR0, bR1, boundaryPaint);

    // Grid crosslines every 5 meters
    final gridPaint = Paint()
      ..color = const Color(0x18455A64)
      ..strokeWidth = 1.0;

    for (var z = trackZMin; z <= trackZMax; z += 5.0) {
      final p0 = project(Vec3(-trackWidth, groundY, z));
      final p1 = project(Vec3(trackWidth, groundY, z));
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, gridPaint);
      }
    }

    // Center Dashed Strip
    final centerPaint = Paint()
      ..color = const Color(0x60ECEFF1)
      ..strokeWidth = 2.0;

    for (var z = trackZMin; z <= trackZMax; z += 6.0) {
      final p0 = project(Vec3(0, groundY, z));
      final p1 = project(Vec3(0, groundY, z + 3.0));
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, centerPaint);
      }
    }

    // Start / Finish Line Checkered Grid at Z = 24
    final startP0 = project(const Vec3(-trackWidth, groundY, 24));
    final startP1 = project(const Vec3(trackWidth, groundY, 24));
    if (startP0 != null && startP1 != null) {
      final startPaint = Paint()
        ..color = const Color(0x90FFD600)
        ..strokeWidth = 3.5;
      canvas.drawLine(startP0, startP1, startPaint);
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

    if (model != null && model!.instances.isNotEmpty) {
      _drawModelGeometry(canvas, vehicleMatrix, project);
    } else {
      _drawProceduralSportsCar(canvas, vehicleMatrix, project);
    }

    // Draw headlight glow beams
    _drawHeadlightBeams(canvas, vehicleMatrix, project);
  }

  void _drawModelGeometry(
    Canvas canvas,
    Mat4 vehicleMatrix,
    Offset? Function(Vec3) project,
  ) {
    final modelCenter = model!.worldBBox.center;
    final modelBottom = model!.worldBBox.lo.y;

    final wirePaint = Paint()
      ..color = const Color(0xFF64B5F6)
      ..strokeWidth = 1.0;

    for (final inst in model!.instances) {
      final verts = inst.worldVertices;
      final edges = inst.edges;

      final step = (edges.length > 2500) ? (edges.length ~/ 2500) : 1;

      for (var i = 0; i < edges.length; i += step) {
        final e = edges[i];
        if (e.a < verts.length && e.b < verts.length) {
          // Normalize vertex relative to car center & bottom
          final v0 = verts[e.a];
          final v1 = verts[e.b];

          final local0 = Vec3(
            v0.x - modelCenter.x,
            v0.y - modelBottom + 0.15,
            v0.z - modelCenter.z,
          );
          final local1 = Vec3(
            v1.x - modelCenter.x,
            v1.y - modelBottom + 0.15,
            v1.z - modelCenter.z,
          );

          final world0 = vehicleMatrix.transformPoint(local0);
          final world1 = vehicleMatrix.transformPoint(local1);

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
      const Vec3(-1.0, 0.36, -1.25), // FL
      const Vec3(1.0, 0.36, -1.25),  // FR
      const Vec3(-1.0, 0.36, 1.25),  // RL
      const Vec3(1.0, 0.36, 1.25),   // RR
    ];

    for (var i = 0; i < wheelCenters.length; i++) {
      final isFront = i < 2;
      final wc = wheelCenters[i];
      _drawDynamicWheel(
        canvas: canvas,
        vehicleMatrix: vehicleMatrix,
        project: project,
        localCenter: wc,
        radius: 0.36,
        steerAngle: isFront ? sim.steerAngle : 0.0,
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
  }) {
    final wheelPaint = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 1.4;

    // Steer rotation matrix around Y
    final cs = cos(steerAngle);
    final ss = sin(steerAngle);

    const segments = 10;
    for (var i = 0; i < segments; i++) {
      final a0 = i * 2 * pi / segments;
      final a1 = (i + 1) * 2 * pi / segments;

      // Unsteered rim point in wheel local space
      final rx0 = 0.0;
      final ry0 = radius * sin(a0);
      final rz0 = radius * cos(a0);

      final rx1 = 0.0;
      final ry1 = radius * sin(a1);
      final rz1 = radius * cos(a1);

      // Rotate rim points by steerAngle
      final sx0 = rx0 * cs + rz0 * ss;
      final sz0 = -rx0 * ss + rz0 * cs;

      final sx1 = rx1 * cs + rz1 * ss;
      final sz1 = -rx1 * ss + rz1 * cs;

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
