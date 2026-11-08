import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'auto_detector.dart';
import 'download_config.dart';
import 'file_picker.dart';
import 'glb_parser.dart';
import 'home_screen.dart';
import 'model_data.dart';
import 'pre_rigged_cars.dart';
import 'test_drive_viewport.dart';
import 'wireframe_viewer.dart';

void main() {
  runApp(const RigCarApp());
}

class RigCarApp extends StatelessWidget {
  const RigCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFE9EEF2);
    return MaterialApp(
      title: 'RIG-CAR Fleet & Auto-Rigger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090D0B),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
              brightness: Brightness.dark,
            ).copyWith(
              primary: const Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: const Color(0xFF111714),
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
      home: const RigHomeScreen(),
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
  bool _isTestDriveMode = false;
  bool _isDriveFullscreen = false;
  bool _showLeftPanel = true;
  bool _showRightPanel = true;
  RigPreset _preset = presets.first;
  String _modelName = 'No model loaded';
  ParsedModel? _parsedModel;
  Uint8List? _modelBytes;
  DetectionResult? _detection;
  int? _selectedBodyNodeIndex;
  int? _selectedNodeIndex;

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
    _isTestDriveMode = widget.startInTestDrive;
    if (_isTestDriveMode) _activeStep = 5;
    final car = widget.initialCar;
    if (car != null) {
      _modelName = '${car.name} (Pre-rigged)';
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

      if (car.wheelPositions.length >= 4) {
        _assignedWheels['FL'] = DetectedWheel(
          nodeIndex: 0,
          nodeName: 'Wheel_FL',
          worldPosition: car.wheelPositions[0],
          confidence: 1.0,
          axle: 'front',
          side: 'left',
        );
        _assignedWheels['FR'] = DetectedWheel(
          nodeIndex: 1,
          nodeName: 'Wheel_FR',
          worldPosition: car.wheelPositions[1],
          confidence: 1.0,
          axle: 'front',
          side: 'right',
        );
        _assignedWheels['RL'] = DetectedWheel(
          nodeIndex: 2,
          nodeName: 'Wheel_RL',
          worldPosition: car.wheelPositions[2],
          confidence: 1.0,
          axle: 'rear',
          side: 'left',
        );
        _assignedWheels['RR'] = DetectedWheel(
          nodeIndex: 3,
          nodeName: 'Wheel_RR',
          worldPosition: car.wheelPositions[3],
          confidence: 1.0,
          axle: 'rear',
          side: 'right',
        );

        _detection = DetectionResult(
          wheels: _assignedWheels.values.whereType<DetectedWheel>().toList(),
          body: null,
          suggestedDrive: car.drive,
          suggestedPreset: car.name,
          warnings: const [],
        );
      }
      _activeStep = 1;
    }
  }

  Future<void> _pickModel() async {
    try {
      final picked = await pickModelFile();
      if (!mounted || picked == null) return;

      setState(() {
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
          _detection = null;
          _selectedBodyNodeIndex = null;

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
        _showMessage('Loaded ${picked.name} (procedural fallback)');
      }
    } catch (e) {
      _showMessage('Error parsing model: $e');
    }
  }

  void _autoRigModel() {
    final model = _parsedModel;
    if (model == null) {
      _pickModel();
      return;
    }

    final detection = AutoDetector.detect(model);
    setState(() {
      _detection = detection;
      _selectedBodyNodeIndex = detection.body?.nodeIndex;
      _drive = detection.suggestedDrive;
      _mapDetectedWheels(detection.wheels);
      _activeStep = 1;
    });
    _showMessage(
      'Model processed: ${detection.wheels.length}/4 wheels detected.',
    );
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
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF25343E),
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

  void _selectStep(int step) {
    setState(() {
      _activeStep = step;
      if (step == 5) {
        _isTestDriveMode = true;
      } else {
        _isTestDriveMode = false;
        _isDriveFullscreen = false;
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
                  onAutoRig: _autoRigModel,
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
                        width: _showLeftPanel ? 232 : 0,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          color: Color(0xFF111714),
                          border: Border(
                            right: BorderSide(color: Color(0xFF223127)),
                          ),
                        ),
                        child: OverflowBox(
                          minWidth: 232,
                          maxWidth: 232,
                          alignment: Alignment.topLeft,
                          child: _DesktopSidebar(
                            activeStep: _activeStep,
                            onStepSelected: _selectStep,
                            hasModel: _parsedModel != null,
                            isTestDrive: _isTestDriveMode,
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
                              onAutoRig: _autoRigModel,
                              wheelsCount: _detection?.wheels.length ?? 0,
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
                                                  onNodeSelected: (idx) {
                                                    setState(
                                                      () => _selectedNodeIndex =
                                                          idx,
                                                    );
                                                  },
                                                  accentColor: _preset.accent,
                                                  bodyColor: widget.initialCar?.accentColor ??
                                                      const Color(0xFFD6DBDF),
                                                  centerOfMassY: _centerOfMass,
                                                  onTestDrive: _enterTestDrive,
                                                ),
                                              ),
                                              if (_showRightPanel) ...[
                                                const SizedBox(width: 18),
                                                // Right sidepanel (content removed as requested)
                                                SizedBox(
                                                  width: 340,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xC00D1511),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: const Color(0xFF1E2B22),
                                                      ),
                                                    ),
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
                                            onNodeSelected: (idx) {
                                              setState(
                                                () => _selectedNodeIndex =
                                                    idx,
                                              );
                                            },
                                            accentColor: _preset.accent,
                                            bodyColor: widget.initialCar?.accentColor ??
                                                const Color(0xFFD6DBDF),
                                            centerOfMassY: _centerOfMass,
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
    return _InspectorPanel(
      activeStep: _activeStep,
      preset: _preset,
      modelName: _modelName,
      parsedModel: _parsedModel,
      detection: _detection,
      selectedBodyNodeIndex: _selectedBodyNodeIndex,
      assignedWheels: _assignedWheels,
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
      onPickModel: _pickModel,
      onAutoRig: _autoRigModel,
      onReassignWheel: _reassignWheel,
      onSelectBody: _selectBody,
      onPresetChanged: (value) {
        setState(() => _preset = value);
      },
      onDriveChanged: (value) {
        setState(() => _drive = value);
      },
      onMassChanged: (value) {
        setState(() => _mass = value);
      },
      onEngineForceChanged: (value) {
        setState(() => _engineForce = value);
      },
      onGripChanged: (value) {
        setState(() => _grip = value);
      },
      onSuspensionChanged: (value) {
        setState(() => _suspension = value);
      },
      onCenterOfMassChanged: (value) {
        setState(() => _centerOfMass = value);
      },
      onFrontSteeringChanged: (value) {
        setState(() => _frontSteering = value);
      },
      onRearSteeringChanged: (value) {
        setState(() => _rearSteering = value);
      },
      onFrontTractionChanged: (value) {
        setState(() => _frontTraction = value);
      },
      onRearTractionChanged: (value) {
        setState(() => _rearTraction = value);
      },
      onExport: _exportGodotFiles,
      canExport: _exportBlockReason == null,
      exportBlockReason: _exportBlockReason,
      onStepSelected: _selectStep,
      onTestDrive: _enterTestDrive,
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
    required this.onToggleCollapse,
  });

  final int activeStep;
  final ValueChanged<int> onStepSelected;
  final bool hasModel;
  final bool isTestDrive;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      padding: const EdgeInsets.fromLTRB(18, 22, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF111714),
        border: Border(right: BorderSide(color: Color(0xFF223127))),
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
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RigHomeScreen()),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1A231E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF223127)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: Color(0xFF34D399),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Fleet Library',
                    style: TextStyle(
                      color: Color(0xFFC9D1D9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SmallLabel('RIGGING PIPELINE'),
          const SizedBox(height: 10),
          _SidebarStep(
            number: 1,
            title: 'Upload',
            subtitle: 'Import 3D model (.glb, .gltf)',
            active: true,
            complete: hasModel,
            onTap: () => onStepSelected(1),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161F1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF223127)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF86978C),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasModel
                        ? 'Model parsed. Review hub alignment in 3D viewport.'
                        : 'Import a vehicle model to inspect wheels and body.',
                    style: const TextStyle(
                      color: Color(0xFF86978C),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'GODOT 4 VEHICLE PIPELINE',
            style: TextStyle(
              color: Color(0xFF6E7681),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Topbar ──────────────────────────────────────────────────────────────────

class _DesktopTopbar extends StatelessWidget {
  const _DesktopTopbar({
    required this.modelName,
    required this.onExport,
    required this.onAutoRig,
    required this.wheelsCount,
    required this.isTestDrive,
    required this.onToggleTestDrive,
    required this.isLeftPanelOpen,
    required this.onToggleLeftPanel,
    required this.isRightPanelOpen,
    required this.onToggleRightPanel,
  });

  final String modelName;
  final VoidCallback onExport;
  final VoidCallback onAutoRig;
  final int wheelsCount;
  final bool isTestDrive;
  final VoidCallback onToggleTestDrive;
  final bool isLeftPanelOpen;
  final VoidCallback onToggleLeftPanel;
  final bool isRightPanelOpen;
  final VoidCallback onToggleRightPanel;

  @override
  Widget build(BuildContext context) {
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
              color: const Color(0xFF1A231E),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF223127)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: wheelsCount >= 4
                      ? const Color(0xFF10B981)
                      : const Color(0xFFD29922),
                ),
                const SizedBox(width: 5),
                Text(
                  wheelsCount >= 4 ? 'AUTO-RIGGED' : 'MANUAL ASSIST',
                  style: TextStyle(
                    color: wheelsCount >= 4
                        ? const Color(0xFF10B981)
                        : const Color(0xFFD29922),
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
          IconButton.filledTonal(
            onPressed: onAutoRig,
            tooltip: 'Auto-rig vehicle',
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            color: const Color(0xFF10B981),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
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
    required this.onAutoRig,
    required this.isTestDrive,
    required this.onToggleTestDrive,
  });
  final VoidCallback onExport;
  final VoidCallback onAutoRig;
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
            onPressed: onAutoRig,
            tooltip: 'Auto-rig vehicle',
            icon: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF10B981),
            ),
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
  const _StepStrip({required this.activeStep, required this.onStepSelected});
  final int activeStep;
  final ValueChanged<int> onStepSelected;

  @override
  Widget build(BuildContext context) {
    if (workflowSteps.length <= 1) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (final step in workflowSteps) ...[
            ChoiceChip(
              label: Text('${step.number}  ${step.title}'),
              selected: activeStep == step.number,
              onSelected: (_) => onStepSelected(step.number),
              showCheckmark: false,
              backgroundColor: const Color(0xFF111714),
              selectedColor: const Color(0xFF10B981),
              side: const BorderSide(color: Color(0xFF223127)),
              labelStyle: TextStyle(
                color: activeStep == step.number
                    ? const Color(0xFF062319)
                    : const Color(0xFF9AA7AF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ── Inspector Panel Dispatcher ──────────────────────────────────────────────

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.activeStep,
    required this.preset,
    required this.modelName,
    required this.parsedModel,
    required this.detection,
    required this.selectedBodyNodeIndex,
    required this.assignedWheels,
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
    required this.onPickModel,
    required this.onAutoRig,
    required this.onReassignWheel,
    required this.onSelectBody,
    required this.onPresetChanged,
    required this.onDriveChanged,
    required this.onMassChanged,
    required this.onEngineForceChanged,
    required this.onGripChanged,
    required this.onSuspensionChanged,
    required this.onCenterOfMassChanged,
    required this.onFrontSteeringChanged,
    required this.onRearSteeringChanged,
    required this.onFrontTractionChanged,
    required this.onRearTractionChanged,
    required this.onExport,
    required this.canExport,
    required this.exportBlockReason,
    required this.onStepSelected,
    required this.onTestDrive,
  });

  final int activeStep;
  final RigPreset preset;
  final String modelName;
  final ParsedModel? parsedModel;
  final DetectionResult? detection;
  final int? selectedBodyNodeIndex;
  final Map<String, DetectedWheel?> assignedWheels;
  final String drive;
  final double mass;
  final double engineForce;
  final double grip;
  final double suspension;
  final double centerOfMass;
  final bool frontSteering;
  final bool rearSteering;
  final bool frontTraction;
  final bool rearTraction;
  final VoidCallback onPickModel;
  final VoidCallback onAutoRig;
  final void Function(String slot, int? nodeIndex) onReassignWheel;
  final ValueChanged<int?> onSelectBody;
  final ValueChanged<RigPreset> onPresetChanged;
  final ValueChanged<String> onDriveChanged;
  final ValueChanged<double> onMassChanged;
  final ValueChanged<double> onEngineForceChanged;
  final ValueChanged<double> onGripChanged;
  final ValueChanged<double> onSuspensionChanged;
  final ValueChanged<double> onCenterOfMassChanged;
  final ValueChanged<bool> onFrontSteeringChanged;
  final ValueChanged<bool> onRearSteeringChanged;
  final ValueChanged<bool> onFrontTractionChanged;
  final ValueChanged<bool> onRearTractionChanged;
  final VoidCallback onExport;
  final bool canExport;
  final String? exportBlockReason;
  final ValueChanged<int> onStepSelected;
  final VoidCallback onTestDrive;

  @override
  Widget build(BuildContext context) {
    // Content of right sidepanel removed as requested
    return const SizedBox.shrink();
  }
}

class _SidebarStep extends StatelessWidget {
  const _SidebarStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.complete,
    required this.onTap,
  });
  final int number;
  final String title;
  final String subtitle;
  final bool active;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF15261C) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xFF10B981) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF10B981)
                      : const Color(0xFF1C2720),
                  shape: BoxShape.circle,
                ),
                child: complete
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : Text(
                        '$number',
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF041D14)
                              : const Color(0xFF97A5AD),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFFC4CED3),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF71818B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF34D399),
                  size: 17,
                ),
            ],
          ),
        ),
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
