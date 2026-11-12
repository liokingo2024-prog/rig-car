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
  double wheelRoll = 0.0; // Integrated wheel roll travel in meters

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

  /// Godot convention direction vectors (-Z forward, +X right)
  Vec3 get forwardVector => Vec3(-sin(yaw), 0, -cos(yaw));
  Vec3 get rightVector => Vec3(cos(yaw), 0, -sin(yaw));

  void reset() {
    position = const Vec3(0, 0, 24); // Start at beginning of test strip
    velocity = Vec3.zero;
    yaw = 0.0;
    yawRate = 0.0;
    steerAngle = 0.0;
    targetSteerAngle = 0.0;
    wheelRoll = 0.0;
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
    // 1. Progressive speed-sensitive steering with realistic steering rack rate
    final maxSteer = (maxSteerAngleDegrees * pi / 180.0).clamp(0.20, 0.85);
    final speedSteerFactor = 1.0 / (1.0 + (speedKmh / 95.0) * 1.15);
    targetSteerAngle = -steerInput * maxSteer * speedSteerFactor;
    final steerRate = steerInput.abs() > 0.01 ? 9.5 : 14.0; // Faster centering
    steerAngle += (targetSteerAngle - steerAngle) * (dt * steerRate).clamp(0.0, 1.0);

    // 2. Local direction vectors (Godot convention: -Z is forward, +X is right)
    final fwd = Vec3(-sin(yaw), 0, -cos(yaw));
    final right = Vec3(cos(yaw), 0, -sin(yaw));

    // 3. Local velocity decomposition
    final longSpeed = velocity.dot(fwd);
    final latSpeed = velocity.dot(right);
    speedKmh = (longSpeed * 3.6).abs();
    wheelRoll += longSpeed * dt;

    // 4. Transmission & Engine RPM model
    final gearRatios = [3.4, 2.1, 1.45, 1.1, 0.88, 0.72];
    if (longSpeed >= -0.2) {
      if (speedKmh > 185) {
        currentGear = 6;
      } else if (speedKmh > 140) {
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
      final throttleBlip = throttleInput > 0 ? throttleInput * 320.0 : 0.0;
      engineRpm = (950 + (speedKmh * ratio * 38) + throttleBlip).clamp(950.0, 7800.0);
    } else {
      currentGear = -1; // Reverse
      engineRpm = (950 + (speedKmh * 3.5 * 38)).clamp(950.0, 5000.0);
    }

    // 5. Powertrain Forces & Engine Compression Braking
    var driveForce = 0.0;
    var brakeForce = 0.0;

    final gearRatio = (currentGear == -1)
        ? 3.5
        : gearRatios[(currentGear - 1).clamp(0, 5)];

    if (throttleInput > 0.05) {
      final torqueCurve = 1.0 - (engineRpm / 9000.0) * 0.22;
      driveForce = throttleInput * engineForce * gearRatio * 4.4 * torqueCurve;
    } else if (throttleInput < -0.05) {
      if (longSpeed > 0.8) {
        brakeForce = (-throttleInput) * (mass * 9.81 * 1.15);
      } else {
        driveForce = throttleInput * engineForce * 8.5; // Reverse
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
      frontPower = frontTraction ? 0.5 : 0.0;
      rearPower = rearTraction ? 0.5 : 0.0;
    }

    final totalForwardThrust = (driveForce * (frontPower + rearPower)) -
        (brakeForce * (longSpeed >= 0 ? 1.0 : -1.0));

    // 6. Wheelbase, Rear-Axle Offset & Ackermann Tire Cornering Model
    final frontZ = (wheelPositions.length >= 2) ? wheelPositions[0].z : -1.35;
    final rearZ = (wheelPositions.length >= 4) ? wheelPositions[2].z : 1.35;
    final wheelbase = (rearZ - frontZ).abs().clamp(2.0, 4.2);
    final rearAxleOffset = rearZ.abs().clamp(0.85, 2.2);

    final effectiveFrontSteer = frontSteering ? steerAngle : 0.0;
    final effectiveRearSteer = rearSteering ? -steerAngle * 0.45 : 0.0;
    final netSteer = effectiveFrontSteer - effectiveRearSteer;

    // Raw kinematic yaw rate, clamped by the physical tire adhesion limit.
    final rawTargetYawRate = (longSpeed / wheelbase) * tan(netSteer);
    final maxCorneringG = (grip * 1.35).clamp(0.65, 2.8);
    final maxLateralAccel = maxCorneringG * 9.81;
    final maxPhysYawRate = longSpeed.abs() > 1.5
        ? (maxLateralAccel / longSpeed.abs())
        : 4.0;
    final clampedTargetYawRate =
        rawTargetYawRate.clamp(-maxPhysYawRate, maxPhysYawRate);

    // Drift triggers: handbrake at speed, or power/steer demand beyond grip.
    final isHandbrakeActive = handbrake;
    final demandOverLimit =
        (rawTargetYawRate.abs() * longSpeed.abs()) / maxLateralAccel;
    final rwdPowerOversteer =
        (drive == 'RWD' && throttleInput > 0.75 && speedKmh > 45.0) ? 0.25 : 0.0;
    isDrifting = (isHandbrakeActive && speedKmh > 10.0) ||
        ((demandOverLimit + rwdPowerOversteer) > 1.28 && speedKmh > 65.0);

    // 7. Aerodynamic Drag + Rolling Resistance + Engine Braking (Off-Throttle)
    const airDragCoeff = 0.36;
    final dragForce = 0.5 * airDragCoeff * 1.225 * (longSpeed * longSpeed.abs());
    final rollingResistance = mass * 9.81 * 0.016;
    final engineBraking = (throttleInput.abs() <= 0.05 && longSpeed.abs() > 0.5)
        ? (mass * 0.85 * gearRatio * 0.42)
        : 0.0;
    final corneringScrubDrag = (steerAngle.abs() * longSpeed.abs() * mass * 0.12);

    final signLong = longSpeed > 0.05 ? 1.0 : (longSpeed < -0.05 ? -1.0 : 0.0);
    final totalNetLongForce = totalForwardThrust -
        dragForce -
        ((rollingResistance + engineBraking + corneringScrubDrag) * signLong);

    final longAccel = totalNetLongForce / mass;

    // 8. Integrate Velocity, Yaw & Position (rear-axle planted kinematic model)
    if (!isDrifting) {
      // Smooth yaw rate with tire cornering stiffness so lateral load builds
      // progressively instead of snapping the heading in a single frame.
      final corneringResponse =
          (11.0 * (grip / 1.1).clamp(0.6, 1.6)).clamp(6.0, 18.0);
      yawRate +=
          (clampedTargetYawRate - yawRate) * (dt * corneringResponse).clamp(0.0, 1.0);

      final newLongSpeed = longSpeed + longAccel * dt;
      final dYaw = yawRate * dt;
      final oldYaw = yaw;
      yaw += dYaw;

      // Pivot yaw rotation around the REAR AXLE so the rear tires track a pure
      // rolling arc: the chassis rotates about the rear contact patches instead
      // of spinning around its geometric centre like a hovercraft.
      final oldFwd = Vec3(-sin(oldYaw), 0, -cos(oldYaw));
      final newFwd = Vec3(-sin(yaw), 0, -cos(yaw));
      final newRight = Vec3(cos(yaw), 0, -sin(yaw));

      final rearAxleWorld = position - (oldFwd * rearAxleOffset);
      final pivotedCenter = rearAxleWorld + (newFwd * rearAxleOffset);

      // Bleed off any residual lateral velocity into pure rolling.
      final decayedLatSpeed = latSpeed * exp(-dt * 14.0);
      velocity = (newFwd * newLongSpeed) + (newRight * decayedLatSpeed);
      position = pivotedCenter + (velocity * dt);
    } else {
      // Controlled drift: handbrake or grip limit exceeded.
      final driftYawTarget = clampedTargetYawRate * 1.45;
      yawRate += (driftYawTarget - yawRate) * (dt * 6.5).clamp(0.0, 1.0);
      yaw += yawRate * dt;

      final newFwd = Vec3(-sin(yaw), 0, -cos(yaw));
      final newRight = Vec3(cos(yaw), 0, -sin(yaw));
      // Centrifugal tail-out slip opposes the turn direction.
      final centrifugalSlip = (longSpeed * yawRate) * 0.32;
      final latDamping = (5.5 * (isHandbrakeActive ? 0.45 : grip)).clamp(1.8, 9.0);
      final newLatSpeed =
          (latSpeed + (centrifugalSlip - latSpeed * latDamping) * dt)
              .clamp(-14.0, 14.0);
      final newLongSpeed = (longSpeed + longAccel * dt) * (1.0 - 0.35 * dt);

      velocity = (newFwd * newLongSpeed) + (newRight * newLatSpeed);
      position = position + (velocity * dt);
    }

    // Stop micro-crawl when stationary with no throttle
    if (throttleInput.abs() < 0.05 && speedKmh < 0.8) {
      velocity = Vec3.zero;
      speedKmh = 0.0;
      yawRate = 0.0;
    }

    // 9. Lateral & Longitudinal G-Force + Suspension Deflection
    lateralG = ((longSpeed * yawRate) / 9.81).clamp(-2.5, 2.5);
    longitudinalG = (longAccel / 9.81).clamp(-2.0, 2.0);

    final isHardBrakingLockup = (brakeForce > 9000.0 && speedKmh > 35.0);
    for (var i = 0; i < 4; i++) {
      final isRear = i >= 2;
      var slip = isDrifting ? 0.82 : (lateralG.abs() / maxCorneringG * 0.25);
      if (isRear && isHandbrakeActive) slip = 1.0;
      if (isHardBrakingLockup) slip += 0.35;
      wheelSlips[i] = slip.clamp(0.0, 1.0);
    }

    // Derived from the authored spring rate, damper and rest length so the
    // Workbench sliders produce a physically consistent ride.
    final effStiff = ((springStiffness / 45.0) * (suspension / 6.0)).clamp(0.35, 2.5);
    final effDamp = (dampingCompression / 2.4).clamp(0.35, 2.5);
    final restingFactor = (springRestLength / 0.18).clamp(0.45, 2.0);
    final comHeightFactor =
        ((0.55 - centerOfMass.abs()) * restingFactor).clamp(0.15, 1.2);
    final targetPitch =
        (longitudinalG * 0.042 * comHeightFactor / effStiff).clamp(-0.09, 0.09);
    final targetRoll =
        (-lateralG * 0.055 * comHeightFactor / effStiff).clamp(-0.11, 0.11);

    final responseRate = (11.0 * effDamp).clamp(4.0, 24.0);
    pitch += (targetPitch - pitch) * (dt * responseRate).clamp(0.0, 1.0);
    roll += (targetRoll - roll) * (dt * responseRate).clamp(0.0, 1.0);

    wheelSuspensionCompressions[0] = (pitch - roll).clamp(-0.12, 0.12); // FL
    wheelSuspensionCompressions[1] = (pitch + roll).clamp(-0.12, 0.12); // FR
    wheelSuspensionCompressions[2] = (-pitch - roll).clamp(-0.12, 0.12); // RL
    wheelSuspensionCompressions[3] = (-pitch + roll).clamp(-0.12, 0.12); // RR

    // 10. Record Skid Marks when slipping
    if (isDrifting ||
        isHardBrakingLockup ||
        (isHandbrakeActive && speedKmh > 5)) {
      final slipAlpha = (isDrifting ? 0.75 : 0.40).clamp(0.25, 0.85);
      final rearLeftZ =
          wheelPositions.length >= 4 ? wheelPositions[2].z.abs() : 1.35;
      final rearRightZ =
          wheelPositions.length >= 4 ? wheelPositions[3].z.abs() : 1.35;
      final rearLeftX = wheelPositions.length >= 4 ? wheelPositions[2].x : -0.85;
      final rearRightX = wheelPositions.length >= 4 ? wheelPositions[3].x : 0.85;

      final rearL = position - (fwd * rearLeftZ) + (right * rearLeftX);
      final rearR = position - (fwd * rearRightZ) + (right * rearRightX);

      leftSkidMarks.add(SkidPoint(rearL, slipAlpha));
      rightSkidMarks.add(SkidPoint(rearR, slipAlpha));

      if (leftSkidMarks.length > _maxSkidMarks) {
        leftSkidMarks.removeAt(0);
        rightSkidMarks.removeAt(0);
      }
    }
  }
}
