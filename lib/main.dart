import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'auto_detector.dart';
import 'download_config.dart';
import 'file_picker.dart';
import 'glb_parser.dart';
import 'home_screen.dart';
import 'inspector_panel.dart';
import 'model_data.dart';
import 'pipeline_models.dart';
import 'pre_rigged_cars.dart';
import 'sketchfab_viewport.dart';
import 'solid_mesh_lod.dart';
import 'test_drive_viewport.dart';
import 'wireframe_viewer.dart';

void main() {
  runApp(const RigCarApp());
}

class RigCarApp extends StatelessWidget {
  const RigCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFF3F4F6);
    return MaterialApp(
      title: 'RIG-CAR Fleet & Auto-Rigger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A110E),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
              brightness: Brightness.dark,
            ).copyWith(
              primary: const Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: const Color(0xFF111C18),
              onSurface: ink,
            ),
        fontFamily: 'Arial',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D120F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF223127)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF223127)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF10B981)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF86978C), fontSize: 12),
          suffixStyle: const TextStyle(color: Color(0xFF86978C), fontSize: 12),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          titleLarge: TextStyle(
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: ink, fontSize: 14),
          bodyMedium: TextStyle(color: Color(0xFF91A0AA), fontSize: 12),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
      home: Builder(
        builder: (context) {
          final uri = Uri.base;
          final openWorkbench = uri.queryParameters['page'] == 'workbench' ||
              uri.queryParameters['workbench'] == 'true';
          if (openWorkbench) {
            final carId = uri.queryParameters['car'];
            PreRiggedCar? car;
            if (carId != null) {
              try {
                car = preRiggedCars.firstWhere((c) => c.id == carId);
              } catch (_) {}
            }
            return RigWorkbenchPage(initialCar: car);
          }
          return const RigHomeScreen();
        },
      ),
    );
  }
}

class RigWorkbenchPage extends StatefulWidget {
  const RigWorkbenchPage({
    super.key,
    this.initialCar,
    this.startInTestDrive = false,
  });

  final PreRiggedCar? initialCar;
  final bool startInTestDrive;

  @override
  State<RigWorkbenchPage> createState() => _RigWorkbenchPageState();
}

class _RigWorkbenchPageState extends State<RigWorkbenchPage> {
  int _activeStep = 1;
  String _inspectMode = 'auto'; // 'auto' | 'manual'
  int? _hoveredNodeIndex;
  bool _isTestDriveMode = false;
  bool _isDriveFullscreen = false;
  bool _showLeftPanel = true;
  bool _showRightPanel = true;
  final RigPreset _preset = presets.first;
  String _modelName = 'No model loaded';
  ParsedModel? _parsedModel;
  Uint8List? _modelBytes;
  DetectionResult? _detection;
  int? _selectedBodyNodeIndex;
  int? _selectedNodeIndex;
  int _viewportUpdateEpoch = 0;

  // Drivetrain & physics
  String _drive = 'AWD';
  double _mass = 1200;
  double _engineForce = 420;
  double _grip = 1.0;
  double _suspension = 5.9;
  double _centerOfMass = -0.18;
  bool _frontSteering = true;
  bool _rearSteering = false;
  bool _frontTraction = true;
  bool _rearTraction = true;

  // Handling presets & physics overrides
  String _selectedHandlingPreset = 'sport';
  double _springRestLength = 0.18;
  double _springStiffness = 42.0;
  double _dampingCompression = 2.4;
  double _steerAngle = 36.0;

  // Acoustics & Godot architecture
  String _selectedAcousticProfile = 'v10';
  bool _sirenAudioEnabled = false;
  bool _tireSkidAudioEnabled = true;
  String _godotArchitecture = 'standard';
  late List<DetectedMeshGroup> _detectedGroups;
  late List<AudioSlotConfig> _audioSlots;
  bool _isScanningWheels = false;
  int _scanStage = 0;
  bool _scanCompleted = false;
  bool _highlightFoundWheels = false;

  // Manual wheel assignments [FL, FR, RL, RR]
  final Map<String, DetectedWheel?> _assignedWheels = {
    'FL': null,
    'FR': null,
    'RL': null,
    'RR': null,
  };

  @override
  void initState() {
    super.initState();
    _detectedGroups = _initDetectedGroups();
    _audioSlots = _initAudioSlots();
    _isTestDriveMode = widget.startInTestDrive;
    if (_isTestDriveMode) _activeStep = 5;
    final car = widget.initialCar;
    if (car != null) {
      _modelName = '${car.name} (Template)';
      _drive = car.drive;
      _mass = car.mass;
      _engineForce = car.engineForce;
      _grip = car.grip;
      _suspension = car.suspension;
      _centerOfMass = car.centerOfMass;
      _frontSteering = car.frontSteering;
      _rearSteering = car.rearSteering;
      _frontTraction = car.frontTraction;
      _rearTraction = car.rearTraction;

      _parsedModel = ParsedModel.createProceduralDefault(
        name: car.name,
        wheelPositions: car.wheelPositions,
      );
      if (!_isTestDriveMode) _activeStep = 1;
    } else {
      _modelName = 'Apex GT Coupe (Template)';
      _parsedModel = ParsedModel.createProceduralDefault(
        name: 'Apex GT Coupe',
      );
    }
  }

  void _resetRiggingProcess({bool resetStep = true}) {
    _assignedWheels['FL'] = null;
    _assignedWheels['FR'] = null;
    _assignedWheels['RL'] = null;
    _assignedWheels['RR'] = null;
    _detection = null;
    _selectedBodyNodeIndex = null;
    _selectedNodeIndex = null;
    _hoveredNodeIndex = null;
    _isScanningWheels = false;
    _scanStage = 0;
    _scanCompleted = false;
    _highlightFoundWheels = false;
    _detectedGroups = _initDetectedGroups();
    if (resetStep) {
      _activeStep = 1;
    }
    _viewportUpdateEpoch++;
    clearSketchfabWheels();
    updateSketchfabWheelMarkers(const []);
    highlightSketchfabWheels(const []);
  }

  Future<void> _pickModel() async {
    try {
      final picked = await pickModelFile();
      if (!mounted || picked == null) return;

      // Discard current rigging process completely and start clear
      setState(() {
        _resetRiggingProcess();
        _modelName = picked.name;
      });

      if (picked.bytes.isNotEmpty) {
        // Normalize imported authoring units before detection and rendering.
        // This gives the viewport and exported Godot rig one stable vehicle
        // coordinate system regardless of whether the source used mm, cm, or
        // arbitrary units.
        final parsed = await GlbParser.parse(picked.name, picked.bytes);
        parsed.normalizeForRiggingInPlace();

        setState(() {
          _parsedModel = parsed;
          _modelBytes = picked.bytes;

          // Estimate mass from volume
          final size = parsed.worldBBox.size;
          final vol = (size.x.abs() * size.y.abs() * size.z.abs()).clamp(
            2.0,
            30.0,
          );
          _mass = (vol * 140.0).clamp(600.0, 2800.0).roundToDouble();
          _activeStep = 1;
        });

        _showMessage(
          'Model loaded: ${picked.name}',
        );
      } else {
        setState(() {
          _parsedModel = ParsedModel.createProceduralDefault(name: picked.name);
          _modelBytes = null;
          _activeStep = 1;
        });
        _showMessage('Loaded ${picked.name} (procedural fallback)');
      }
    } catch (e) {
      _showMessage('Error parsing model: $e');
    }
  }

  void _mapDetectedWheels(List<DetectedWheel> wheels) {
    _assignedWheels['FL'] = null;
    _assignedWheels['FR'] = null;
    _assignedWheels['RL'] = null;
    _assignedWheels['RR'] = null;

    for (final w in wheels) {
      final key =
          '${w.axle == 'front' ? 'F' : 'R'}${w.side == 'left' ? 'L' : 'R'}';
      if (_assignedWheels.containsKey(key) && _assignedWheels[key] == null) {
        _assignedWheels[key] = w;
      }
    }

    // Fill remaining unassigned slots
    final unassigned = wheels
        .where((w) => !_assignedWheels.values.contains(w))
        .toList();
    for (final key in ['FL', 'FR', 'RL', 'RR']) {
      if (_assignedWheels[key] == null && unassigned.isNotEmpty) {
        _assignedWheels[key] = unassigned.removeAt(0);
      }
    }
  }

  void _reassignWheel(String slot, int? nodeIndex) {
    if (nodeIndex == null || _parsedModel == null) return;
    final node = _parsedModel!.nodes[nodeIndex];
    final axle = slot.startsWith('F') ? 'front' : 'rear';
    final side = slot.endsWith('L') ? 'left' : 'right';

    setState(() {
      _assignedWheels[slot] = DetectedWheel(
        nodeIndex: node.index,
        nodeName: node.name,
        worldPosition: AutoDetector.worldCenterForNode(_parsedModel!, node),
        confidence: 1.0, // Human confirmed
        meshIndex: node.meshIndex,
        axle: axle,
        side: side,
      );
      _selectedNodeIndex = node.index;
    });
  }

  void _selectBody(int? nodeIndex) {
    if (nodeIndex == null || _parsedModel == null) return;
    setState(() => _selectedBodyNodeIndex = nodeIndex);
  }

  bool get _hasFourDistinctWheelAssignments {
    final assignments = [
      'FL',
      'FR',
      'RL',
      'RR',
    ].map((slot) => _assignedWheels[slot]).toList();
    if (assignments.any((wheel) => wheel == null)) return false;

    final wheels = assignments.cast<DetectedWheel>();
    final partIds = wheels
        .expand(
          (wheel) => wheel.partIds.isNotEmpty
              ? wheel.partIds
              : (wheel.partNodeIndices.isEmpty
                    ? <String>['node:${wheel.nodeIndex}']
                    : wheel.partNodeIndices.map((index) => 'node:$index')),
        )
        .toSet();
    if (partIds.length < 4) return false;

    for (var i = 0; i < wheels.length; i++) {
      for (var j = i + 1; j < wheels.length; j++) {
        if ((wheels[i].worldPosition - wheels[j].worldPosition).length < 0.01) {
          return false;
        }
      }
    }
    return true;
  }

  String? get _exportBlockReason {
    if (!_hasFourDistinctWheelAssignments) {
      return 'Confirm four different wheel assemblies before exporting.';
    }
    if (_parsedModel != null && _selectedBodyNodeIndex == null) {
      return 'Select the car body before exporting.';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFF3F4F6),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF13261F),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF10B981)),
          ),
        ),
      );
  }

  RigConfig get _config {
    List<Vec3>? wheelPositions;
    final fl = _assignedWheels['FL'];
    final fr = _assignedWheels['FR'];
    final rl = _assignedWheels['RL'];
    final rr = _assignedWheels['RR'];

    if (fl != null && fr != null && rl != null && rr != null) {
      wheelPositions = [
        fl.worldPosition,
        fr.worldPosition,
        rl.worldPosition,
        rr.worldPosition,
      ];
    }

    return RigConfig(
      modelName: _modelName,
      presetName: _preset.name,
      drive: _drive,
      mass: _mass,
      engineForce: _engineForce,
      grip: _grip,
      suspension: _suspension,
      centerOfMass: _centerOfMass,
      frontSteering: _frontSteering,
      rearSteering: _rearSteering,
      frontTraction: _frontTraction,
      rearTraction: _rearTraction,
      wheelPositions: wheelPositions,
      bodyNodeName: _parsedModel == null || _selectedBodyNodeIndex == null
          ? null
          : _parsedModel!.nodes[_selectedBodyNodeIndex!].name,
    );
  }

  Future<void> _exportGodotFiles() async {
    final blockReason = _exportBlockReason;
    if (blockReason != null) {
      _showMessage(blockReason);
      if (_parsedModel != null) _selectStep(2);
      return;
    }

    final config = _config;
    await downloadTextFile(
      'rig_car_config.json',
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      'application/json',
    );
    await downloadTextFile('rig_car.gd', config.toGdScript(), 'text/plain');
    await downloadTextFile('rig_car.tscn', config.toTscn(), 'text/plain');
    if (mounted) _showMessage('Exported Godot 4 rig files');
  }

  void _enterTestDrive() {
    setState(() {
      _isTestDriveMode = true;
    });
  }

  void _exitTestDrive() {
    setState(() {
      _isTestDriveMode = false;
      _isDriveFullscreen = false;
      _activeStep = 1;
    });
  }

  bool _isStepEnabled(int step) {
    if (step == 1) return true;
    if (_parsedModel == null) return false;
    if (step == 2) return true;
    final wheelCount = _assignedWheels.values.whereType<DetectedWheel>().length;
    final step2Done = _scanCompleted && wheelCount >= 4;
    if (step == 3) return step2Done;
    if (step == 4) return step2Done;
    if (step == 5) return step2Done;
    return false;
  }

  void _selectStep(int step) {
    if (!_isStepEnabled(step)) {
      _showMessage('Please complete Step 2 (Scan & Organize) before advancing.');
      return;
    }
    setState(() {
      _activeStep = step;
      _showRightPanel = true;
      _isTestDriveMode = false;
      _isDriveFullscreen = false;
    });
  }

  List<DetectedMeshGroup> _initDetectedGroups() {
    return [
      DetectedMeshGroup(
        id: 1,
        name: 'Outer Tires + Rims (4 corners · Grounded)',
        count: 4,
        shapeType: 'Cylindrical',
        role: 'Spin (Wheel)',
        isEnabled: true,
      ),
      DetectedMeshGroup(
        id: 2,
        name: 'Brake Discs / Calipers (4x · Coaxial)',
        count: 4,
        shapeType: 'Box',
        role: 'Steer Only (Knuckle/Caliper)',
        isEnabled: false,
      ),
      DetectedMeshGroup(
        id: 3,
        name: 'Suspension Uprights / Knuckles (4x · Inboard)',
        count: 4,
        shapeType: 'Irregular',
        role: 'Static (Chassis)',
        isEnabled: false,
      ),
    ];
  }

  List<AudioSlotConfig> _initAudioSlots() {
    return [
      AudioSlotConfig(
        id: 'idle',
        title: 'Idle Loop',
        subtitle: 'Low RPM engine idle sound bed',
        fileName: 'engine_idle_loop.wav',
      ),
      AudioSlotConfig(
        id: 'high_rpm',
        title: 'High RPM Loop',
        subtitle: 'Full-throttle high rev acoustic track',
        fileName: 'engine_high_rpm.wav',
      ),
      AudioSlotConfig(
        id: 'skid',
        title: 'Tire Skid',
        subtitle: 'Lateral scrub & drift screech',
        fileName: 'tire_skid_asphalt.wav',
      ),
      AudioSlotConfig(
        id: 'siren',
        title: 'Siren/Extra',
        subtitle: 'Accessory horn or emergency siren',
        fileName: 'police_siren_wail.wav',
      ),
    ];
  }

  StepStatus _getStepStatus(int step) {
    switch (step) {
      case 1:
        return _parsedModel != null ? StepStatus.done : StepStatus.pending;
      case 2:
        if (_parsedModel == null) return StepStatus.pending;
        if (_isScanningWheels) return StepStatus.running;
        if (_inspectMode == 'manual') return StepStatus.manual;
        final wheelCount =
            _assignedWheels.values.whereType<DetectedWheel>().length;
        if (_scanCompleted && wheelCount >= 4 && (_detection?.warnings.isEmpty ?? false)) {
          return StepStatus.done;
        } else if (_scanCompleted && _detection != null && _detection!.warnings.isNotEmpty) {
          return StepStatus.warning;
        }
        return StepStatus.pending;
      case 3:
        if (!_isStepEnabled(3)) return StepStatus.pending;
        return StepStatus.done;
      case 4:
        if (!_isStepEnabled(4)) return StepStatus.pending;
        return StepStatus.done;
      case 5:
        if (!_isStepEnabled(5)) return StepStatus.pending;
        if (_exportBlockReason == null) return StepStatus.done;
        return StepStatus.warning;
      default:
        return StepStatus.pending;
    }
  }

  void _ensureModel() {
    _parsedModel ??= ParsedModel.createProceduralDefault(
      name: _modelName != 'No model loaded' ? _modelName : 'Apex GT Coupe',
    );
  }

  void _onRotateYaw(double angle) {
    setState(() {
      _ensureModel();
      _parsedModel!.rotateYaw(angle);
      SolidScene.invalidate(_parsedModel!);
      _viewportUpdateEpoch++;
    });
    rotateSketchfabModel(angle);
    _showMessage('Rotated vehicle model by ${(angle * 180 / pi).round()}°');
  }

  void _onFlipFrontBack() {
    setState(() {
      _ensureModel();
      _parsedModel!.flipFrontBack();
      SolidScene.invalidate(_parsedModel!);
      _viewportUpdateEpoch++;
    });
    flipSketchfabModel();
    _showMessage('Flipped vehicle front to back (180° yaw)');
  }

  void _onSnapToGround() {
    setState(() {
      _ensureModel();
      _parsedModel!.snapToGround();
      SolidScene.invalidate(_parsedModel!);
      _viewportUpdateEpoch++;
    });
    snapSketchfabModelToGround();
    _showMessage('Snapped lowest vertices to ground plane (Y = 0.0m)');
  }

  void _onApplyScale(double targetLength) {
    setState(() {
      _ensureModel();
      _parsedModel!.normalizeForRiggingInPlace(targetFootprint: targetLength);
      SolidScene.invalidate(_parsedModel!);
      _viewportUpdateEpoch++;
    });
    scaleSketchfabModel(targetLength);
    _showMessage('Normalized vehicle footprint to ${targetLength.toStringAsFixed(1)}m');
  }

  Future<void> _onStartWheelScan() async {
    if (_isScanningWheels) return;
    _ensureModel();
    if (_parsedModel == null) return;

    setState(() {
      _isScanningWheels = true;
      _highlightFoundWheels = false;
      _scanStage = 1;
    });
    _showMessage('Neural Rig: Isolating mesh vertex islands (Stage 1/4)...');

    await Future.delayed(const Duration(milliseconds: 35));
    if (!mounted) return;
    setState(() => _scanStage = 2);
    _showMessage('Neural Rig: Coaxial hub clustering & circularity analysis (Stage 2/4)...');

    await Future.delayed(const Duration(milliseconds: 35));
    if (!mounted) return;
    setState(() => _scanStage = 3);
    _showMessage('Neural Rig: Ground contact patch & outer-track filtering (Stage 3/4)...');

    await Future.delayed(const Duration(milliseconds: 35));
    if (!mounted) return;
    setState(() => _scanStage = 4);
    _showMessage('Neural Rig: Solving hub centers & radius cylinder fit (Stage 4/4)...');

    await Future.delayed(const Duration(milliseconds: 35));
    if (!mounted) return;

    final jsResult = detectSketchfabWheels();
    final detection = AutoDetector.detect(_parsedModel!);
    _mapDetectedWheels(detection.wheels);

    if (jsResult != null) {
      try {
        final jsWheels = jsResult['wheels'];
        if (jsWheels != null) {
          for (final corner in ['FL', 'FR', 'RL', 'RR']) {
            final cornerData = jsWheels[corner];
            if (cornerData != null) {
              final existing = _assignedWheels[corner];
              final r = (cornerData['radius'] as num?)?.toDouble();
              final w = (cornerData['width'] as num?)?.toDouble();
              final smc = (cornerData['subMeshCount'] as num?)?.toInt();
              final cName = cornerData['name'] as String?;
              final cx = (cornerData['x'] as num?)?.toDouble();
              final cy = (cornerData['y'] as num?)?.toDouble();
              final cz = (cornerData['z'] as num?)?.toDouble();
              if (r != null && w != null) {
                final axle = corner.startsWith('F') ? 'front' : 'rear';
                final side = corner.endsWith('L') ? 'left' : 'right';
                _assignedWheels[corner] = DetectedWheel(
                  nodeIndex: existing?.nodeIndex ?? 0,
                  nodeName: cName ?? existing?.nodeName ?? 'Wheel_$corner',
                  worldPosition: (cx != null && cy != null && cz != null)
                      ? Vec3(cx, cy, cz)
                      : (existing?.worldPosition ?? Vec3.zero),
                  confidence: existing?.confidence ?? 0.95,
                  meshIndex: existing?.meshIndex,
                  partNodeIndices: existing?.partNodeIndices ?? [],
                  partIds: existing?.partIds ?? [],
                  axle: axle,
                  side: side,
                  radius: r,
                  width: w,
                  circularity: (cornerData['circularity'] as num?)?.toDouble() ?? existing?.circularity ?? 0.98,
                  subMeshCount: smc ?? existing?.subMeshCount ?? 1,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error syncing jsResult wheels: $e');
      }
    }

    setState(() {
      _detection = detection;
      _selectedBodyNodeIndex = detection.body?.nodeIndex;
      _drive = detection.suggestedDrive;
      _isScanningWheels = false;
      _scanStage = 4;
      _scanCompleted = true;
      _highlightFoundWheels = true;
      _viewportUpdateEpoch++;
    });

    final effectiveWheels = _getEffectiveWheelPositions();
    updateSketchfabWheelMarkers(effectiveWheels);

    final wheelNames = detection.wheels.map((w) => w.nodeName).toList();
    highlightSketchfabWheels(wheelNames);

    _showMessage('Wheel filtering complete: ${detection.wheels.length}/4 wheels detected & highlighted in viewport!');
  }

  void _onGroupRoleChange(int groupId, String role) {
    setState(() {
      final grp = _detectedGroups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => _detectedGroups.first,
      );
      grp.role = role;
    });
    _showMessage('Group $groupId assigned role: $role');
  }

  void _onPickWheelInViewport(String corner) {
    if (_selectedNodeIndex != null) {
      _reassignWheel(corner, _selectedNodeIndex);
      final mirrorCorner = corner == 'FL'
          ? 'FR'
          : (corner == 'FR'
              ? 'FL'
              : (corner == 'RL' ? 'RR' : 'RL'));
      final source = _assignedWheels[corner];
      if (source != null) {
        final mirroredPos = Vec3(
          -source.worldPosition.x,
          source.worldPosition.y,
          source.worldPosition.z,
        );
        final mirrorAxle = mirrorCorner.startsWith('F') ? 'front' : 'rear';
        final mirrorSide = mirrorCorner.endsWith('L') ? 'left' : 'right';
        _assignedWheels[mirrorCorner] = DetectedWheel(
          nodeIndex: source.nodeIndex,
          nodeName: '${source.nodeName}_mirrored',
          worldPosition: mirroredPos,
          confidence: source.confidence,
          meshIndex: source.meshIndex,
          partNodeIndices: source.partNodeIndices,
          partIds: source.partIds,
          axle: mirrorAxle,
          side: mirrorSide,
          radius: source.radius,
          width: source.width,
          circularity: source.circularity,
          subMeshCount: source.subMeshCount,
        );
      }
      setState(() {
        _scanCompleted = true;
        _highlightFoundWheels = true;
        _viewportUpdateEpoch++;
      });
      final effectiveWheels = _getEffectiveWheelPositions();
      updateSketchfabWheelMarkers(effectiveWheels);
      _showMessage('Assigned selected part to Wheel $corner & auto-mirrored to $mirrorCorner');
    } else {
      _showMessage('Select a tire in the 3D viewport, then click Pick to assign Wheel $corner');
    }
  }

  void _onRecalculateHeightFilter(double threshold) {
    if (_parsedModel != null) {
      final groundTol = (threshold / 100.0).clamp(0.02, 0.25);
      final jsResult = detectSketchfabWheels(groundTol: groundTol);
      final detection = AutoDetector.detect(
        _parsedModel!,
        groundTolRatio: groundTol,
        inboardTolRatio: 0.02,
      );
      _mapDetectedWheels(detection.wheels);
      if (jsResult != null) {
        try {
          final jsWheels = jsResult['wheels'];
          if (jsWheels != null) {
            for (final corner in ['FL', 'FR', 'RL', 'RR']) {
              final cornerData = jsWheels[corner];
              if (cornerData != null) {
                final existing = _assignedWheels[corner];
                final r = (cornerData['radius'] as num?)?.toDouble();
                final w = (cornerData['width'] as num?)?.toDouble();
                final smc = (cornerData['subMeshCount'] as num?)?.toInt();
                final cName = cornerData['name'] as String?;
                final cx = (cornerData['x'] as num?)?.toDouble();
                final cy = (cornerData['y'] as num?)?.toDouble();
                final cz = (cornerData['z'] as num?)?.toDouble();
                if (r != null && w != null) {
                  final axle = corner.startsWith('F') ? 'front' : 'rear';
                  final side = corner.endsWith('L') ? 'left' : 'right';
                  _assignedWheels[corner] = DetectedWheel(
                    nodeIndex: existing?.nodeIndex ?? 0,
                    nodeName: cName ?? existing?.nodeName ?? 'Wheel_$corner',
                    worldPosition: (cx != null && cy != null && cz != null)
                        ? Vec3(cx, cy, cz)
                        : (existing?.worldPosition ?? Vec3.zero),
                    confidence: existing?.confidence ?? 0.95,
                    meshIndex: existing?.meshIndex,
                    partNodeIndices: existing?.partNodeIndices ?? [],
                    partIds: existing?.partIds ?? [],
                    axle: axle,
                    side: side,
                    radius: r,
                    width: w,
                    circularity: (cornerData['circularity'] as num?)?.toDouble() ?? existing?.circularity ?? 0.98,
                    subMeshCount: smc ?? existing?.subMeshCount ?? 1,
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error syncing jsResult wheels: $e');
        }
      }
      setState(() {
        _detection = detection;
        _scanCompleted = true;
        _highlightFoundWheels = true;
        _viewportUpdateEpoch++;
      });
      final effectiveWheels = _getEffectiveWheelPositions();
      updateSketchfabWheelMarkers(effectiveWheels);
      final wheelNames = detection.wheels.map((w) => w.nodeName).toList();
      highlightSketchfabWheels(wheelNames);
      _showMessage('Re-run detection with ${threshold.round()}% ground tolerance cutoff');
    } else {
      _showMessage('Import a model first to run wheel detection');
    }
  }

  void _onMirrorLeftToRight() {
    setState(() {
      final fl = _assignedWheels['FL'];
      final rl = _assignedWheels['RL'];
      if (fl != null) {
        _assignedWheels['FR'] = DetectedWheel(
          nodeIndex: fl.nodeIndex,
          nodeName: 'Wheel_FR_Mirrored',
          worldPosition: Vec3(-fl.worldPosition.x, fl.worldPosition.y, fl.worldPosition.z),
          confidence: 1.0,
          axle: 'front',
          side: 'right',
        );
      }
      if (rl != null) {
        _assignedWheels['RR'] = DetectedWheel(
          nodeIndex: rl.nodeIndex,
          nodeName: 'Wheel_RR_Mirrored',
          worldPosition: Vec3(-rl.worldPosition.x, rl.worldPosition.y, rl.worldPosition.z),
          confidence: 1.0,
          axle: 'rear',
          side: 'right',
        );
      }
    });
    _showMessage('Mirrored Left wheels (FL, RL) to Right side (FR, RR)');
  }

  void _onRecenterPivots() {
    setState(() {
      for (final key in ['FL', 'FR', 'RL', 'RR']) {
        final w = _assignedWheels[key];
        if (w != null && _parsedModel != null && w.nodeIndex < _parsedModel!.nodes.length) {
          final node = _parsedModel!.nodes[w.nodeIndex];
          _assignedWheels[key] = DetectedWheel(
            nodeIndex: w.nodeIndex,
            nodeName: w.nodeName,
            worldPosition: AutoDetector.worldCenterForNode(_parsedModel!, node),
            confidence: w.confidence,
            meshIndex: w.meshIndex,
            axle: w.axle,
            side: w.side,
          );
        }
      }
    });
    _showMessage('Wheel spin pivots recentered to cylinder fit');
  }

  void _onHandlingPresetSelected(HandlingPreset preset) {
    setState(() {
      _selectedHandlingPreset = preset.id;
      _mass = preset.mass;
      _grip = preset.grip;
      _suspension = preset.suspension;
      _engineForce = preset.engineForce;
      _centerOfMass = preset.centerOfMassY;
      _springRestLength = preset.springRestLength;
      _springStiffness = preset.springStiffness;
      _dampingCompression = preset.dampingCompression;
      _steerAngle = preset.steerAngle;
    });
    _showMessage('Applied handling preset: ${preset.title}');
  }

  void _onResetPhysicsProperty(String prop) {
    final preset = kHandlingPresets.firstWhere(
      (p) => p.id == _selectedHandlingPreset,
      orElse: () => kHandlingPresets.first,
    );
    setState(() {
      switch (prop) {
        case 'mass':
          _mass = preset.mass;
          break;
        case 'centerOfMassY':
          _centerOfMass = preset.centerOfMassY;
          break;
        case 'suspension':
          _suspension = preset.suspension;
          break;
        case 'springStiffness':
          _springStiffness = preset.springStiffness;
          break;
        case 'dampingCompression':
          _dampingCompression = preset.dampingCompression;
          break;
        case 'grip':
          _grip = preset.grip;
          break;
        case 'steerAngle':
          _steerAngle = preset.steerAngle;
          break;
      }
    });
    _showMessage('Reset $prop to preset default');
  }

  void _onHoverPart(String? partId) {
    setState(() {
      if (partId == null || !_scanCompleted) {
        _hoveredNodeIndex = null;
        highlightSketchfabMeshesCyan(null);
        return;
      }
      if (partId.startsWith('wheel_')) {
        final slot = partId.substring('wheel_'.length).toUpperCase();
        _hoveredNodeIndex = _assignedWheels[slot]?.nodeIndex;
        highlightSketchfabMeshesCyan([slot, 'wheel', 'tire']);
      } else if (partId.startsWith('group_')) {
        final id = int.tryParse(partId.substring('group_'.length));
        final grp = _detectedGroups.firstWhere(
          (g) => g.id == id,
          orElse: () => _detectedGroups.first,
        );
        _hoveredNodeIndex = grp.nodeIndices.isNotEmpty
            ? grp.nodeIndices.first
            : null;
        if (id == 1) {
          highlightSketchfabMeshesCyan(['wheel', 'tire', 'tyre', 'rim']);
        } else if (id == 2) {
          highlightSketchfabMeshesCyan(['caliper', 'disc', 'brake']);
        } else if (id == 3) {
          highlightSketchfabMeshesCyan(['knuckle', 'upright', 'suspension', 'arm', 'wishbone']);
        }
      } else if (partId == 'model_root' ||
          partId == 'bbox' ||
          partId == 'ground_plane' ||
          partId == 'forward_axis') {
        _hoveredNodeIndex = _selectedBodyNodeIndex;
      } else {
        _hoveredNodeIndex = null;
        highlightSketchfabMeshesCyan(null);
      }
    });
  }

  List<Vec3> _getEffectiveWheelPositions() {
    final wheels = <Vec3>[];
    for (final key in ['FL', 'FR', 'RL', 'RR']) {
      final w = _assignedWheels[key];
      if (w != null) {
        wheels.add(w.worldPosition);
      }
    }
    if (wheels.length == 4) return wheels;
    if (_detection != null && _detection!.wheels.length >= 4) {
      return _detection!.wheels.take(4).map((w) => w.worldPosition).toList();
    }
    final car = widget.initialCar;
    if (car != null && car.wheelPositions.length >= 4) {
      return car.wheelPositions;
    }
    return const [
      Vec3(-0.95, 0.35, -1.25),
      Vec3(0.95, 0.35, -1.25),
      Vec3(-0.95, 0.35, 1.25),
      Vec3(0.95, 0.35, 1.25),
    ];
  }

  Widget _buildTestDriveViewport({bool isFullscreen = false}) {
    final viewport = TestDriveViewport(
      mass: _mass,
      engineForce: _engineForce,
      grip: _grip,
      suspension: _suspension,
      centerOfMass: _centerOfMass,
      drive: _drive,
      frontSteering: _frontSteering,
      rearSteering: _rearSteering,
      frontTraction: _frontTraction,
      rearTraction: _rearTraction,
      wheelPositions: _getEffectiveWheelPositions(),
      model: _parsedModel,
      detection: _detection,
      accentColor: _preset.accent,
      isFullscreen: isFullscreen,
      onToggleFullscreen: (full) => setState(() => _isDriveFullscreen = full),
      onExit: _exitTestDrive,
    );

    if (isFullscreen) {
      return viewport;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF041D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      clipBehavior: Clip.antiAlias,
      child: viewport,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isTestDriveMode && _isDriveFullscreen) {
      return Scaffold(
        backgroundColor: const Color(0xFF041D14),
        body: _buildTestDriveViewport(isFullscreen: true),
      );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1120;
          final tablet = constraints.maxWidth >= 760;
          return Column(
            children: [
              if (!desktop)
                _MobileHeader(
                  onExport: _exportGodotFiles,
                  isTestDrive: _isTestDriveMode,
                  onToggleTestDrive: () {
                    if (_isTestDriveMode) {
                      _exitTestDrive();
                    } else {
                      _enterTestDrive();
                    }
                  },
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (desktop)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: _showLeftPanel ? 250 : 0,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          color: Color(0xFF111714),
                          border: Border(
                            right: BorderSide(color: Color(0xFF1E352C)),
                          ),
                        ),
                        child: OverflowBox(
                          minWidth: 250,
                          maxWidth: 250,
                          alignment: Alignment.topLeft,
                          child: _DesktopSidebar(
                            activeStep: _activeStep,
                            onStepSelected: _selectStep,
                            hasModel: _parsedModel != null,
                            isTestDrive: _isTestDriveMode,
                            getStepStatus: _getStepStatus,
                            isStepEnabled: _isStepEnabled,
                            onToggleCollapse: () {
                              setState(() => _showLeftPanel = !_showLeftPanel);
                            },
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (desktop)
                            _DesktopTopbar(
                              modelName: _modelName,
                              onExport: _exportGodotFiles,
                              inspectMode: _inspectMode,
                              wheelsCount: _detection?.wheels.length ?? 0,
                              isScanDone: _scanCompleted,
                              isTestDrive: _isTestDriveMode,
                              onToggleTestDrive: () {
                                if (_isTestDriveMode) {
                                  _exitTestDrive();
                                } else {
                                  _enterTestDrive();
                                }
                              },
                              isLeftPanelOpen: _showLeftPanel,
                              onToggleLeftPanel: () {
                                setState(() => _showLeftPanel = !_showLeftPanel);
                              },
                              isRightPanelOpen: _showRightPanel,
                              onToggleRightPanel: () {
                                setState(() => _showRightPanel = !_showRightPanel);
                              },
                            ),
                          if (!desktop)
                            _StepStrip(
                              activeStep: _activeStep,
                              onStepSelected: _selectStep,
                              isStepEnabled: _isStepEnabled,
                            ),
                          Expanded(
                            child: _isTestDriveMode
                                ? Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      desktop ? 24 : 16,
                                      desktop ? 20 : 16,
                                      desktop ? 24 : 16,
                                      desktop ? 20 : 24,
                                    ),
                                    child: _buildTestDriveViewport(),
                                  )
                                : (tablet && desktop
                                      ? Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            24,
                                            20,
                                            24,
                                            20,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              // 3D Viewport stays anchored and fills available height
                                              Expanded(
                                                child: WireframeViewer(
                                                  model: _parsedModel,
                                                  modelBytes: _modelBytes,
                                                  detection: _detection,
                                                  bodyNodeIndex:
                                                      _selectedBodyNodeIndex,
                                                  selectedNodeIndex:
                                                      _selectedNodeIndex,
                                                  hoveredNodeIndex:
                                                      _hoveredNodeIndex,
                                                  onNodeSelected: (idx) {
                                                    setState(() {
                                                      _selectedNodeIndex = idx;
                                                      if (_selectedBodyNodeIndex == null && _parsedModel != null) {
                                                        _selectBody(idx);
                                                      }
                                                    });
                                                  },
                                                  accentColor: _preset.accent,
                                                  bodyColor: widget.initialCar?.accentColor ??
                                                      const Color(0xFFD6DBDF),
                                                  centerOfMassY: _centerOfMass,
                                                  updateEpoch: _viewportUpdateEpoch,
                                                  highlightWheels: _highlightFoundWheels,
                                                  onTestDrive: _enterTestDrive,
                                                ),
                                              ),
                                              if (_showRightPanel) ...[
                                                const SizedBox(width: 18),
                                                // Right sidepanel detail inspector
                                                SizedBox(
                                                  width: 360,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF111C18),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: const Color(0xFF1E352C),
                                                      ),
                                                    ),
                                                    clipBehavior: Clip.antiAlias,
                                                    child: _buildInspector(),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            16,
                                            16,
                                            16,
                                          ),
                                          child: WireframeViewer(
                                            model: _parsedModel,
                                            modelBytes: _modelBytes,
                                            detection: _detection,
                                            bodyNodeIndex:
                                                _selectedBodyNodeIndex,
                                            selectedNodeIndex:
                                                _selectedNodeIndex,
                                            hoveredNodeIndex:
                                                _hoveredNodeIndex,
                                            onNodeSelected: (idx) {
                                              setState(() {
                                                _selectedNodeIndex = idx;
                                                if (_selectedBodyNodeIndex == null && _parsedModel != null) {
                                                  _selectBody(idx);
                                                }
                                              });
                                            },
                                            accentColor: _preset.accent,
                                            bodyColor: widget.initialCar?.accentColor ??
                                                const Color(0xFFD6DBDF),
                                            centerOfMassY: _centerOfMass,
                                            updateEpoch: _viewportUpdateEpoch,
                                            highlightWheels: _highlightFoundWheels,
                                            onTestDrive: _enterTestDrive,
                                          ),
                                        )),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInspector() {
    return InspectorPanel(
      activeStep: _activeStep,
      inspectMode: _inspectMode,
      onInspectModeChanged: (mode) {
        setState(() => _inspectMode = mode);
      },
      parsedModel: _parsedModel,
      detection: _detection,
      assignedWheels: _assignedWheels,
      detectedGroups: _detectedGroups,
      selectedHandlingPreset: _selectedHandlingPreset,
      mass: _mass,
      grip: _grip,
      suspension: _suspension,
      engineForce: _engineForce,
      centerOfMassY: _centerOfMass,
      springRestLength: _springRestLength,
      springStiffness: _springStiffness,
      dampingCompression: _dampingCompression,
      steerAngle: _steerAngle,
      selectedAcousticProfile: _selectedAcousticProfile,
      sirenAudioEnabled: _sirenAudioEnabled,
      tireSkidAudioEnabled: _tireSkidAudioEnabled,
      audioSlots: _audioSlots,
      godotArchitecture: _godotArchitecture,
      canExport: _exportBlockReason == null,
      exportBlockReason: _exportBlockReason,
      onStepSelect: _selectStep,
      onPickModel: _pickModel,
      onRotateYaw: _onRotateYaw,
      onFlipFrontBack: _onFlipFrontBack,
      onSnapToGround: _onSnapToGround,
      onApplyScale: _onApplyScale,
      onStartScan: _onStartWheelScan,
      isScanning: _isScanningWheels,
      scanStage: _scanStage,
      isScanDone: _scanCompleted,
      onApproveAutoRig: _onStartWheelScan,
      onGroupRoleChange: _onGroupRoleChange,
      onPickWheelInViewport: _onPickWheelInViewport,
      onRecalculateHeightFilter: _onRecalculateHeightFilter,
      onMirrorLeftToRight: _onMirrorLeftToRight,
      onRecenterPivots: _onRecenterPivots,
      onHandlingPresetSelected: _onHandlingPresetSelected,
      onMassChanged: (val) => setState(() => _mass = val),
      onCenterOfMassChanged: (val) => setState(() => _centerOfMass = val),
      onSuspensionChanged: (val) => setState(() => _suspension = val),
      onSpringStiffnessChanged: (val) => setState(() => _springStiffness = val),
      onDampingCompressionChanged: (val) => setState(() => _dampingCompression = val),
      onGripChanged: (val) => setState(() => _grip = val),
      onSteerAngleChanged: (val) => setState(() => _steerAngle = val),
      onResetPhysicsProperty: _onResetPhysicsProperty,
      onAcousticProfileSelected: (profile) => setState(() => _selectedAcousticProfile = profile.id),
      onToggleSirenAudio: (enabled) => setState(() => _sirenAudioEnabled = enabled),
      onToggleTireSkidAudio: (enabled) => setState(() => _tireSkidAudioEnabled = enabled),
      onAudioSlotPitchChanged: (slotId, pitch) {
        setState(() {
          final slot = _audioSlots.firstWhere((s) => s.id == slotId);
          slot.pitchMultiplier = pitch;
        });
      },
      onPreviewAudioSlot: (slotId) {
        _showMessage('Playing acoustic preview for $slotId');
      },
      onGodotArchitectureChanged: (arch) => setState(() => _godotArchitecture = arch),
      onExport: _exportGodotFiles,
      onTestDrive: _enterTestDrive,
      onHoverPart: _onHoverPart,
    );
  }
}

// ── Desktop Sidebar ─────────────────────────────────────────────────────────

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.activeStep,
    required this.onStepSelected,
    required this.hasModel,
    required this.isTestDrive,
    required this.getStepStatus,
    required this.isStepEnabled,
    required this.onToggleCollapse,
  });

  final int activeStep;
  final ValueChanged<int> onStepSelected;
  final bool hasModel;
  final bool isTestDrive;
  final StepStatus Function(int step) getStepStatus;
  final bool Function(int step) isStepEnabled;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF111C18),
        border: Border(right: BorderSide(color: Color(0xFF1E352C))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Brand(),
              IconButton(
                tooltip: 'Collapse sidebar',
                icon: const Icon(
                  Icons.keyboard_double_arrow_left_rounded,
                  size: 18,
                  color: Color(0xFF86978C),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onToggleCollapse,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SmallLabel('RIGGING PIPELINE'),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final step in kPipelineSteps) ...[
                  _SidebarStepCard(
                    number: step.number,
                    title: step.title,
                    subtitle: step.subtitle,
                    status: getStepStatus(step.number),
                    isActive: activeStep == step.number,
                    isEnabled: isStepEnabled(step.number),
                    onTap: () => onStepSelected(step.number),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF13261F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E352C)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF10B981),
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasModel
                        ? 'Model parsed. Review hub alignment in 3D viewport.'
                        : 'Import a vehicle model to inspect wheels and body.',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'GODOT 4 VEHICLE PIPELINE',
            style: TextStyle(
              color: Color(0xFF6E7681),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarStepCard extends StatelessWidget {
  const _SidebarStepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final StepStatus status;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback? onTap;

  Widget _buildBadge() {
    if (!isEnabled) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF131A16),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1B241F)),
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    switch (status) {
      case StepStatus.done:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFF10B981),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF041D14),
            size: 15,
          ),
        );
      case StepStatus.warning:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF59E0B),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.priority_high_rounded,
            color: Color(0xFF1A1208),
            size: 15,
          ),
        );
      case StepStatus.manual:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF0C243B),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF1E3A5F)),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.circle,
            color: Color(0xFF38BDF8),
            size: 8,
          ),
        );
      case StepStatus.running:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFF13261F),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF10B981),
            ),
          ),
        );
      case StepStatus.pending:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF17201C),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF223127)),
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: !isEnabled
            ? const Color(0xFF0C1310)
            : (isActive ? const Color(0xFF13261F) : const Color(0xFF111C18)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: !isEnabled
              ? const Color(0xFF15221C)
              : (isActive ? const Color(0xFF10B981) : const Color(0xFF1E352C)),
        ),
      ),
      child: Row(
        children: [
          _buildBadge(),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: !isEnabled
                        ? const Color(0xFF4B5563)
                        : (isActive ? const Color(0xFFF3F4F6) : const Color(0xFFD1D5DB)),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: !isEnabled
                        ? const Color(0xFF374151)
                        : const Color(0xFF9CA3AF),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF10B981),
              size: 18,
            ),
        ],
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: !isEnabled
          ? Opacity(
              opacity: 0.38,
              child: cardContent,
            )
          : cardContent,
    );
  }
}

// ── Topbar ──────────────────────────────────────────────────────────────────

class _DesktopTopbar extends StatelessWidget {
  const _DesktopTopbar({
    required this.modelName,
    required this.onExport,
    required this.inspectMode,
    required this.wheelsCount,
    required this.isScanDone,
    required this.isTestDrive,
    required this.onToggleTestDrive,
    required this.isLeftPanelOpen,
    required this.onToggleLeftPanel,
    required this.isRightPanelOpen,
    required this.onToggleRightPanel,
  });

  final String modelName;
  final VoidCallback onExport;
  final String inspectMode;
  final int wheelsCount;
  final bool isScanDone;
  final bool isTestDrive;
  final VoidCallback onToggleTestDrive;
  final bool isLeftPanelOpen;
  final VoidCallback onToggleLeftPanel;
  final bool isRightPanelOpen;
  final VoidCallback onToggleRightPanel;

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    final Color statusBg;
    final Color statusBorder;

    if (!isScanDone) {
      statusText = inspectMode == 'manual' ? 'CUSTOM MODE' : 'READY TO RIG';
      statusColor = const Color(0xFF9CA3AF);
      statusBg = const Color(0xFF131A16);
      statusBorder = const Color(0xFF1E352C);
    } else if (inspectMode == 'manual' || wheelsCount < 4) {
      statusText = 'MANUAL ASSIST';
      statusColor = const Color(0xFFF59E0B);
      statusBg = const Color(0xFF281B0E);
      statusBorder = const Color(0xFF4D3810);
    } else {
      statusText = 'AUTO-RIGGED';
      statusColor = const Color(0xFF10B981);
      statusBg = const Color(0xFF13261F);
      statusBorder = const Color(0xFF1E352C);
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111714),
        border: Border(bottom: BorderSide(color: Color(0xFF223127))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: isLeftPanelOpen ? 'Collapse left sidebar' : 'Expand left sidebar',
            icon: Icon(
              isLeftPanelOpen
                  ? Icons.menu_open_rounded
                  : Icons.menu_rounded,
              size: 20,
              color: isLeftPanelOpen
                  ? const Color(0xFF10B981)
                  : const Color(0xFF86978C),
            ),
            onPressed: onToggleLeftPanel,
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Back to Fleet Library',
            icon: const Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: Color(0xFF86978C),
            ),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RigHomeScreen()),
                );
              }
            },
          ),
          const SizedBox(width: 6),
          const Text(
            'CAR RIGGER',
            style: TextStyle(
              color: Color(0xFFF0FDF4),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: statusBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: statusColor,
                ),
                const SizedBox(width: 5),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              modelName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF86978C), fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onToggleTestDrive,
            icon: Icon(
              isTestDrive
                  ? Icons.tune_rounded
                  : Icons.sports_motorsports_rounded,
              size: 15,
            ),
            label: Text(
              isTestDrive ? 'WORKBENCH' : 'TEST DRIVE',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: isTestDrive
                  ? const Color(0xFF1A231E)
                  : const Color(0xFF10B981),
              foregroundColor: isTestDrive
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFF062319),
              side: isTestDrive
                  ? const BorderSide(color: Color(0xFF223127))
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.file_download_outlined, size: 15),
            label: const Text('Export rig', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC9D1D9),
              side: const BorderSide(color: Color(0xFF223127)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: isRightPanelOpen ? 'Hide right sidepanel' : 'Show right sidepanel',
            icon: Icon(
              isRightPanelOpen
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
              size: 19,
              color: isRightPanelOpen
                  ? const Color(0xFF10B981)
                  : const Color(0xFF86978C),
            ),
            onPressed: onToggleRightPanel,
          ),
        ],
      ),
    );
  }
}

// ── Mobile Header & Strip ───────────────────────────────────────────────────

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.onExport,
    required this.isTestDrive,
    required this.onToggleTestDrive,
  });
  final VoidCallback onExport;
  final bool isTestDrive;
  final VoidCallback onToggleTestDrive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111714),
        border: Border(bottom: BorderSide(color: Color(0xFF223127))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Fleet Library',
            icon: const Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: Color(0xFF86978C),
            ),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RigHomeScreen()),
                );
              }
            },
          ),
          const SizedBox(width: 6),
          const _Brand(),
          const Spacer(),
          IconButton(
            onPressed: onToggleTestDrive,
            tooltip: isTestDrive ? 'Return to Workbench' : 'Test Drive Mode',
            icon: Icon(
              isTestDrive
                  ? Icons.tune_rounded
                  : Icons.sports_motorsports_rounded,
              color: isTestDrive
                  ? const Color(0xFF34D399)
                  : const Color(0xFF10B981),
            ),
          ),
          IconButton(
            onPressed: onExport,
            tooltip: 'Export Godot rig',
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
    );
  }
}

class _StepStrip extends StatelessWidget {
  const _StepStrip({
    required this.activeStep,
    required this.onStepSelected,
    required this.isStepEnabled,
  });
  final int activeStep;
  final ValueChanged<int> onStepSelected;
  final bool Function(int step) isStepEnabled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (final step in kPipelineSteps) ...[
            Builder(
              builder: (context) {
                final enabled = isStepEnabled(step.number);
                final selected = activeStep == step.number;
                final chip = ChoiceChip(
                  label: Text('${step.number}  ${step.title}'),
                  selected: selected,
                  onSelected: (_) => onStepSelected(step.number),
                  showCheckmark: false,
                  backgroundColor: !enabled
                      ? const Color(0xFF0C1310)
                      : const Color(0xFF111C18),
                  selectedColor: const Color(0xFF10B981),
                  side: BorderSide(
                    color: !enabled
                        ? const Color(0xFF15221C)
                        : (selected ? const Color(0xFF10B981) : const Color(0xFF1E352C)),
                  ),
                  labelStyle: TextStyle(
                    color: !enabled
                        ? const Color(0xFF4B5563)
                        : (selected
                            ? const Color(0xFF062319)
                            : const Color(0xFF9CA3AF)),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: enabled
                      ? chip
                      : Opacity(
                          opacity: 0.38,
                          child: chip,
                        ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF1A231E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF223127)),
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: Color(0xFF10B981),
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'RIG-CAR',
          style: TextStyle(
            color: Color(0xFFF0FDF4),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF65747D),
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Workflow Steps & Presets ────────────────────────────────────────────────

class RigPreset {
  const RigPreset({
    required this.name,
    required this.description,
    required this.accent,
    required this.secondary,
    required this.wheelbase,
    required this.trackWidth,
  });

  final String name;
  final String description;
  final Color accent;
  final Color secondary;
  final double wheelbase;
  final double trackWidth;
}

class WorkflowStep {
  const WorkflowStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final String title;
  final String subtitle;
}

const workflowSteps = [
  WorkflowStep(
    number: 1,
    title: 'Upload',
    subtitle: 'Import 3D model (.glb, .gltf)',
  ),
];

const presets = [
  RigPreset(
    name: 'Sports coupe',
    description: 'Low, fast, rear-biased',
    accent: Color(0xFF10B981),
    secondary: Color(0xFF065F46),
    wheelbase: 2.7,
    trackWidth: 1.55,
  ),
  RigPreset(
    name: 'Off-road rig',
    description: 'High clearance, soft ride',
    accent: Color(0xFF7EBB86),
    secondary: Color(0xFF2D6C53),
    wheelbase: 2.9,
    trackWidth: 1.68,
  ),
  RigPreset(
    name: 'Delivery van',
    description: 'Heavy body, stable setup',
    accent: Color(0xFF77A8D8),
    secondary: Color(0xFF315B91),
    wheelbase: 3.2,
    trackWidth: 1.72,
  ),
];
