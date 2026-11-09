import 'dart:math';

import 'model_data.dart';

// ── Real-Time Godot 4 VehicleBody3D Physics Simulation ─────────────────────
//
// Implements full vehicle dynamics: engine torque, multi-gear transmission,
// Ackermann steering, independent suspension spring deflection (pitch & roll),
// lateral tire slip (Pacejka-simplified), handbrake drift mechanics,
// and skid mark tracking on the test track.

class ConeObstacle {
  final Vec3 position;
  const ConeObstacle(this.position);
}

class SkidPoint {
  final Vec3 pos;
  final double alpha;
  const SkidPoint(this.pos, this.alpha);
}

class VehiclePhysicsSimulation {
  VehiclePhysicsSimulation({
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
    this.maxSteerAngleDegrees = 36.0,
    this.springRestLength = 0.18,
    this.springStiffness = 42.0,
    this.dampingCompression = 2.4,
  }) {
    reset();
    _initTrackCones();
  }

  // Configuration from Workbench
  double mass;
  double engineForce;
  double grip;
  double suspension;
  double centerOfMass;
  String drive;
  bool frontSteering;
  bool rearSteering;
  bool frontTraction;
  bool rearTraction;
  List<Vec3> wheelPositions;
  double maxSteerAngleDegrees;
  double springRestLength;
  double springStiffness;
  double dampingCompression;

  // Vehicle State
  Vec3 position = Vec3.zero;
  Vec3 velocity = Vec3.zero;
  double yaw = 0.0; // Heading angle in radians (0 = facing -Z)
  double yawRate = 0.0; // Angular velocity (rad/s)
  double steerAngle = 0.0; // Current steering angle in radians
  double targetSteerAngle = 0.0;

  // Suspension deflection (visual tilt in radians)
  double pitch = 0.0; // Dive (braking) / Squat (accel)
  double roll = 0.0; // Lean during cornering

  // Drivetrain & Engine state
  int currentGear = 1;
  double engineRpm = 1000.0;
  double speedKmh = 0.0;
  bool isDrifting = false;
  double lateralG = 0.0;
  double longitudinalG = 0.0;

  // Wheel slip states [FL, FR, RL, RR] (0.0 = full grip, 1.0 = full slide)
  final List<double> wheelSlips = [0, 0, 0, 0];
  final List<double> wheelSuspensionCompressions = [0, 0, 0, 0];

  // Test Track Obstacles & Skid Trails
  final List<ConeObstacle> cones = [];
  final List<SkidPoint> leftSkidMarks = [];
  final List<SkidPoint> rightSkidMarks = [];
  static const int _maxSkidMarks = 180;

  void reset() {
    position = const Vec3(0, 0, 24); // Start at beginning of test strip
    velocity = Vec3.zero;
    yaw = 0.0;
    yawRate = 0.0;
    steerAngle = 0.0;
    targetSteerAngle = 0.0;
    pitch = 0.0;
    roll = 0.0;
    currentGear = 1;
    engineRpm = 950.0;
    speedKmh = 0.0;
    isDrifting = false;
    lateralG = 0.0;
    longitudinalG = 0.0;
    leftSkidMarks.clear();
    rightSkidMarks.clear();
    for (var i = 0; i < 4; i++) {
      wheelSlips[i] = 0.0;
      wheelSuspensionCompressions[i] = 0.0;
    }
  }

  void _initTrackCones() {
    cones.clear();
    // Slalom course along Z from Z = 15 to Z = -50
    for (var z = 12.0; z >= -48.0; z -= 10.0) {
      final offset = (z.toInt() % 20 == 0) ? -2.2 : 2.2;
      cones.add(ConeObstacle(Vec3(offset, 0, z)));
    }
    // Track boundary gates
    for (var z = 24.0; z >= -80.0; z -= 16.0) {
      cones.add(ConeObstacle(Vec3(-6.5, 0, z)));
      cones.add(ConeObstacle(Vec3(6.5, 0, z)));
    }
  }

  // ── Physics Step ──────────────────────────────────────────────────────────

  void step(double dt, {
    required double throttleInput, // -1.0 (brake/rev) to +1.0 (throttle)
    required double steerInput, // -1.0 (left) to +1.0 (right)
    required bool handbrake,
  }) {
    // 1. Steering smoothing with configured maximum steering angle
    final maxSteer = (maxSteerAngleDegrees * pi / 180.0).clamp(0.20, 0.95);
    targetSteerAngle = -steerInput * maxSteer;
    steerAngle += (targetSteerAngle - steerAngle) * (dt * 12.0).clamp(0.0, 1.0);

    // 2. Local direction vectors (Godot convention: -Z is forward, +X is right)
    final fwd = Vec3(-sin(yaw), 0, -cos(yaw));
    final right = Vec3(cos(yaw), 0, -sin(yaw));

    // 3. Local velocity decomposition
    final longSpeed = velocity.dot(fwd);
    final latSpeed = velocity.dot(right);
    speedKmh = (longSpeed * 3.6).abs();

    // 4. Transmission & Engine RPM model
    final gearRatios = [3.4, 2.1, 1.45, 1.1, 0.88, 0.72];
    if (longSpeed >= 0) {
      if (speedKmh > 140) {
        currentGear = 5;
      } else if (speedKmh > 100) {
        currentGear = 4;
      } else if (speedKmh > 65) {
        currentGear = 3;
      } else if (speedKmh > 32) {
        currentGear = 2;
      } else {
        currentGear = 1;
      }
      final ratio = gearRatios[(currentGear - 1).clamp(0, 5)];
      engineRpm = (1000 + (speedKmh * ratio * 38)).clamp(950.0, 7800.0);
    } else {
      currentGear = -1; // Reverse
      engineRpm = (1000 + (speedKmh * 3.5 * 38)).clamp(950.0, 5000.0);
    }

    // 5. Powertrain Forces
    var driveForce = 0.0;
    var brakeForce = 0.0;

    final gearRatio = (currentGear == -1)
        ? 3.5
        : gearRatios[(currentGear - 1).clamp(0, 5)];

    if (throttleInput > 0.05) {
      // Throttle applied with gear transmission leverage
      final torqueCurve = 1.0 - (engineRpm / 8500.0) * 0.25;
      driveForce = throttleInput * engineForce * gearRatio * 4.2 * torqueCurve;
    } else if (throttleInput < -0.05) {
      // If moving forward, pedal acts as brake; if stopped, acts as reverse
      if (longSpeed > 1.2) {
        brakeForce = (-throttleInput) * (mass * 9.81 * 1.05);
      } else {
        driveForce = throttleInput * engineForce * 9.0; // Reverse
      }
    }

    // Drivetrain power bias (FWD, RWD, AWD)
    var frontPower = 0.0;
    var rearPower = 0.0;
    if (drive == 'FWD') {
      frontPower = frontTraction ? 1.0 : 0.0;
    } else if (drive == 'RWD') {
      rearPower = rearTraction ? 1.0 : 0.0;
    } else {
      // AWD
      frontPower = frontTraction ? 0.5 : 0.0;
      rearPower = rearTraction ? 0.5 : 0.0;
    }

    final totalForwardThrust = (driveForce * (frontPower + rearPower)) -
        (brakeForce * (longSpeed >= 0 ? 1.0 : -1.0));

    // 6. Cornering & Lateral Grip (Tire Friction Model)
    final wheelbase = (wheelPositions.length >= 4)
        ? (wheelPositions[2].z - wheelPositions[0].z).abs().clamp(2.0, 4.0)
        : 2.7;

    // Ackermann yaw velocity target
    final targetYawRate = (longSpeed / wheelbase) * tan(steerAngle);
    final maxCorneringG = (grip * 1.1).clamp(0.4, 2.5);
    final maxLateralAccel = maxCorneringG * 9.81;

    // Check drift condition (handbrake or exceeding grip threshold)
    final gripFactor = handbrake ? 0.28 : grip;
    final isHandbrakeActive = handbrake;

    // Lateral slip calculation
    final theoreticalLatAccel = longSpeed * yawRate;
    lateralG = theoreticalLatAccel / 9.81;
    longitudinalG = (totalForwardThrust / mass) / 9.81;

    final lateralSlipMagnitude =
        (latSpeed.abs() + (isHandbrakeActive ? 3.0 : 0.0)) /
            (maxLateralAccel + 0.1);
    isDrifting = (lateralSlipMagnitude > 0.45 && speedKmh > 12) ||
        (isHandbrakeActive && speedKmh > 8);

    // Update individual wheel slip telemetry
    for (var i = 0; i < 4; i++) {
      final isRear = i >= 2;
      var slip = lateralSlipMagnitude * (isRear && isHandbrakeActive ? 2.5 : 1.0);
      if (brakeForce > 200) slip += 0.3;
      wheelSlips[i] = slip.clamp(0.0, 1.0);
    }

    // Yaw dynamics with drifting inertia
    final yawDamping = isDrifting ? 1.8 : 5.5;
    final yawTorque = (targetYawRate - yawRate) * (yawDamping * (gripFactor / 1.0));
    yawRate += yawTorque * dt;
    yaw += yawRate * dt;

    // 7. Resistance Forces (Aerodynamic Drag + Rolling Friction)
    const airDragCoeff = 0.38;
    final dragForce = 0.5 * airDragCoeff * 1.225 * (longSpeed * longSpeed.abs());
    const rollingResistance = 180.0;

    final totalNetLongForce = totalForwardThrust -
        dragForce -
        (rollingResistance * (longSpeed > 0 ? 1 : (longSpeed < 0 ? -1 : 0)));

    final longAccel = totalNetLongForce / mass;

    // Lateral force opposing slide
    final lateralResistanceForce =
        -latSpeed * mass * (gripFactor * (isDrifting ? 2.5 : 6.0));
    final latAccel = lateralResistanceForce / mass;

    // 8. Integrate Linear Velocity & Position
    final accelWorld = (fwd * longAccel) + (right * latAccel);
    velocity = velocity + (accelWorld * dt);

    // Stop complete jitter when stationary
    if (throttleInput.abs() < 0.05 && speedKmh < 0.8 && brakeForce > 10) {
      velocity = Vec3.zero;
    }

    position = position + (velocity * dt);

    // 9. Suspension Dynamics (Pitch under accel/brake, Roll during cornering)
    // Spring stiffness factor: higher stiffness = stiffer, less lean
    final effectiveStiffness = ((springStiffness / 10.0) * (suspension / 5.0)).clamp(1.5, 25.0);
    final targetPitch = (-longitudinalG * (centerOfMass.abs() + 0.25) / effectiveStiffness)
        .clamp(-0.25, 0.25);
    final targetRoll = (lateralG * (centerOfMass.abs() + 0.25) / effectiveStiffness)
        .clamp(-0.35, 0.35);

    final dampingRate = (dampingCompression * 3.5).clamp(4.0, 18.0);
    pitch += (targetPitch - pitch) * (dt * dampingRate);
    roll += (targetRoll - roll) * (dt * dampingRate);

    // Suspension compression per wheel
    wheelSuspensionCompressions[0] = (pitch - roll).clamp(-0.15, 0.15); // FL
    wheelSuspensionCompressions[1] = (pitch + roll).clamp(-0.15, 0.15); // FR
    wheelSuspensionCompressions[2] = (-pitch - roll).clamp(-0.15, 0.15); // RL
    wheelSuspensionCompressions[3] = (-pitch + roll).clamp(-0.15, 0.15); // RR

    // 10. Record Skid Marks when slipping
    if (isDrifting ||
        (brakeForce > 300 && speedKmh > 15) ||
        (isHandbrakeActive && speedKmh > 5)) {
      final slipAlpha = (lateralSlipMagnitude * 0.7 +
              (isHandbrakeActive ? 0.35 : 0.0))
          .clamp(0.25, 0.85);

      // Use actual rear wheel positions if available
      final rearLeftZ = wheelPositions.length >= 4 ? wheelPositions[2].z : -1.35;
      final rearRightZ = wheelPositions.length >= 4 ? wheelPositions[3].z : -1.35;
      final rearLeftX = wheelPositions.length >= 4 ? wheelPositions[2].x : -0.85;
      final rearRightX = wheelPositions.length >= 4 ? wheelPositions[3].x : 0.85;

      final rearL = position + (fwd * rearLeftZ) + (right * rearLeftX);
      final rearR = position + (fwd * rearRightZ) + (right * rearRightX);

      leftSkidMarks.add(SkidPoint(rearL, slipAlpha));
      rightSkidMarks.add(SkidPoint(rearR, slipAlpha));

      if (leftSkidMarks.length > _maxSkidMarks) {
        leftSkidMarks.removeAt(0);
        rightSkidMarks.removeAt(0);
      }
    }
  }
}
