// ── Pipeline Status & Modes ─────────────────────────────────────────────────

enum StepStatus {
  pending,
  running,
  done,
  warning,
  manual,
}

class PipelineStepInfo {
  const PipelineStepInfo({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final String title;
  final String subtitle;
}

const List<PipelineStepInfo> kPipelineSteps = [
  PipelineStepInfo(
    number: 1,
    title: 'Upload Vehicle',
    subtitle: 'Import 3D model (.glb, .gltf)',
  ),
  PipelineStepInfo(
    number: 2,
    title: 'Scan & Organize',
    subtitle: 'Loose parts, 4-wheel match & hubs',
  ),
  PipelineStepInfo(
    number: 3,
    title: 'Add Physics',
    subtitle: 'Mass, suspension & tire grip',
  ),
  PipelineStepInfo(
    number: 4,
    title: 'Add Sound',
    subtitle: 'Engine RPM, skid & siren audio',
  ),
  PipelineStepInfo(
    number: 5,
    title: 'Export Rig',
    subtitle: 'Package Godot 4 vehicle scene',
  ),
];

// ── Detected Geometry Groups (Step 2) ───────────────────────────────────────

class DetectedMeshGroup {
  DetectedMeshGroup({
    required this.id,
    required this.name,
    required this.count,
    required this.shapeType,
    required this.role,
    this.isEnabled = true,
    this.nodeIndices = const [],
    this.partIds = const [],
  });

  final int id;
  final String name;
  final int count;
  final String shapeType; // e.g., 'Cylindrical', 'Conical', 'Box'
  String role; // 'Spin (Wheel)' | 'Steer Only (Caliper)' | 'Static (Chassis/Exhaust)'
  bool isEnabled;
  final List<int> nodeIndices;
  final List<String> partIds;
}

// ── Physics Handling Presets (Step 3) ───────────────────────────────────────

class HandlingPreset {
  const HandlingPreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.mass,
    required this.grip,
    required this.suspension,
    required this.engineForce,
    required this.centerOfMassY,
    required this.springRestLength,
    required this.springStiffness,
    required this.dampingCompression,
    required this.steerAngle,
  });

  final String id;
  final String title;
  final String subtitle;
  final double mass;
  final double grip;
  final double suspension;
  final double engineForce;
  final double centerOfMassY;
  final double springRestLength;
  final double springStiffness;
  final double dampingCompression;
  final double steerAngle;
}

const List<HandlingPreset> kHandlingPresets = [
  HandlingPreset(
    id: 'sport',
    title: 'Sport / Interceptor',
    subtitle: 'Stiff damping, high grip & sharp steering',
    mass: 1450,
    grip: 2.2,
    suspension: 6.2,
    engineForce: 480,
    centerOfMassY: 0.32,
    springRestLength: 0.18,
    springStiffness: 42.0,
    dampingCompression: 2.4,
    steerAngle: 36.0,
  ),
  HandlingPreset(
    id: 'drift',
    title: 'Arcade Drift',
    subtitle: 'Low rear friction, high yaw torque & slide bias',
    mass: 1250,
    grip: 1.4,
    suspension: 5.0,
    engineForce: 550,
    centerOfMassY: 0.28,
    springRestLength: 0.15,
    springStiffness: 48.0,
    dampingCompression: 2.0,
    steerAngle: 44.0,
  ),
  HandlingPreset(
    id: 'offroad',
    title: 'Off-Road SUV',
    subtitle: 'High clearance, long travel & compliant dampers',
    mass: 2100,
    grip: 1.9,
    suspension: 7.8,
    engineForce: 420,
    centerOfMassY: 0.45,
    springRestLength: 0.26,
    springStiffness: 28.0,
    dampingCompression: 3.2,
    steerAngle: 32.0,
  ),
  HandlingPreset(
    id: 'utility',
    title: 'Heavy Utility',
    subtitle: 'Payload stability, high mass & rigid leaf springs',
    mass: 2800,
    grip: 1.6,
    suspension: 8.5,
    engineForce: 380,
    centerOfMassY: 0.52,
    springRestLength: 0.22,
    springStiffness: 55.0,
    dampingCompression: 3.8,
    steerAngle: 28.0,
  ),
];

// ── Acoustic Profiles & Audio Slots (Step 4) ────────────────────────────────

class AcousticProfile {
  const AcousticProfile({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.baseRpm,
    required this.maxRpm,
  });

  final String id;
  final String title;
  final String subtitle;
  final int baseRpm;
  final int maxRpm;
}

const List<AcousticProfile> kAcousticProfiles = [
  AcousticProfile(
    id: 'v10',
    title: 'V10 Supercar',
    subtitle: '8,500 RPM harmonic scream & high-frequency induction',
    baseRpm: 950,
    maxRpm: 8800,
  ),
  AcousticProfile(
    id: 'v8',
    title: 'V8 Muscle',
    subtitle: 'Deep cross-plane rumble, low idle lope & supercharger whine',
    baseRpm: 750,
    maxRpm: 6800,
  ),
  AcousticProfile(
    id: 'i4_turbo',
    title: 'Inline-4 Turbo',
    subtitle: 'Spooling turbo, sharp wastegate chirp & quick rev build',
    baseRpm: 850,
    maxRpm: 7200,
  ),
  AcousticProfile(
    id: 'ev',
    title: 'EV Motor Whine',
    subtitle: 'Inverter modulation, direct-drive stator hum & regenerative whine',
    baseRpm: 0,
    maxRpm: 16000,
  ),
];

class AudioSlotConfig {
  AudioSlotConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    this.fileName = 'Default asset',
    this.pitchMultiplier = 1.0,
    this.isPlaying = false,
  });

  final String id;
  final String title;
  final String subtitle;
  String fileName;
  double pitchMultiplier;
  bool isPlaying;
}
