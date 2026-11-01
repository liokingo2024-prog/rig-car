import 'package:flutter/material.dart';

import 'model_data.dart';

class PreRiggedCar {
  final String id;
  final String name;
  final String category; // 'Sports', 'Off-Road', 'Utility', 'Electric'
  final String description;
  final String drive; // 'AWD', 'RWD', 'FWD'
  final double mass;
  final double engineForce;
  final double grip;
  final double suspension;
  final double centerOfMass;
  final bool frontSteering;
  final bool rearSteering;
  final bool frontTraction;
  final bool rearTraction;
  final double wheelbase;
  final double trackWidth;
  final Color accentColor;
  final Color secondaryColor;
  final List<Vec3> wheelPositions;

  const PreRiggedCar({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.drive,
    required this.mass,
    required this.engineForce,
    required this.grip,
    required this.suspension,
    required this.centerOfMass,
    required this.frontSteering,
    required this.rearSteering,
    required this.frontTraction,
    required this.rearTraction,
    required this.wheelbase,
    required this.trackWidth,
    required this.accentColor,
    required this.secondaryColor,
    required this.wheelPositions,
  });

  RigConfig toRigConfig() => RigConfig(
        modelName: '$name.glb',
        presetName: name,
        drive: drive,
        mass: mass,
        engineForce: engineForce,
        grip: grip,
        suspension: suspension,
        centerOfMass: centerOfMass,
        frontSteering: frontSteering,
        rearSteering: rearSteering,
        frontTraction: frontTraction,
        rearTraction: rearTraction,
        wheelPositions: wheelPositions,
      );
}

const preRiggedCars = [
  PreRiggedCar(
    id: 'apex_gt',
    name: 'Apex GT Coupe',
    category: 'Sports',
    description:
        'Low-slung grand tourer with sharp steering response and rear-biased traction.',
    drive: 'RWD',
    mass: 1250,
    engineForce: 480,
    grip: 1.20,
    suspension: 6.50,
    centerOfMass: -0.22,
    frontSteering: true,
    rearSteering: false,
    frontTraction: false,
    rearTraction: true,
    wheelbase: 2.7,
    trackWidth: 1.55,
    accentColor: Color(0xFFFF6E4D),
    secondaryColor: Color(0xFFB92D3F),
    wheelPositions: [
      Vec3(-0.82, 0.32, -1.35),
      Vec3(0.82, 0.32, -1.35),
      Vec3(-0.84, 0.32, 1.35),
      Vec3(0.84, 0.32, 1.35),
    ],
  ),
  PreRiggedCar(
    id: 'vanguard_4x4',
    name: 'Vanguard 4x4 Trail',
    category: 'Off-Road',
    description:
        'Heavy-duty off-road rig with long travel suspension and full all-wheel traction.',
    drive: 'AWD',
    mass: 2100,
    engineForce: 620,
    grip: 1.45,
    suspension: 4.20,
    centerOfMass: -0.10,
    frontSteering: true,
    rearSteering: false,
    frontTraction: true,
    rearTraction: true,
    wheelbase: 2.9,
    trackWidth: 1.68,
    accentColor: Color(0xFF7EBB86),
    secondaryColor: Color(0xFF2D6C53),
    wheelPositions: [
      Vec3(-0.90, 0.45, -1.45),
      Vec3(0.90, 0.45, -1.45),
      Vec3(-0.90, 0.45, 1.45),
      Vec3(0.90, 0.45, 1.45),
    ],
  ),
  PreRiggedCar(
    id: 'phantom_ev',
    name: 'Phantom Hyper-EV',
    category: 'Electric',
    description:
        'Quad-motor electric hypercar with instantaneous torque and maximum tire grip.',
    drive: 'AWD',
    mass: 1680,
    engineForce: 780,
    grip: 1.60,
    suspension: 7.20,
    centerOfMass: -0.28,
    frontSteering: true,
    rearSteering: false,
    frontTraction: true,
    rearTraction: true,
    wheelbase: 2.8,
    trackWidth: 1.62,
    accentColor: Color(0xFF00E5FF),
    secondaryColor: Color(0xFF007799),
    wheelPositions: [
      Vec3(-0.85, 0.30, -1.40),
      Vec3(0.85, 0.30, -1.40),
      Vec3(-0.85, 0.30, 1.40),
      Vec3(0.85, 0.30, 1.40),
    ],
  ),
  PreRiggedCar(
    id: 'titan_cargo',
    name: 'Titan Cargo Hauler',
    category: 'Utility',
    description:
        'Stiff suspension, heavy chassis, engineered for commercial cargo stability.',
    drive: 'RWD',
    mass: 2600,
    engineForce: 550,
    grip: 0.95,
    suspension: 8.50,
    centerOfMass: -0.05,
    frontSteering: true,
    rearSteering: false,
    frontTraction: false,
    rearTraction: true,
    wheelbase: 3.2,
    trackWidth: 1.72,
    accentColor: Color(0xFF77A8D8),
    secondaryColor: Color(0xFF315B91),
    wheelPositions: [
      Vec3(-0.88, 0.40, -1.60),
      Vec3(0.88, 0.40, -1.60),
      Vec3(-0.88, 0.40, 1.60),
      Vec3(0.88, 0.40, 1.60),
    ],
  ),
  PreRiggedCar(
    id: 'rallycross_rs',
    name: 'RallyCross RS',
    category: 'Sports',
    description:
        'Agile dirt and tarmac racer with high-response steering and balanced drift dynamics.',
    drive: 'AWD',
    mass: 1180,
    engineForce: 510,
    grip: 1.35,
    suspension: 5.40,
    centerOfMass: -0.16,
    frontSteering: true,
    rearSteering: false,
    frontTraction: true,
    rearTraction: true,
    wheelbase: 2.6,
    trackWidth: 1.58,
    accentColor: Color(0xFFFFD600),
    secondaryColor: Color(0xFFD48800),
    wheelPositions: [
      Vec3(-0.80, 0.36, -1.30),
      Vec3(0.80, 0.36, -1.30),
      Vec3(-0.80, 0.36, 1.30),
      Vec3(0.80, 0.36, 1.30),
    ],
  ),
  PreRiggedCar(
    id: 'metro_shuttle',
    name: 'Metro City Shuttle',
    category: 'Utility',
    description:
        'Compact front-wheel drive urban runner tuned for tight turning radius.',
    drive: 'FWD',
    mass: 1450,
    engineForce: 340,
    grip: 1.00,
    suspension: 6.00,
    centerOfMass: -0.15,
    frontSteering: true,
    rearSteering: false,
    frontTraction: true,
    rearTraction: false,
    wheelbase: 2.5,
    trackWidth: 1.50,
    accentColor: Color(0xFFFF80AB),
    secondaryColor: Color(0xFFC51162),
    wheelPositions: [
      Vec3(-0.76, 0.32, -1.25),
      Vec3(0.76, 0.32, -1.25),
      Vec3(-0.76, 0.32, 1.25),
      Vec3(0.76, 0.32, 1.25),
    ],
  ),
];
