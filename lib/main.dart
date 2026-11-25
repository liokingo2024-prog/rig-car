import 'dart:convert';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
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
          final isTestDrive = uri.queryParameters['page'] == 'test-drive' ||
              uri.queryParameters['drive'] == 'true' ||
              uri.queryParameters['test_drive'] == 'true';
          final openWorkbench = uri.queryParameters['page'] == 'workbench' ||
              uri.queryParameters['workbench'] == 'true' ||
              isTestDrive;
          if (openWorkbench) {
            final carId = uri.queryParameters['car'];
            PreRiggedCar? car;
            if (carId != null) {
              try {
                car = preRiggedCars.firstWhere((c) => c.id == carId);
              } catch (_) {}
            }
            return RigWorkbenchPage(initialCar: car, startInTestDrive: isTestDrive);
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

class _RigUndoSnapshot {
  _RigUndoSnapshot(this.wheels, {this.yawApplied = 0});

  final Map<String, DetectedWheel?> wheels;
  final double yawApplied;
}

class _RigWorkbenchPageState extends State<RigWorkbenchPage> {
  int _activeStep = 1;
  String _inspectMode = 'auto'; // 'auto' | 'manual'
  int? _hoveredNodeIndex;
  bool _isTestDriveMode = false;
  ParsedModel? _testDriveModel;
  Map<String, DetectedWheel?> _testDriveWheels = const {};
  bool _isDriveFullscreen = false;
  bool _showLeftPanel = true;
  bool _showRightPanel = true;
  bool _mobileShowInspector = false;
  final RigPreset _preset = presets.first;
  String _modelName = 'No model loaded';
  ParsedModel? _parsedModel;
  Uint8List? _modelBytes;

  // Import progress. Parsing a detailed car takes long enough that the app
  // needs to show it is working instead of looking frozen.
  bool _isLoadingModel = false;
  String _loadingStage = '';
  double _loadingProgress = 0.0;
  DetectionResult? _detection;
  int? _selectedBodyNodeIndex;
  int? _selectedNodeIndex;
  int _viewportUpdateEpoch = 0;
  int _turntableRequest = 0;
  int _cameraResetRequest = 0;
  final List<_RigUndoSnapshot> _undoStack = [];

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

  /// What the export button produces: 'glb' (organized model only), 'scene'
  /// (rigged tscn + script + model) or 'project' (full Godot 4 bundle).
  String _exportTarget = 'project';
  bool _exportIncludeAudio = true;
  bool _exportIncludeSourceModel = false;
  bool _excludeRoofAntenna = false;
  String? _activePickingCorner;
  late List<DetectedMeshGroup> _detectedGroups;
  late List<AudioSlotConfig> _audioSlots;
  bool _isScanningWheels = false;
  int _scanStage = 0;
  bool _scanCompleted = false;
  bool _highlightFoundWheels = false;
  List<Vec3> _aiHeadlights = const [];
  List<Vec3> _aiTaillights = const [];
  List<Vec3> _aiDoorHandles = const [];
  List<Vec3> _aiDoors = const [];

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
      final detection = AutoDetector.detect(_parsedModel!);
      _detection = detection;
      _mapDetectedWheels(detection.wheels);
      _updateDetectedGroupsFromWheels(detection);
      _scanCompleted = true;
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

      setState(() {
        // Discard current rigging process completely and start clear.
        _resetRiggingProcess();
        _modelName = picked.name;
        _isLoadingModel = true;
        _loadingStage = 'Loading ${picked.name}…';
        _loadingProgress = 0.08;
      });

      if (picked.bytes.isNotEmpty) {
        // Let the frame paint the overlay before parsing starts, otherwise the
        // first frames are spent inside the parser and the UI looks frozen.
        await Future<void>.delayed(const Duration(milliseconds: 16));

        final parsed = await GlbParser.parse(
          picked.name,
          picked.bytes,
          onProgress: (stage, progress) {
            if (!mounted) return;
            setState(() {
              _loadingStage = stage;
              _loadingProgress = progress;
            });
          },
        );
        if (!mounted) return;

        // Normalize imported authoring units before detection and rendering.
        // This gives the viewport and exported Godot rig one stable vehicle
        // coordinate system regardless of whether the source used mm, cm, or
        // arbitrary units.
        setState(() {
          _loadingStage = 'Normalizing scale…';
          _loadingProgress = 0.96;
        });
        await Future<void>.delayed(Duration.zero);
        parsed.normalizeForRiggingInPlace();
        if (!mounted) return;

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
          _isLoadingModel = false;
          _loadingProgress = 1.0;
        });

        _showMessage(
          'Model loaded: ${picked.name}',
        );
      } else {
        setState(() {
          _parsedModel = ParsedModel.createProceduralDefault(name: picked.name);
          _modelBytes = null;
          _activeStep = 1;
          _isLoadingModel = false;
        });
        _showMessage('Loaded ${picked.name} (procedural fallback)');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error parsing model: $e');
      }
    } finally {
      // Never leave the overlay stuck on screen, even if parsing threw.
      if (mounted && _isLoadingModel) {
        setState(() => _isLoadingModel = false);
      }
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
    _pushUndo();
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
        partNodeIndices: [node.index],
        spinNodeIndices: [node.index],
        axle: axle,
        side: side,
      );
      _selectedNodeIndex = node.index;
    });
  }

  void _syncJsAndAutoWheels(dynamic jsResult, DetectionResult detection) {
    _mapDetectedWheels(detection.wheels);

    if (jsResult != null) {
      try {
        final jsWheels = jsResult['wheels'];
        if (jsWheels != null) {
          final bodyNodeIdx = detection.body?.nodeIndex;
          final model = _parsedModel;
          final nonWheelNodes = <int>{};
          if (bodyNodeIdx != null) nonWheelNodes.add(bodyNodeIdx);
          if (model != null) {
            final carBox = model.worldBBox;
            final carLen = max(carBox.size.z.abs(), carBox.size.x.abs());
            final carW = min(carBox.size.z.abs(), carBox.size.x.abs());
            final carH = carBox.size.y.abs();
            for (final inst in model.instances) {
              final s = inst.worldBBox.size;
              final maxDim = max(s.x.abs(), max(s.y.abs(), s.z.abs()));
              if (s.z.abs() > carLen * 0.45 ||
                  s.x.abs() > carW * 0.48 ||
                  s.y.abs() > carH * 0.70 ||
                  maxDim > carLen * 0.45) {
                nonWheelNodes.add(inst.nodeIndex);
              }
            }
          }

          for (final corner in ['FL', 'FR', 'RL', 'RR']) {
            final cornerData = jsWheels[corner];
            if (cornerData != null) {
              final existing = _assignedWheels[corner];
              final r = (cornerData['radius'] as num?)?.toDouble() ?? existing?.radius ?? 0.34;
              final w = (cornerData['width'] as num?)?.toDouble() ?? existing?.width ?? 0.25;
              final smc = (cornerData['subMeshCount'] as num?)?.toInt() ?? existing?.subMeshCount ?? 1;
              final cName = cornerData['name'] as String? ?? existing?.nodeName ?? 'Wheel_$corner';
              final cx = (cornerData['x'] as num?)?.toDouble();
              final cy = (cornerData['y'] as num?)?.toDouble();
              final cz = (cornerData['z'] as num?)?.toDouble();
              final hubPos = (cx != null && cy != null && cz != null)
                  ? Vec3(cx, cy, cz)
                  : (existing?.worldPosition ?? Vec3.zero);

              final jsPartNames = (cornerData['partNames'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .where((s) => s.isNotEmpty)
                  .toSet() ?? const <String>{};
              final jsSpinNames = (cornerData['spinPartNames'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .where((s) => s.isNotEmpty)
                  .toSet() ?? const <String>{};
              final jsCaliperNames = (cornerData['caliperHubPartNames'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .where((s) => s.isNotEmpty)
                  .toSet() ?? const <String>{};

              final rawSpinBoxes = (cornerData['spinMeshBoxes'] as List<dynamic>?) ?? const [];
              final rawCalBoxes = (cornerData['caliperMeshBoxes'] as List<dynamic>?) ?? const [];

              final resolvedPartNodes = <int>{};
              final resolvedSpinNodes = <int>{};
              final resolvedCaliperNodes = <int>{};

              final expectedPos = (hubPos != Vec3.zero)
                  ? hubPos
                  : existing?.worldPosition;

              if (model != null) {
                final carBox = model.worldBBox;
                final fAxisIsZ = carBox.size.z.abs() >= carBox.size.x.abs();
                final latLimit = max(w * 0.78, r * 0.62);

                bool isStrictlyInsideWheelEnvelope(MeshInstance inst) {
                  if (nonWheelNodes.contains(inst.nodeIndex)) return false;
                  final b = inst.worldBBox;
                  final s = b.size;
                  final maxInstDim = max(s.x.abs(), max(s.y.abs(), s.z.abs()));
                  // A genuine wheel sub-mesh can never be larger than 2.25 * radius
                  if (maxInstDim > r * 2.25) return false;
                  if (expectedPos == null) return true;
                  final dLong = (fAxisIsZ
                          ? (b.center.z - expectedPos.z)
                          : (b.center.x - expectedPos.x))
                      .abs();
                  final dLat = (fAxisIsZ
                          ? (b.center.x - expectedPos.x)
                          : (b.center.z - expectedPos.z))
                      .abs();
                  final dUp = (b.center.y - expectedPos.y).abs();
                  if (dLong > r * 1.08 || dUp > r * 1.08 || dLat > latLimit) {
                    return false;
                  }
                  if (model.instances.length > 1) {
                    final minLong = (fAxisIsZ ? (b.lo.z - expectedPos.z) : (b.lo.x - expectedPos.x)).abs();
                    final maxLong = (fAxisIsZ ? (b.hi.z - expectedPos.z) : (b.hi.x - expectedPos.x)).abs();
                    if (max(minLong, maxLong) > r * 1.25) return false;
                    final minUp = (b.lo.y - expectedPos.y).abs();
                    final maxUp = (b.hi.y - expectedPos.y).abs();
                    if (max(minUp, maxUp) > r * 1.25) return false;
                    final minLat = (fAxisIsZ ? (b.lo.x - expectedPos.x) : (b.lo.z - expectedPos.z)).abs();
                    final maxLat = (fAxisIsZ ? (b.hi.x - expectedPos.x) : (b.hi.z - expectedPos.z)).abs();
                    if (max(minLat, maxLat) > latLimit * 1.35) return false;
                  }
                  return true;
                }

                bool matchesJsBox(MeshInstance inst, dynamic boxObj) {
                  if (boxObj == null) return false;
                  final bx = (boxObj['cx'] as num?)?.toDouble();
                  final by = (boxObj['cy'] as num?)?.toDouble();
                  final bz = (boxObj['cz'] as num?)?.toDouble();
                  final bsx = (boxObj['sx'] as num?)?.toDouble();
                  final bsy = (boxObj['sy'] as num?)?.toDouble();
                  final bsz = (boxObj['sz'] as num?)?.toDouble();
                  if (bx == null || by == null || bz == null) return false;
                  final ic = inst.worldBBox.center;
                  final isz = inst.worldBBox.size;
                  final centerDist =
                      (ic - Vec3(bx, by, bz)).length;
                  if (centerDist > max(r * 0.35, 0.12)) return false;
                  if (bsx != null && bsy != null && bsz != null) {
                    final sizeDiff = max(
                      (isz.x.abs() - bsx.abs()).abs(),
                      max(
                        (isz.y.abs() - bsy.abs()).abs(),
                        (isz.z.abs() - bsz.abs()).abs(),
                      ),
                    );
                    if (sizeDiff > max(r * 0.45, 0.15)) return false;
                  }
                  return true;
                }

                bool matchesJsName(String nodeName, Set<String> targetNames) {
                  if (nodeName.isEmpty || targetNames.isEmpty) return false;
                  if (targetNames.contains(nodeName)) return true;
                  // Handle multi-primitive split names (`${node.name}_${mesh.name}`)
                  for (final t in targetNames) {
                    if (t.isEmpty) continue;
                    if (nodeName.endsWith('_$t') || nodeName.startsWith('${t}_')) {
                      return true;
                    }
                  }
                  return false;
                }

                // 1. Authoritative 1:1 match against Three.js highlighted mesh boxes & names
                for (final inst in model.instances) {
                  if (!isStrictlyInsideWheelEnvelope(inst)) continue;
                  final nName = (inst.nodeIndex >= 0 && inst.nodeIndex < model.nodes.length)
                      ? model.nodes[inst.nodeIndex].name.toLowerCase()
                      : '';

                  final boxSpinMatch =
                      rawSpinBoxes.any((b) => matchesJsBox(inst, b));
                  final boxCalMatch =
                      rawCalBoxes.any((b) => matchesJsBox(inst, b));
                  final nameSpinMatch = matchesJsName(nName, jsSpinNames);
                  final nameCalMatch = matchesJsName(nName, jsCaliperNames);
                  final namePartMatch = matchesJsName(nName, jsPartNames);

                  if (boxSpinMatch || nameSpinMatch) {
                    resolvedSpinNodes.add(inst.nodeIndex);
                    resolvedPartNodes.add(inst.nodeIndex);
                  } else if (boxCalMatch || nameCalMatch) {
                    resolvedCaliperNodes.add(inst.nodeIndex);
                    resolvedPartNodes.add(inst.nodeIndex);
                  } else if (namePartMatch) {
                    resolvedPartNodes.add(inst.nodeIndex);
                    resolvedSpinNodes.add(inst.nodeIndex);
                  }
                }

                // 2. If name/box matching found nothing (e.g. coordinate scaling diff),
                // filter existing AutoDetector nodes strictly by the 3D wheel envelope
                if (resolvedPartNodes.isEmpty && existing != null) {
                  for (final inst in model.instances) {
                    if (!isStrictlyInsideWheelEnvelope(inst)) continue;
                    if (existing.spinNodeIndices.contains(inst.nodeIndex)) {
                      resolvedSpinNodes.add(inst.nodeIndex);
                      resolvedPartNodes.add(inst.nodeIndex);
                    } else if (existing.caliperHubNodeIndices.contains(inst.nodeIndex)) {
                      resolvedCaliperNodes.add(inst.nodeIndex);
                      resolvedPartNodes.add(inst.nodeIndex);
                    } else if (existing.partNodeIndices.contains(inst.nodeIndex)) {
                      resolvedPartNodes.add(inst.nodeIndex);
                      resolvedSpinNodes.add(inst.nodeIndex);
                    }
                  }
                }

                // 3. Last-resort 3D (X + Y + Z + size) envelope match around hubPos
                if (resolvedPartNodes.isEmpty && hubPos != Vec3.zero) {
                  for (final inst in model.instances) {
                    if (isStrictlyInsideWheelEnvelope(inst)) {
                      resolvedPartNodes.add(inst.nodeIndex);
                      resolvedSpinNodes.add(inst.nodeIndex);
                    }
                  }
                }
              }

              resolvedPartNodes.removeAll(nonWheelNodes);
              resolvedSpinNodes.removeAll(nonWheelNodes);
              resolvedCaliperNodes.removeAll(nonWheelNodes);

              int primaryNodeIdx;
              if (resolvedSpinNodes.isNotEmpty) {
                primaryNodeIdx = resolvedSpinNodes.first;
              } else if (resolvedPartNodes.isNotEmpty) {
                primaryNodeIdx = resolvedPartNodes.first;
              } else if (existing != null && !nonWheelNodes.contains(existing.nodeIndex)) {
                primaryNodeIdx = existing.nodeIndex;
              } else {
                int? fallbackNode;
                var closestDistSq = double.infinity;
                if (model != null) {
                  for (final inst in model.instances) {
                    if (nonWheelNodes.contains(inst.nodeIndex)) continue;
                    final d = inst.worldBBox.center - hubPos;
                    final distSq = d.x * d.x + d.y * d.y + d.z * d.z;
                    if (distSq < closestDistSq) {
                      closestDistSq = distSq;
                      fallbackNode = inst.nodeIndex;
                    }
                  }
                }
                primaryNodeIdx = fallbackNode ?? (existing?.nodeIndex ?? 1);
              }

              final axle = corner.startsWith('F') ? 'front' : 'rear';
              final side = corner.endsWith('L') ? 'left' : 'right';

              var authoritativeHub = hubPos;
              var authoritativeRadius = r;
              var authoritativeWidth = w;
              if (model != null) {
                final cand = <int>{};
                if (resolvedSpinNodes.isNotEmpty) {
                  cand.addAll(resolvedSpinNodes.where((n) => !nonWheelNodes.contains(n)));
                }
                if (cand.isEmpty && resolvedPartNodes.isNotEmpty) {
                  cand.addAll(resolvedPartNodes.where((n) => !nonWheelNodes.contains(n) && !resolvedCaliperNodes.contains(n)));
                }
                if (cand.isEmpty && !nonWheelNodes.contains(primaryNodeIdx)) {
                  cand.add(primaryNodeIdx);
                }

                BBox? meshBox;
                for (final inst in model.instances) {
                  if (cand.contains(inst.nodeIndex)) {
                    meshBox = meshBox == null
                        ? inst.worldBBox
                        : BBox.union([meshBox, inst.worldBBox]);
                  }
                }
                if (meshBox != null && meshBox.size.y > 0.05) {
                  final carBox = model.worldBBox;
                  final fAxisIsZ = carBox.size.z.abs() >= carBox.size.x.abs();
                  final carLength = max(1e-4, (fAxisIsZ ? carBox.size.z : carBox.size.x).abs());
                  final span = max(meshBox.size.x, meshBox.size.z);
                  final isSingleWheelMesh = span <= 0.42 * carLength;
                  final isNearExisting = existing == null ||
                      (meshBox.center - existing.worldPosition).length <= 0.15 * carLength;

                  if (isSingleWheelMesh && isNearExisting) {
                    authoritativeHub = meshBox.center;
                    final dLong = (fAxisIsZ ? meshBox.size.z : meshBox.size.x).abs();
                    final dUp = meshBox.size.y.abs();
                    final meshR = max(dLong, dUp) * 0.5;
                    if (meshR >= 0.15 && meshR <= 0.85) authoritativeRadius = meshR;
                    final meshW = (fAxisIsZ ? meshBox.size.x : meshBox.size.z).abs();
                    if (meshW >= 0.08 && meshW <= 0.65) authoritativeWidth = meshW;
                  }
                }
              }

              _assignedWheels[corner] = DetectedWheel(
                nodeIndex: primaryNodeIdx,
                nodeName: cName,
                worldPosition: authoritativeHub,
                confidence: existing?.confidence ?? 0.95,
                meshIndex: existing?.meshIndex,
                partNodeIndices: resolvedPartNodes.toList(),
                partIds: existing?.partIds ?? [],
                spinNodeIndices: resolvedSpinNodes.toList(),
                caliperHubNodeIndices: resolvedCaliperNodes.toList(),
                axle: axle,
                side: side,
                radius: authoritativeRadius,
                width: authoritativeWidth,
                circularity: (cornerData['circularity'] as num?)?.toDouble() ?? existing?.circularity ?? 0.98,
                subMeshCount: smc,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error syncing jsResult wheels: $e');
      }
    }
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

  /// Model plus the part names the exported vehicle should use. Merged-mesh
  /// models are split so the export exposes `Body`, `Left Front Wheel`,
  /// `Right Front Wheel`, `Left Rear Wheel` and `Right Rear Wheel`.
  ({ParsedModel? model, Map<String, String> wheelNames, String? bodyName, bool wheelSplit})
      _exportRig() {
    final model = _parsedModel;
    if (model == null) {
      return (model: null, wheelNames: const {}, bodyName: null, wheelSplit: false);
    }

    final wheels = <String, DetectedWheel>{};
    for (final corner in const ['FL', 'FR', 'RL', 'RR']) {
      final w = _assignedWheels[corner];
      if (w != null) wheels[corner] = w;
    }

    var rigModel = model;
    var wheelSplit = false;
    var wheelNames = {
      for (final e in wheels.entries) e.key: e.value.nodeName,
    };
    String? bodyName = _selectedBodyNodeIndex == null
        ? null
        : model.nodes[_selectedBodyNodeIndex!].name;

    if (wheels.length == 4) {
      final split = model.splitWheelIslands(wheels);
      if (split.wheelNodeIndices.isNotEmpty) {
        rigModel = split.model;
        wheelNames = {
          for (final e in split.wheelNodeIndices.entries)
            e.key: rigModel.nodes[e.value].name,
        };
        bodyName = kBodyNodeName;
        wheelSplit = true;
      }
    }

    return (
      model: rigModel,
      wheelNames: wheelNames,
      bodyName: bodyName,
      wheelSplit: wheelSplit,
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

    final rig = _exportRig();

    return RigConfig(
      modelName: _modelName,
      presetName: _selectedHandlingPreset,
      drive: _drive,
      mass: _mass,
      engineForce: _engineForce,
      grip: _grip,
      suspension: _suspension,
      centerOfMass: _centerOfMass,
      springRestLength: _springRestLength,
      springStiffness: _springStiffness,
      dampingCompression: _dampingCompression,
      steerAngle: _steerAngle,
      wheelRadius: _assignedWheels['FL']?.radius ?? 0.35,
      chassisSize: _parsedModel?.worldBBox.size,
      godotArchitecture: _godotArchitecture,
      frontSteering: _frontSteering,
      rearSteering: _rearSteering,
      frontTraction: _frontTraction,
      rearTraction: _rearTraction,
      wheelPositions: wheelPositions,
      bodyNodeName: rig.bodyName,
      wheelNodeNames: rig.wheelNames,
      headlightPositions: _aiHeadlights,
      taillightPositions: _aiTaillights,
      doorHandlePositions: _aiDoorHandles,
      doorPositions: _aiDoors,
    );
  }

  /// Runs an export for a target picked from a header export menu, keeping the
  /// step-5 selection in sync with what was actually exported.
  Future<void> _exportWithTarget(String target) async {
    if (_exportTarget != target) setState(() => _exportTarget = target);
    await _exportGodotFiles();
  }

  Future<void> _exportGodotFiles() async {
    final blockReason = _exportBlockReason;
    if (blockReason != null) {
      _showMessage(blockReason);
      if (_parsedModel != null) _selectStep(2);
      return;
    }

    final config = _config;
    final rig = _exportRig();
    final rigModel = rig.model;
    if (rigModel == null) {
      _showMessage('Load a vehicle model before exporting.');
      return;
    }

    final modelBase = _modelName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    final baseName = modelBase == 'No_model_loaded' || modelBase.isEmpty
        ? 'rig_car'
        : modelBase;

    // Rebase wheel geometry onto its hub so rotating an exported wheel node
    // spins that wheel instead of orbiting the whole car.
    final wheelPivots = <String, Vec3>{
      for (final e in rig.wheelNames.entries)
        if (_assignedWheels[e.key] != null)
          e.value: _assignedWheels[e.key]!.worldPosition,
    };
    final glbBytes = rigModel.toRiggedGlb(wheelPivots: wheelPivots);
    final glbName = '${baseName}_rigged.glb';

    if (_exportTarget == 'glb') {
      await downloadBytesFile(glbName, glbBytes, 'model/gltf-binary');
      if (mounted) {
        _showMessage('Exported $glbName (body + four named wheel nodes)');
      }
      return;
    }

    // Bundle every asset into a single zip: browsers block chained multi-file
    // downloads, and Godot needs the project file next to the scene.
    final archive = Archive();
    void addText(String name, String contents) {
      final bytes = utf8.encode(contents);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final sourceEntry = _modelName.contains('/')
        ? _modelName.split('/').last
        : _modelName;
    final sourceInstanceable =
        RegExp(r'\.(glb|gltf)$', caseSensitive: false).hasMatch(sourceEntry);
    final shipSource = _exportTarget == 'project' &&
        _exportIncludeSourceModel &&
        sourceInstanceable &&
        (_modelBytes?.isNotEmpty ?? false);
    // A merged-mesh car only exposes its wheels through the split export, and a
    // source Godot cannot import as a scene must never be referenced.
    final instanceName = shipSource && !rig.wheelSplit ? sourceEntry : glbName;

    addText('rig_car.gd', config.toGdScript());
    addText('rig_car.tscn', config.toTscn(modelPath: 'res://$instanceName'));
    addText(
      'rig_car_config.json',
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
    archive.addFile(ArchiveFile(glbName, glbBytes.length, glbBytes));

    if (shipSource) {
      final modelBytes = _modelBytes!;
      archive.addFile(ArchiveFile(sourceEntry, modelBytes.length, modelBytes));
    }

    if (_exportTarget == 'project') {
      addText('project.godot', _godotProjectFile());
      if (_exportIncludeAudio) {
        for (final slot in _audioSlots) {
          final bytes = slot.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          final safeName =
              slot.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
          archive.addFile(ArchiveFile('audio/$safeName', bytes.length, bytes));
        }
      }
    }

    final bundleName = _exportTarget == 'project'
        ? '${baseName}_godot4_bundle'
        : '${baseName}_rigged_scene';
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    await downloadBytesFile(
      '$bundleName.zip',
      zipBytes,
      'application/zip',
    );
    if (mounted) {
      _showMessage(_exportTarget == 'project'
          ? 'Exported $bundleName.zip (Godot 4 project bundle)'
          : 'Exported $bundleName.zip (rig_car.tscn + script + rigged glb)');
    }
  }

  /// Minimal Godot 4.3 project file so the exported scene opens and drives
  /// immediately, including the input actions used by rig_car.gd.
  String _godotProjectFile() {
    String key(int physicalKeycode) =>
        'Object(InputEventKey,"resource_local_to_scene":false,'
        '"resource_name":"","device":-1,"window_id":0,'
        '"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,'
        '"meta_pressed":false,"pressed":false,"keycode":0,'
        '"physical_keycode":$physicalKeycode,"key_label":0,"unicode":0,'
        '"location":0,"echo":false,"script":null)';

    String action(String code) =>
        '{\n"deadzone": 0.5,\n"events": [$code]\n}';

    return '''; Engine configuration file.
config_version=5

[application]

config/name="RIG-CAR"
config/features=PackedStringArray("4.3", "Forward Plus")
run/main_scene="res://rig_car.tscn"

[input]

accelerate=${action(key(87))}
brake=${action(key(83))}
steer_left=${action(key(65))}
steer_right=${action(key(68))}
handle_brake=${action(key(32))}
''';
  }

  Future<void> _enterTestDrive() async {
    _ensureModel();
    if (_parsedModel != null && (!_scanCompleted || _assignedWheels.length < 4)) {
      final detection = AutoDetector.detect(
        _parsedModel!,
        excludeRoofAntenna: _excludeRoofAntenna,
      );
      SolidScene.invalidate(_parsedModel!);
      if (detection.autoAxisResult != null &&
          detection.autoAxisResult!.yawRotatedRadians.abs() > 0.001) {
        rotateSketchfabModel(detection.autoAxisResult!.yawRotatedRadians);
      }
      purgeSketchfabUnderWheelObjects();
      snapSketchfabModelToGround();
      final jsResult = detectSketchfabWheels();
      _syncJsAndAutoWheels(jsResult, detection);
      _updateDetectedGroupsFromWheels(detection);
      _detection = detection;
      _selectedBodyNodeIndex = detection.body?.nodeIndex;
      _drive = detection.suggestedDrive;
      _frontTraction = _drive == 'AWD' || _drive == 'FWD';
      _rearTraction = _drive == 'AWD' || _drive == 'RWD';
      _scanCompleted = true;
    }
    _prepareTestDriveRig();
    if (kIsWeb) {
      enterSketchfabTestDrive();
      setSketchfabTestDriveWorld('sunset', 'circuit');
    }
    if (mounted) {
      setState(() {
        _isTestDriveMode = true;
      });
    }
  }

  /// Builds a Test-Drive-only copy of the model ONLY when the car is a single
  /// merged mesh whose wheels have no dedicated scene nodes. When Scan & Organize
  /// has already assigned dedicated wheel nodes, keep `_assignedWheels` 100%
  /// untouched so no body/fender triangles are ever merged into the wheels!
  void _prepareTestDriveRig() {
    _testDriveModel = _parsedModel;
    _testDriveWheels = Map.of(_assignedWheels);

    final model = _parsedModel;
    if (model == null || model.instances.isEmpty) return;

    final wheels = <String, DetectedWheel>{};
    for (final corner in const ['FL', 'FR', 'RL', 'RR']) {
      final w = _assignedWheels[corner];
      if (w != null) wheels[corner] = w;
    }
    if (wheels.length < 4) return;

    // Identify large body/shared nodes (span > 42% of car length)
    final carBox = model.worldBBox;
    final carLen = max(carBox.size.z.abs(), carBox.size.x.abs());
    final sharedOrBodyNodes = <int>{
      if (_detection?.body != null) _detection!.body!.nodeIndex,
    };
    for (final inst in model.instances) {
      final s = inst.worldBBox.size;
      if (max(s.x.abs(), s.z.abs()) > carLen * 0.42) {
        sharedOrBodyNodes.add(inst.nodeIndex);
      }
    }

    // Check if every corner ALREADY has at least one dedicated non-body wheel node
    final allCornersHaveDedicatedNodes = wheels.values.every((w) {
      final nodes = <int>{
        ...w.spinNodeIndices,
        ...w.partNodeIndices,
        w.nodeIndex,
      };
      return nodes.any((n) => n >= 0 && !sharedOrBodyNodes.contains(n));
    });

    // If all 4 wheels already have dedicated wheel nodes from Scan, do NOT call
    // splitWheelIslands (which would slice fender-arch triangles out of the body)!
    if (allCornersHaveDedicatedNodes) return;

    final split = model.splitWheelIslands(wheels);
    if (split.wheelNodeIndices.isEmpty) return;
    _testDriveModel = split.model;

    split.wheelNodeIndices.forEach((corner, nodeIndex) {
      final w = wheels[corner]!;
      final node = split.model.nodes[nodeIndex];
      _testDriveWheels[corner] = DetectedWheel(
        nodeIndex: node.index,
        nodeName: node.name,
        worldPosition: w.worldPosition,
        confidence: w.confidence,
        meshIndex: node.meshIndex,
        partNodeIndices: [node.index],
        partIds: w.partIds,
        spinNodeIndices: [node.index],
        caliperHubNodeIndices: const [],
        axle: w.axle,
        side: w.side,
        radius: w.radius,
        width: w.width,
        circularity: w.circularity,
        subMeshCount: 1,
      );
    });
  }

  void _exitTestDrive() {
    setState(() {
      _isTestDriveMode = false;
      _isDriveFullscreen = false;
      _activeStep = 1;
      _testDriveModel = null;
      _testDriveWheels = const {};
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
      _mobileShowInspector = true;
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

  void _updateDetectedGroupsFromWheels(DetectionResult detection) {
    final allSpinNodes = <int>{};
    final allCaliperNodes = <int>{};
    for (final w in _assignedWheels.values.whereType<DetectedWheel>()) {
      allSpinNodes.addAll(w.spinNodeIndices);
      allCaliperNodes.addAll(w.caliperHubNodeIndices);
    }
    final wheelCount = _assignedWheels.values.whereType<DetectedWheel>().length;

    setState(() {
      _detectedGroups = [
        DetectedMeshGroup(
          id: 1,
          name: 'Outer Tires + Rims (4 corners · Grounded)',
          count: wheelCount,
          shapeType: 'Cylindrical',
          role: 'Spin (Wheel)',
          isEnabled: true,
          nodeIndices: allSpinNodes.toList(),
        ),
        DetectedMeshGroup(
          id: 2,
          name: 'Brake Discs / Calipers (Coaxial & Hub Frames)',
          count: allCaliperNodes.length,
          shapeType: 'Box',
          role: 'Steer Only (Knuckle/Caliper)',
          isEnabled: allCaliperNodes.isNotEmpty,
          nodeIndices: allCaliperNodes.toList(),
        ),
        DetectedMeshGroup(
          id: 3,
          name: 'Suspension Uprights / Knuckles (Inboard Chassis)',
          count: detection.suspensionNodes.length,
          shapeType: 'Irregular',
          role: 'Static (Chassis)',
          isEnabled: false,
          nodeIndices: detection.suspensionNodes,
        ),
      ];
    });
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

  void _syncWheelsAfterModelTransform() {
    if (!_scanCompleted || _parsedModel == null) return;
    final detection = AutoDetector.detect(
      _parsedModel!,
      excludeRoofAntenna: _excludeRoofAntenna,
      pruneUnderWheelObjects: false,
      autoAlignForward: false,
      snapToLand: false,
    );
    _detection = detection;
    _mapDetectedWheels(detection.wheels);
    _updateDetectedGroupsFromWheels(detection);
    final effectiveWheels = _getEffectiveWheelPositions();
    updateSketchfabWheelMarkers(effectiveWheels);
    final wheelNames = detection.wheels.map((w) => w.nodeName).toList();
    highlightSketchfabWheels(wheelNames);
  }

  void _onRotateYaw(double angle) {
    _pushUndo(yawApplied: angle);
    setState(() {
      _ensureModel();
      _parsedModel!.rotateYaw(angle);
      SolidScene.invalidate(_parsedModel!);
      _syncWheelsAfterModelTransform();
      _viewportUpdateEpoch++;
    });
    rotateSketchfabModel(angle);
    _showMessage('Rotated vehicle model by ${(angle * 180 / pi).round()}°');
  }

  void _onFlipFrontBack() {
    _pushUndo(yawApplied: pi);
    setState(() {
      _ensureModel();
      _parsedModel!.flipFrontBack();
      SolidScene.invalidate(_parsedModel!);
      _syncWheelsAfterModelTransform();
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
      _syncWheelsAfterModelTransform();
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
      _syncWheelsAfterModelTransform();
      _viewportUpdateEpoch++;
    });
    scaleSketchfabModel(targetLength);
    _showMessage('Normalized vehicle footprint to ${targetLength.toStringAsFixed(1)}m');
  }

  void _pushUndo({double yawApplied = 0}) {
    if (_parsedModel == null) return;
    _undoStack.add(
      _RigUndoSnapshot(Map.of(_assignedWheels), yawApplied: yawApplied),
    );
    if (_undoStack.length > 20) _undoStack.removeAt(0);
  }

  void _undoLastRigEdit() {
    if (_undoStack.isEmpty) {
      _showMessage('Nothing to undo');
      return;
    }
    final snapshot = _undoStack.removeLast();
    setState(() {
      if (snapshot.yawApplied != 0 && _parsedModel != null) {
        _parsedModel!.rotateYaw(-snapshot.yawApplied);
        SolidScene.invalidate(_parsedModel!);
        _syncWheelsAfterModelTransform();
      }
      // Restore the manual assignments after re-detection so the undo wins.
      _assignedWheels
        ..clear()
        ..addAll(snapshot.wheels);
      _viewportUpdateEpoch++;
    });
    if (snapshot.yawApplied != 0) {
      rotateSketchfabModel(-snapshot.yawApplied);
    }
    _showMessage('Undid last rig edit');
  }

  bool get _isEditingText {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _handleShortcut(VoidCallback action) {
    if (_isEditingText) return;
    action();
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

    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;
    setState(() => _scanStage = 2);

    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;
    setState(() => _scanStage = 3);

    // 1. Run AutoDetector in Dart FIRST (purges under-wheel mesh, aligns forward axis -Z, snaps to land Y=0)
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final detection = AutoDetector.detect(
      _parsedModel!,
      excludeRoofAntenna: _excludeRoofAntenna,
    );

    SolidScene.invalidate(_parsedModel!);
    if (detection.autoAxisResult != null &&
        detection.autoAxisResult!.yawRotatedRadians.abs() > 0.001) {
      rotateSketchfabModel(detection.autoAxisResult!.yawRotatedRadians);
    }
    purgeSketchfabUnderWheelObjects();
    snapSketchfabModelToGround();

    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;
    setState(() => _scanStage = 4);

    // 2. Call detectSketchfabWheels AFTER model is oriented and ground-snapped
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final jsResult = detectSketchfabWheels();
    _syncJsAndAutoWheels(jsResult, detection);
    _updateDetectedGroupsFromWheels(detection);

    // 3. AI Auto-Rig pass (ONNX YOLO11n-seg for forward alignment verification & headlights/taillights/doors/handles)
    List<Vec3> detectedHl = [];
    List<Vec3> detectedTl = [];
    List<Vec3> detectedDh = [];
    List<Vec3> detectedDr = [];
    try {
      final aiResult = await runSketchfabAiScan();
      if (aiResult != null) {
        if (aiResult['headlights'] is List) {
          detectedHl = (aiResult['headlights'] as List).map((p) => Vec3(
            ((p as Map)['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['z'] as num).toDouble(),
          )).toList();
        }
        if (aiResult['taillights'] is List) {
          detectedTl = (aiResult['taillights'] as List).map((p) => Vec3(
            ((p as Map)['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['z'] as num).toDouble(),
          )).toList();
        }
        if (aiResult['doorHandles'] is List) {
          detectedDh = (aiResult['doorHandles'] as List).map((p) => Vec3(
            ((p as Map)['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['z'] as num).toDouble(),
          )).toList();
        }
        if (aiResult['doors'] is List) {
          detectedDr = (aiResult['doors'] as List).map((p) => Vec3(
            ((p as Map)['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['z'] as num).toDouble(),
          )).toList();
        }
      }
    } catch (_) {}

    setState(() {
      _detection = detection;
      _selectedBodyNodeIndex = detection.body?.nodeIndex;
      _aiHeadlights = detectedHl;
      _aiTaillights = detectedTl;
      _aiDoorHandles = detectedDh;
      _aiDoors = detectedDr;
      _drive = detection.suggestedDrive;
      _frontTraction = _drive == 'AWD' || _drive == 'FWD';
      _rearTraction = _drive == 'AWD' || _drive == 'RWD';
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

    final axis = detection.autoAxisResult;
    final axisNote = (axis != null && (axis.axisSwapped || axis.frontFlipped))
        ? ' · Forward aligned (-Z)'
        : '';
    final cleanNote = detection.underWheelObjectsDeleted > 0
        ? ' · Purged ${detection.underWheelObjectsDeleted} under-wheel mesh'
        : '';
    final aiNote = (_aiHeadlights.isNotEmpty || _aiDoorHandles.isNotEmpty)
        ? ' · AI Rig: ${_aiHeadlights.length} HL, ${_aiTaillights.length} TL, ${_aiDoorHandles.length} Handles, ${_aiDoors.length} Doors'
        : '';
    _showMessage('Auto rig: ${detection.wheels.length}/4 wheels detected$axisNote$cleanNote$aiNote · 0.00m land contact');
  }

  void _onGroupRoleChange(int groupId, String role) {
    setState(() {
      final grp = _detectedGroups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => _detectedGroups.first,
      );
      grp.role = role;

      for (final slot in ['FL', 'FR', 'RL', 'RR']) {
        final w = _assignedWheels[slot];
        if (w == null) continue;
        final spins = <int>{...w.spinNodeIndices};
        final calipers = <int>{...w.caliperHubNodeIndices};
        final cornerGroupNodes = grp.nodeIndices
            .where((n) =>
                w.partNodeIndices.contains(n) ||
                w.nodeIndex == n ||
                spins.contains(n) ||
                calipers.contains(n))
            .toSet();

        if (role == 'Spin (Wheel)') {
          spins.addAll(cornerGroupNodes);
          calipers.removeAll(cornerGroupNodes);
        } else if (role.startsWith('Steer Only')) {
          spins.removeAll(cornerGroupNodes);
          calipers.addAll(cornerGroupNodes);
        } else {
          // Static (Chassis)
          spins.removeAll(cornerGroupNodes);
          calipers.removeAll(cornerGroupNodes);
        }

        _assignedWheels[slot] = DetectedWheel(
          nodeIndex: w.nodeIndex,
          nodeName: w.nodeName,
          worldPosition: w.worldPosition,
          confidence: w.confidence,
          meshIndex: w.meshIndex,
          partNodeIndices: w.partNodeIndices,
          partIds: w.partIds,
          spinNodeIndices: spins.toList(),
          caliperHubNodeIndices: calipers.toList(),
          axle: w.axle,
          side: w.side,
          radius: w.radius,
          width: w.width,
          circularity: w.circularity,
          subMeshCount: w.subMeshCount,
        );
      }
      _viewportUpdateEpoch++;
    });
    _showMessage('Group $groupId assigned role: $role');
  }

  void _onGroupToggle(int groupId, bool isEnabled) {
    setState(() {
      final grp = _detectedGroups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => _detectedGroups.first,
      );
      grp.isEnabled = isEnabled;

      for (final slot in ['FL', 'FR', 'RL', 'RR']) {
        final w = _assignedWheels[slot];
        if (w == null) continue;
        final spins = <int>{...w.spinNodeIndices};
        final calipers = <int>{...w.caliperHubNodeIndices};
        final cornerGroupNodes = grp.nodeIndices
            .where((n) =>
                w.partNodeIndices.contains(n) ||
                w.nodeIndex == n ||
                spins.contains(n) ||
                calipers.contains(n))
            .toSet();

        if (!isEnabled) {
          spins.removeAll(cornerGroupNodes);
          calipers.removeAll(cornerGroupNodes);
        } else {
          if (grp.role == 'Spin (Wheel)') {
            spins.addAll(cornerGroupNodes);
            calipers.removeAll(cornerGroupNodes);
          } else if (grp.role.startsWith('Steer Only')) {
            spins.removeAll(cornerGroupNodes);
            calipers.addAll(cornerGroupNodes);
          } else {
            spins.removeAll(cornerGroupNodes);
            calipers.removeAll(cornerGroupNodes);
          }
        }

        _assignedWheels[slot] = DetectedWheel(
          nodeIndex: w.nodeIndex,
          nodeName: w.nodeName,
          worldPosition: w.worldPosition,
          confidence: w.confidence,
          meshIndex: w.meshIndex,
          partNodeIndices: w.partNodeIndices,
          partIds: w.partIds,
          spinNodeIndices: spins.toList(),
          caliperHubNodeIndices: calipers.toList(),
          axle: w.axle,
          side: w.side,
          radius: w.radius,
          width: w.width,
          circularity: w.circularity,
          subMeshCount: w.subMeshCount,
        );
      }
      _viewportUpdateEpoch++;
    });
    _showMessage('Group $groupId ${isEnabled ? "enabled" : "disabled"}');
  }

  void _autoMirrorWheel(String corner) {
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

      int targetNodeIdx = source.nodeIndex;
      List<int> targetPartNodes = [...source.partNodeIndices];
      List<String> targetPartIds = [];

      if (_parsedModel != null) {
        MeshInstance? closestRightInst;
        double closestDist = source.radius * 1.15;
        for (final inst in _parsedModel!.instances) {
          final dist = (inst.worldBBox.center - mirroredPos).length;
          if (dist < closestDist) {
            closestDist = dist;
            closestRightInst = inst;
          }
        }
        if (closestRightInst != null) {
          targetNodeIdx = closestRightInst.nodeIndex;
          targetPartNodes = [closestRightInst.nodeIndex];
          targetPartIds = ['node:${closestRightInst.nodeIndex}'];
        }
      }

      if (targetPartIds.isEmpty) {
        targetPartIds = source.partIds.isNotEmpty
            ? source.partIds.map((id) => '${id}_mirrored_$mirrorCorner').toList()
            : ['mirrored_${mirrorCorner}_node_${source.nodeIndex}'];
      }

      _assignedWheels[mirrorCorner] = DetectedWheel(
        nodeIndex: targetNodeIdx,
        nodeName: '${source.nodeName}_mirrored',
        worldPosition: mirroredPos,
        confidence: source.confidence,
        meshIndex: source.meshIndex,
        partNodeIndices: targetPartNodes,
        partIds: targetPartIds,
        spinNodeIndices: targetPartNodes,
        caliperHubNodeIndices: const [],
        axle: mirrorAxle,
        side: mirrorSide,
        radius: source.radius,
        width: source.width,
        circularity: source.circularity,
        subMeshCount: source.subMeshCount,
      );
    }
  }

  void _onPickWheelInViewport(String corner) {
    setState(() => _activePickingCorner = corner);
    _showMessage('Click a wheel mesh in the 3D viewport to assign to Wheel $corner...');
  }

  void _onRecalculateHeightFilter(double groundTolPercent, double inboardTolPercent) {
    if (_parsedModel != null) {
      final groundTol = (groundTolPercent / 100.0).clamp(0.02, 0.25);
      final inboardTol = (inboardTolPercent / 100.0).clamp(0.0, 0.10);

      // 1. Run AutoDetector in Dart FIRST
      final detection = AutoDetector.detect(
        _parsedModel!,
        groundTolRatio: groundTol,
        inboardTolRatio: inboardTol,
        excludeRoofAntenna: _excludeRoofAntenna,
      );

      SolidScene.invalidate(_parsedModel!);
      if (detection.autoAxisResult != null &&
          detection.autoAxisResult!.yawRotatedRadians.abs() > 0.001) {
        rotateSketchfabModel(detection.autoAxisResult!.yawRotatedRadians);
      }
      purgeSketchfabUnderWheelObjects();
      snapSketchfabModelToGround();

      // 2. Run detectSketchfabWheels on rotated/snapped Three.js model
      final jsResult = detectSketchfabWheels(groundTol: groundTol, inboardTol: inboardTol);
      _syncJsAndAutoWheels(jsResult, detection);
      _updateDetectedGroupsFromWheels(detection);

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
      final axis = detection.autoAxisResult;
      final axisNote = (axis != null && (axis.axisSwapped || axis.frontFlipped))
          ? ' · Forward aligned (-Z)'
          : '';
      final cleanNote = detection.underWheelObjectsDeleted > 0
          ? ' · Purged ${detection.underWheelObjectsDeleted} under-wheel mesh'
          : '';
      _showMessage('Re-run detection (${groundTolPercent.round()}% tol, ${inboardTolPercent.toStringAsFixed(1)}% inb)$axisNote$cleanNote · 0.00m land contact');
    } else {
      _showMessage('Import a model first to run wheel detection');
    }
  }

  void _onMirrorLeftToRight() {
    setState(() {
      for (final pair in [('FL', 'FR'), ('RL', 'RR')]) {
        final source = _assignedWheels[pair.$1];
        final targetSlot = pair.$2;
        if (source == null) continue;

        final mirroredPos = Vec3(
          -source.worldPosition.x,
          source.worldPosition.y,
          source.worldPosition.z,
        );
        final mirrorAxle = targetSlot.startsWith('F') ? 'front' : 'rear';
        final mirrorSide = targetSlot.endsWith('L') ? 'left' : 'right';

        int targetNodeIdx = source.nodeIndex;
        List<int> targetPartNodes = [...source.partNodeIndices];
        List<String> targetPartIds = [];

        if (_parsedModel != null) {
          MeshInstance? closestRightInst;
          double closestDist = source.radius * 1.15;
          for (final inst in _parsedModel!.instances) {
            final dist = (inst.worldBBox.center - mirroredPos).length;
            if (dist < closestDist) {
              closestDist = dist;
              closestRightInst = inst;
            }
          }
          if (closestRightInst != null) {
            targetNodeIdx = closestRightInst.nodeIndex;
            targetPartNodes = [closestRightInst.nodeIndex];
            targetPartIds = ['node:${closestRightInst.nodeIndex}'];
          }
        }

        if (targetPartIds.isEmpty) {
          targetPartIds = source.partIds.isNotEmpty
              ? source.partIds.map((id) => '${id}_mirrored_$targetSlot').toList()
              : ['mirrored_${targetSlot}_node_${source.nodeIndex}'];
        }

        _assignedWheels[targetSlot] = DetectedWheel(
          nodeIndex: targetNodeIdx,
          nodeName: 'Wheel_${targetSlot}_Mirrored',
          worldPosition: mirroredPos,
          confidence: 1.0,
          meshIndex: source.meshIndex,
          partNodeIndices: targetPartNodes,
          partIds: targetPartIds,
          spinNodeIndices: targetPartNodes,
          caliperHubNodeIndices: const [],
          axle: mirrorAxle,
          side: mirrorSide,
          radius: source.radius,
          width: source.width,
          circularity: source.circularity,
          subMeshCount: source.subMeshCount,
        );
      }
      _scanCompleted = true;
      _highlightFoundWheels = true;
      _viewportUpdateEpoch++;
    });
    final effectiveWheels = _getEffectiveWheelPositions();
    updateSketchfabWheelMarkers(effectiveWheels);
    _showMessage('Mirrored Left wheels (FL, RL) to Right side (FR, RR)');
  }

  void _onRecenterPivots() {
    setState(() {
      for (final key in ['FL', 'FR', 'RL', 'RR']) {
        final w = _assignedWheels[key];
        if (w == null || _parsedModel == null) continue;

        final targetNodeSet = (w.spinNodeIndices.isNotEmpty
                ? w.spinNodeIndices
                : (w.partNodeIndices.isNotEmpty ? w.partNodeIndices : [w.nodeIndex]))
            .toSet();

        BBox? clusterBox;
        for (final inst in _parsedModel!.instances) {
          if (targetNodeSet.contains(inst.nodeIndex)) {
            clusterBox = clusterBox == null
                ? inst.worldBBox
                : BBox.union([clusterBox, inst.worldBBox]);
          }
        }

        Vec3 newCenter = clusterBox?.center ??
            (w.nodeIndex < _parsedModel!.nodes.length
                ? AutoDetector.worldCenterForNode(
                    _parsedModel!, _parsedModel!.nodes[w.nodeIndex])
                : w.worldPosition);

        // If mirrored wheel whose nodes live on opposite X side, preserve its side
        if (w.side == 'right' && newCenter.x < 0) {
          newCenter = Vec3(-newCenter.x, newCenter.y, newCenter.z);
        } else if (w.side == 'left' && newCenter.x > 0) {
          newCenter = Vec3(-newCenter.x, newCenter.y, newCenter.z);
        }

        _assignedWheels[key] = DetectedWheel(
          nodeIndex: w.nodeIndex,
          nodeName: w.nodeName,
          worldPosition: newCenter,
          confidence: w.confidence,
          meshIndex: w.meshIndex,
          partNodeIndices: w.partNodeIndices,
          partIds: w.partIds,
          spinNodeIndices: w.spinNodeIndices,
          caliperHubNodeIndices: w.caliperHubNodeIndices,
          radius: w.radius,
          width: w.width,
          circularity: w.circularity,
          subMeshCount: w.subMeshCount,
          axle: w.axle,
          side: w.side,
        );
      }
      _viewportUpdateEpoch++;
    });
    final effectiveWheels = _getEffectiveWheelPositions();
    updateSketchfabWheelMarkers(effectiveWheels);
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

  void _onNodeSelected(int idx) {
    if (_activePickingCorner != null) {
      final corner = _activePickingCorner!;
      setState(() {
        _activePickingCorner = null;
        _reassignWheel(corner, idx);
        _autoMirrorWheel(corner);
        _scanCompleted = true;
        _highlightFoundWheels = true;
        _viewportUpdateEpoch++;
      });
      final effectiveWheels = _getEffectiveWheelPositions();
      updateSketchfabWheelMarkers(effectiveWheels);
      _showMessage('Assigned node $idx to Wheel $corner & mirrored to opposite');
    } else {
      setState(() {
        _selectedNodeIndex = idx;
        if (_selectedBodyNodeIndex == null && _parsedModel != null) {
          _selectBody(idx);
        }
      });
    }
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
      } else if (partId == 'loose_parts') {
        _hoveredNodeIndex = null;
        highlightSketchfabMeshesCyan(['caliper', 'disc', 'brake', 'knuckle', 'arm', 'suspension', 'hub']);
      } else if (partId == 'groups_match') {
        _hoveredNodeIndex = null;
        highlightSketchfabMeshesCyan(['wheel', 'tire', 'tyre', 'rim', 'disc', 'caliper']);
      } else if (partId == 'height_filter') {
        _hoveredNodeIndex = null;
        final wheelNames = _assignedWheels.values
            .whereType<DetectedWheel>()
            .map((w) => w.nodeName)
            .toList();
        highlightSketchfabMeshesCyan(wheelNames.isNotEmpty ? wheelNames : ['wheel', 'tire']);
      } else if (partId == 'wheel_hubs') {
        _hoveredNodeIndex = null;
        highlightSketchfabMeshesCyan(['FL', 'FR', 'RL', 'RR', 'wheel', 'tire', 'rim']);
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
      model: _testDriveModel ?? _parsedModel,
      detection: _detection,
      accentColor: _preset.accent,
      isFullscreen: isFullscreen,
      onToggleFullscreen: (full) => setState(() => _isDriveFullscreen = full),
      onExit: _exitTestDrive,
      steerAngle: _steerAngle,
      springRestLength: _springRestLength,
      springStiffness: _springStiffness,
      dampingCompression: _dampingCompression,
      assignedWheels: _testDriveWheels.isEmpty
          ? _assignedWheels
          : _testDriveWheels,
      soundProfile: _selectedAcousticProfile,
      sirenEnabled: _sirenAudioEnabled,
      tireSkidAudioEnabled: _tireSkidAudioEnabled,
      onPhysicsUpdated: ({
        required double mass,
        required double engineForce,
        required double grip,
        required double springStiffness,
        required double dampingCompression,
        required String drive,
      }) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _mass = mass;
            _engineForce = engineForce;
            _grip = grip;
            _springStiffness = springStiffness;
            _dampingCompression = dampingCompression;
            _drive = drive;
            _frontTraction = drive != 'RWD';
            _rearTraction = drive != 'FWD';
          });
        });
      },
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

    final workbench = Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1120;
          return Column(
            children: [
              if (!desktop)
                _MobileHeader(
                  onExport: _exportWithTarget,
                  isTestDrive: _isTestDriveMode,
                  onToggleTestDrive: () {
                    if (_isTestDriveMode) {
                      _exitTestDrive();
                    } else {
                      _enterTestDrive();
                    }
                  },
                  isInspector: _mobileShowInspector,
                  onToggleInspector: () {
                    setState(() => _mobileShowInspector = !_mobileShowInspector);
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
                        width: (_showLeftPanel && !_isTestDriveMode) ? 250 : 0,
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
                              onExport: _exportWithTarget,
                              inspectMode: _inspectMode,
                              wheelsCount: _assignedWheels.values
                                  .whereType<DetectedWheel>()
                                  .length,
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
                                    padding: const EdgeInsets.all(8.0),
                                    child: _buildTestDriveViewport(),
                                  )
                                : (desktop
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
                                                  onNodeSelected: _onNodeSelected,
                                                  accentColor: _preset.accent,
                                                  bodyColor: widget.initialCar?.accentColor ??
                                                      const Color(0xFFD6DBDF),
                                                  centerOfMassY: _centerOfMass,
                                                  updateEpoch: _viewportUpdateEpoch,
                                                  highlightWheels: _highlightFoundWheels,
                                                  turntableRequest: _turntableRequest,
                                                  cameraResetRequest: _cameraResetRequest,
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
                                      : (_mobileShowInspector
                                          ? Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF111C18),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: const Color(0xFF1E352C),
                                                  ),
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: Column(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                      color: const Color(0xFF16231E),
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF10B981)),
                                                          const SizedBox(width: 8),
                                                          const Text(
                                                            'Rigging Tools & Inspector',
                                                            style: TextStyle(
                                                              color: Color(0xFFF0FDF4),
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w700,
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          TextButton.icon(
                                                            onPressed: () => setState(() => _mobileShowInspector = false),
                                                            icon: const Icon(Icons.view_in_ar_rounded, size: 15),
                                                            label: const Text('View 3D', style: TextStyle(fontSize: 12)),
                                                            style: TextButton.styleFrom(
                                                              foregroundColor: const Color(0xFF34D399),
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Expanded(child: _buildInspector()),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
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
                                                      onNodeSelected: _onNodeSelected,
                                                      accentColor: _preset.accent,
                                                      bodyColor: widget.initialCar?.accentColor ??
                                                          const Color(0xFFD6DBDF),
                                                      centerOfMassY: _centerOfMass,
                                                      updateEpoch: _viewportUpdateEpoch,
                                                      highlightWheels: _highlightFoundWheels,
                                                      turntableRequest: _turntableRequest,
                                                      cameraResetRequest: _cameraResetRequest,
                                                      onTestDrive: _enterTestDrive,
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: 14,
                                                    bottom: 56,
                                                    child: FloatingActionButton.extended(
                                                      heroTag: 'mobile_inspector_btn',
                                                      onPressed: () => setState(() => _mobileShowInspector = true),
                                                      backgroundColor: const Color(0xFF10B981),
                                                      foregroundColor: const Color(0xFF041D14),
                                                      icon: const Icon(Icons.tune_rounded, size: 17),
                                                      label: const Text(
                                                        'Rigging Tools',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))),
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

    if (_isTestDriveMode) return workbench;

    final page = _isLoadingModel
        ? Stack(
            fit: StackFit.expand,
            children: [workbench, _buildImportOverlay()],
          )
        : workbench;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () =>
            _handleShortcut(() => _selectStep(1)),
        const SingleActivator(LogicalKeyboardKey.digit2): () =>
            _handleShortcut(() => _selectStep(2)),
        const SingleActivator(LogicalKeyboardKey.digit3): () =>
            _handleShortcut(() => _selectStep(3)),
        const SingleActivator(LogicalKeyboardKey.digit4): () =>
            _handleShortcut(() => _selectStep(4)),
        const SingleActivator(LogicalKeyboardKey.digit5): () =>
            _handleShortcut(() => _selectStep(5)),
        const SingleActivator(LogicalKeyboardKey.keyT): () =>
            _handleShortcut(() {
              if (_isTestDriveMode) {
                _exitTestDrive();
              } else {
                _enterTestDrive();
              }
            }),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            _handleShortcut(() => setState(() => _cameraResetRequest++)),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _handleShortcut(() => setState(() => _turntableRequest++)),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _handleShortcut(_undoLastRigEdit),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            _handleShortcut(_undoLastRigEdit),
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  /// Blocks the workbench while a picked file is parsed and shows which stage
  /// the import has reached, so a heavy car never looks like a dead tab.
  Widget _buildImportOverlay() {
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: const Color(0xCC0A110E),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111C18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3810B981)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 32,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F4F6),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _loadingProgress > 0 ? _loadingProgress : null,
                    minHeight: 5,
                    backgroundColor: const Color(0x1AFFFFFF),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _loadingStage.isEmpty ? 'Importing vehicle…' : _loadingStage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF86978C),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
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
      exportTarget: _exportTarget,
      includeAudio: _exportIncludeAudio,
      includeSourceModel: _exportIncludeSourceModel,
      onExportTargetChanged: (target) => setState(() => _exportTarget = target),
      onIncludeAudioChanged: (v) => setState(() => _exportIncludeAudio = v),
      onIncludeSourceModelChanged: (v) =>
          setState(() => _exportIncludeSourceModel = v),
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
      onGroupToggle: _onGroupToggle,
      excludeRoofAntenna: _excludeRoofAntenna,
      onExcludeRoofAntennaChanged: (val) => setState(() => _excludeRoofAntenna = val),
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
        final slot = _audioSlots.firstWhere(
          (s) => s.id == slotId,
          orElse: () => _audioSlots.first,
        );
        if (slot.isPlaying) {
          playSketchfabAudioPreview(
            slotId,
            slot.pitchMultiplier,
            bytes: slot.bytes,
          );
          _showMessage(slot.bytes != null
              ? 'Playing ${slot.fileName}'
              : 'Playing acoustic preview for $slotId');
        } else {
          stopSketchfabAudioPreview();
          _showMessage('Stopped acoustic preview for $slotId');
        }
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
                    isOptional: step.isOptional,
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
    this.isOptional = false,
    required this.status,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool isOptional;
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: !isEnabled
                              ? const Color(0xFF4B5563)
                              : (isActive
                                  ? const Color(0xFFF3F4F6)
                                  : const Color(0xFFD1D5DB)),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isOptional) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: !isEnabled
                              ? const Color(0xFF101915)
                              : const Color(0xFF17231E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: !isEnabled
                                ? const Color(0xFF18251F)
                                : const Color(0xFF22332C),
                          ),
                        ),
                        child: Text(
                          'Optional',
                          style: TextStyle(
                            color: !isEnabled
                                ? const Color(0xFF4B5563)
                                : const Color(0xFF86978C),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
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
  final ValueChanged<String> onExport;
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
          PopupMenuButton<String>(
            tooltip: 'Choose what to export',
            onSelected: onExport,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'glb',
                child: Text('Organized model (.glb)', style: TextStyle(fontSize: 12)),
              ),
              PopupMenuItem(
                value: 'scene',
                child: Text('Rigged scene (.tscn + script)', style: TextStyle(fontSize: 12)),
              ),
              PopupMenuItem(
                value: 'project',
                child: Text('Full Godot 4 project (.zip)', style: TextStyle(fontSize: 12)),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF223127)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_download_outlined, size: 15, color: Color(0xFFC9D1D9)),
                  SizedBox(width: 6),
                  Text(
                    'Export rig',
                    style: TextStyle(fontSize: 11, color: Color(0xFFC9D1D9)),
                  ),
                ],
              ),
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
    this.isInspector = false,
    this.onToggleInspector,
  });
  final ValueChanged<String> onExport;
  final bool isTestDrive;
  final VoidCallback onToggleTestDrive;
  final bool isInspector;
  final VoidCallback? onToggleInspector;

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
          if (!isTestDrive && onToggleInspector != null)
            IconButton(
              tooltip: isInspector ? 'Switch to 3D Viewport' : 'Open Rigging Tools',
              icon: Icon(
                isInspector ? Icons.view_in_ar_rounded : Icons.tune_rounded,
                color: isInspector ? const Color(0xFF10B981) : const Color(0xFF86978C),
              ),
              onPressed: onToggleInspector,
            ),
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
          PopupMenuButton<String>(
            tooltip: 'Choose what to export',
            onSelected: onExport,
            icon: const Icon(Icons.file_download_outlined),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'glb',
                child: Text('Organized model (.glb)', style: TextStyle(fontSize: 12)),
              ),
              PopupMenuItem(
                value: 'scene',
                child: Text('Rigged scene (.tscn + script)', style: TextStyle(fontSize: 12)),
              ),
              PopupMenuItem(
                value: 'project',
                child: Text('Full Godot 4 project (.zip)', style: TextStyle(fontSize: 12)),
              ),
            ],
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
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${step.number}  ${step.title}'),
                      if (step.isOptional) ...[
                        const SizedBox(width: 5),
                        Text(
                          'Optional',
                          style: TextStyle(
                            color: !enabled
                                ? const Color(0xFF4B5563)
                                : (selected
                                    ? const Color(0xFF064E3B)
                                    : const Color(0xFF6B7280)),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
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
