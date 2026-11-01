import 'dart:convert';

import 'package:flutter/material.dart';

import 'auto_detector.dart';
import 'download_config.dart';
import 'file_picker.dart';
import 'glb_parser.dart';
import 'home_screen.dart';
import 'model_data.dart';
import 'pre_rigged_cars.dart';
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
        scaffoldBackgroundColor: const Color(0xFF0E151B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF713D),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFFF713D),
          onPrimary: Colors.white,
          surface: const Color(0xFF172129),
          onSurface: ink,
        ),
        fontFamily: 'Arial',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111A21),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2C3A44)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2C3A44)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFF713D)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF91A0AA), fontSize: 12),
          suffixStyle: const TextStyle(color: Color(0xFF91A0AA), fontSize: 12),
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
  const RigWorkbenchPage({super.key, this.initialCar});

  final PreRiggedCar? initialCar;

  @override
  State<RigWorkbenchPage> createState() => _RigWorkbenchPageState();
}

class _RigWorkbenchPageState extends State<RigWorkbenchPage> {
  int _activeStep = 1;
  RigPreset _preset = presets.first;
  String _modelName = 'No model loaded';
  ParsedModel? _parsedModel;
  DetectionResult? _detection;
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
      }
      _activeStep = 3; // Jump straight to physics tuning
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
        final parsed = GlbParser.parse(picked.name, picked.bytes);
        final detection = AutoDetector.detect(parsed);

        setState(() {
          _parsedModel = parsed;
          _detection = detection;
          _drive = detection.suggestedDrive;

          // Find preset matching suggestion
          final matched = presets.firstWhere(
            (p) => p.name == detection.suggestedPreset,
            orElse: () => presets.first,
          );
          _preset = matched;

          // Estimate mass from volume
          final size = parsed.worldBBox.size;
          final vol = (size.x.abs() * size.y.abs() * size.z.abs())
              .clamp(2.0, 30.0);
          _mass = (vol * 140.0).clamp(600.0, 2800.0).roundToDouble();

          // Map detected wheels
          _mapDetectedWheels(detection.wheels);

          // Auto-advance to review step
          _activeStep = 2;
        });

        _showMessage(
          'Model parsed: ${parsed.nodes.length} nodes, '
          '${detection.wheels.length}/4 wheels detected',
        );
      } else {
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
      final key = '${w.axle == 'front' ? 'F' : 'R'}${w.side == 'left' ? 'L' : 'R'}';
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
        worldPosition: node.worldTransform.translation,
        confidence: 1.0, // Human confirmed
        meshIndex: node.meshIndex,
        axle: axle,
        side: side,
      );
      _selectedNodeIndex = node.index;
    });
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
    );
  }

  Future<void> _exportGodotFiles() async {
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

  void _selectStep(int step) {
    setState(() => _activeStep = step);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1120;
          final tablet = constraints.maxWidth >= 760;
          return Column(
            children: [
              if (!desktop) _MobileHeader(onExport: _exportGodotFiles),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (desktop)
                      _DesktopSidebar(
                        activeStep: _activeStep,
                        onStepSelected: _selectStep,
                        hasModel: _parsedModel != null,
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (desktop)
                            _DesktopTopbar(
                              modelName: _modelName,
                              onExport: _exportGodotFiles,
                              wheelsCount: _detection?.wheels.length ?? 0,
                            ),
                          if (!desktop)
                            _StepStrip(
                              activeStep: _activeStep,
                              onStepSelected: _selectStep,
                            ),
                          Expanded(
                            child: tablet && desktop
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
                                            detection: _detection,
                                            selectedNodeIndex:
                                                _selectedNodeIndex,
                                            onNodeSelected: (idx) {
                                              setState(() =>
                                                  _selectedNodeIndex = idx);
                                            },
                                            accentColor: _preset.accent,
                                            centerOfMassY: _centerOfMass,
                                          ),
                                        ),
                                        const SizedBox(width: 18),
                                        // Right side inspector panel with independent scroll
                                        SizedBox(
                                          width: 380,
                                          child: Scrollbar(
                                            thumbVisibility: true,
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                                bottom: 24,
                                              ),
                                              child: _buildInspector(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      28,
                                    ),
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: 380,
                                          child: WireframeViewer(
                                            model: _parsedModel,
                                            detection: _detection,
                                            selectedNodeIndex:
                                                _selectedNodeIndex,
                                            onNodeSelected: (idx) {
                                              setState(() =>
                                                  _selectedNodeIndex = idx);
                                            },
                                            accentColor: _preset.accent,
                                            centerOfMassY: _centerOfMass,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildInspector(),
                                      ],
                                    ),
                                  ),
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
      onReassignWheel: _reassignWheel,
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
      onStepSelected: _selectStep,
    );
  }
}

// ── Desktop Sidebar ─────────────────────────────────────────────────────────

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.activeStep,
    required this.onStepSelected,
    required this.hasModel,
  });

  final int activeStep;
  final ValueChanged<int> onStepSelected;
  final bool hasModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      padding: const EdgeInsets.fromLTRB(18, 22, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF121B22),
        border: Border(right: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Brand(),
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
                color: const Color(0xFF19252E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2B3A44)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.arrow_back_rounded, size: 14, color: Color(0xFFFF986D)),
                  SizedBox(width: 8),
                  Text(
                    'Fleet Library',
                    style: TextStyle(
                      color: Color(0xFFD4DFE5),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SmallLabel('MIXAMO AUTO-RIGGER'),
          const SizedBox(height: 10),
          _SidebarStep(
            number: 1,
            title: 'Upload & Scan',
            subtitle: 'Auto-parse GLB/glTF',
            active: activeStep == 1,
            complete: activeStep > 1,
            onTap: () => onStepSelected(1),
          ),
          _SidebarStep(
            number: 2,
            title: 'Review Detections',
            subtitle: 'Human-assist rigging',
            active: activeStep == 2,
            complete: activeStep > 2,
            onTap: () => onStepSelected(2),
          ),
          _SidebarStep(
            number: 3,
            title: 'Tune physics',
            subtitle: 'Mass & suspension',
            active: activeStep == 3,
            complete: activeStep > 3,
            onTap: () => onStepSelected(3),
          ),
          _SidebarStep(
            number: 4,
            title: 'Export to Godot',
            subtitle: 'Real wheel positions',
            active: activeStep == 4,
            complete: false,
            onTap: () => onStepSelected(4),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2831),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A3B46)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFFB15C),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasModel
                        ? 'Auto-scan complete. Review markers in 3D wireframe.'
                        : 'Drop a GLB car model to auto-detect wheels and body.',
                    style: const TextStyle(
                      color: Color(0xFFB5C0C7),
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
            'v2.0 AUTO-RIG  •  GODOT 4',
            style: TextStyle(
              color: Color(0xFF61707A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
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
    required this.wheelsCount,
  });

  final String modelName;
  final VoidCallback onExport;
  final int wheelsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF10181E),
        border: Border(bottom: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Fleet Library',
            icon: const Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFFBAC7CE)),
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
          const SizedBox(width: 8),
          const Text(
            'CAR RIGGER',
            style: TextStyle(
              color: Color(0xFFEEF2F4),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: wheelsCount >= 4
                  ? const Color(0xFF1E392F)
                  : const Color(0xFF3B2E1E),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              wheelsCount >= 4 ? 'AUTO-RIGGED' : 'MANUAL ASSIST',
              style: TextStyle(
                color: wheelsCount >= 4
                    ? const Color(0xFF6BD2A0)
                    : const Color(0xFFFFB15C),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              modelName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF82919B), fontSize: 12),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('Export Godot rig'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE8EEF1),
              side: const BorderSide(color: Color(0xFF3A4B56)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile Header & Strip ───────────────────────────────────────────────────

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.onExport});
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF10181E),
        border: Border(bottom: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Fleet Library',
            icon: const Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFFBAC7CE)),
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
              backgroundColor: const Color(0xFF172129),
              selectedColor: const Color(0xFFFF713D),
              side: const BorderSide(color: Color(0xFF2C3A44)),
              labelStyle: TextStyle(
                color: activeStep == step.number
                    ? Colors.white
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
    required this.onReassignWheel,
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
    required this.onStepSelected,
  });

  final int activeStep;
  final RigPreset preset;
  final String modelName;
  final ParsedModel? parsedModel;
  final DetectionResult? detection;
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
  final void Function(String slot, int? nodeIndex) onReassignWheel;
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
  final ValueChanged<int> onStepSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workflowSteps[activeStep - 1].title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 3),
        Text(
          workflowSteps[activeStep - 1].subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        switch (activeStep) {
          1 => _UploadScanInspector(
              modelName: modelName,
              parsedModel: parsedModel,
              detection: detection,
              preset: preset,
              onPickModel: onPickModel,
              onPresetChanged: onPresetChanged,
              onNextStep: () => onStepSelected(2),
            ),
          2 => _ReviewRigInspector(
              parsedModel: parsedModel,
              detection: detection,
              assignedWheels: assignedWheels,
              onReassignWheel: onReassignWheel,
              drive: drive,
              onDriveChanged: onDriveChanged,
              frontSteering: frontSteering,
              rearSteering: rearSteering,
              frontTraction: frontTraction,
              rearTraction: rearTraction,
              onFrontSteeringChanged: onFrontSteeringChanged,
              onRearSteeringChanged: onRearSteeringChanged,
              onFrontTractionChanged: onFrontTractionChanged,
              onRearTractionChanged: onRearTractionChanged,
              onNextStep: () => onStepSelected(3),
            ),
          3 => _PhysicsInspector(
              mass: mass,
              engineForce: engineForce,
              grip: grip,
              suspension: suspension,
              centerOfMass: centerOfMass,
              onMassChanged: onMassChanged,
              onEngineForceChanged: onEngineForceChanged,
              onGripChanged: onGripChanged,
              onSuspensionChanged: onSuspensionChanged,
              onCenterOfMassChanged: onCenterOfMassChanged,
              onNextStep: () => onStepSelected(4),
            ),
          _ => _ExportInspector(onExport: onExport),
        },
      ],
    );
  }
}

// ── Step 1: Upload & Scan Inspector ─────────────────────────────────────────

class _UploadScanInspector extends StatelessWidget {
  const _UploadScanInspector({
    required this.modelName,
    required this.parsedModel,
    required this.detection,
    required this.preset,
    required this.onPickModel,
    required this.onPresetChanged,
    required this.onNextStep,
  });

  final String modelName;
  final ParsedModel? parsedModel;
  final DetectionResult? detection;
  final RigPreset preset;
  final VoidCallback onPickModel;
  final ValueChanged<RigPreset> onPresetChanged;
  final VoidCallback onNextStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.auto_awesome,
                title: 'Mixamo-Style Auto-Rig',
                subtitle: 'Drop any 3D car model (.glb, .gltf)',
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onPickModel,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10191F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: parsedModel != null
                          ? const Color(0xFF6BD2A0)
                          : const Color(0xFF3A4A55),
                      width: 1.3,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        parsedModel != null
                            ? Icons.check_circle_outline_rounded
                            : Icons.cloud_upload_outlined,
                        color: parsedModel != null
                            ? const Color(0xFF6BD2A0)
                            : const Color(0xFFFF713D),
                        size: 32,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        modelName == 'No model loaded'
                            ? 'Drop .glb / .gltf or click to browse'
                            : modelName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFE7EEF1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        parsedModel != null
                            ? '${parsedModel!.nodes.length} nodes • ${parsedModel!.meshes.length} meshes'
                            : 'glTF 2.0 binary container with car geometry',
                        style: const TextStyle(
                          color: Color(0xFF82919B),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: onPickModel,
                        icon: const Icon(Icons.file_open_rounded, size: 16),
                        label: Text(parsedModel != null
                            ? 'Choose another model'
                            : 'Upload & Auto-Scan'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF713D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (detection != null) ...[
          const SizedBox(height: 12),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelTitle(
                  icon: Icons.radar_rounded,
                  title: 'Scan Results',
                  subtitle: 'Auto-detected vehicle topology',
                ),
                const SizedBox(height: 12),
                _DetectionMetric(
                  label: 'Wheels detected',
                  value: '${detection!.wheels.length} / 4',
                  isGood: detection!.wheels.length >= 4,
                ),
                const SizedBox(height: 6),
                _DetectionMetric(
                  label: 'Car Body',
                  value: detection!.body?.nodeName ?? 'Manual Selection Needed',
                  isGood: detection!.body != null,
                ),
                const SizedBox(height: 6),
                _DetectionMetric(
                  label: 'Suggested Drive',
                  value: detection!.suggestedDrive,
                  isGood: true,
                ),
                const SizedBox(height: 6),
                _DetectionMetric(
                  label: 'Suggested Preset',
                  value: detection!.suggestedPreset,
                  isGood: true,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onNextStep,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Review Detections (Human Assist)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.tune_rounded,
                title: 'Geometry Preset',
                subtitle: 'Vehicle archetype template',
              ),
              const SizedBox(height: 12),
              for (final item in presets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PresetTile(
                    preset: item,
                    selected: item == preset,
                    onTap: () => onPresetChanged(item),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 2: Review & Human Assist Inspector ─────────────────────────────────

class _ReviewRigInspector extends StatelessWidget {
  const _ReviewRigInspector({
    required this.parsedModel,
    required this.detection,
    required this.assignedWheels,
    required this.onReassignWheel,
    required this.drive,
    required this.onDriveChanged,
    required this.frontSteering,
    required this.rearSteering,
    required this.frontTraction,
    required this.rearTraction,
    required this.onFrontSteeringChanged,
    required this.onRearSteeringChanged,
    required this.onFrontTractionChanged,
    required this.onRearTractionChanged,
    required this.onNextStep,
  });

  final ParsedModel? parsedModel;
  final DetectionResult? detection;
  final Map<String, DetectedWheel?> assignedWheels;
  final void Function(String slot, int? nodeIndex) onReassignWheel;
  final String drive;
  final ValueChanged<String> onDriveChanged;
  final bool frontSteering;
  final bool rearSteering;
  final bool frontTraction;
  final bool rearTraction;
  final ValueChanged<bool> onFrontSteeringChanged;
  final ValueChanged<bool> onRearSteeringChanged;
  final ValueChanged<bool> onFrontTractionChanged;
  final ValueChanged<bool> onRearTractionChanged;
  final VoidCallback onNextStep;

  @override
  Widget build(BuildContext context) {
    final nodes = parsedModel?.nodes ?? [];
    final meshNodes = nodes.where((n) => n.meshIndex != null).toList();

    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.pan_tool_alt_rounded,
                title: 'Human-Assist Wheel Assignment',
                subtitle: 'Confirm or reassign auto-detected wheels',
              ),
              const SizedBox(height: 12),
              for (final slot in ['FL', 'FR', 'RL', 'RR'])
                _WheelAssignmentTile(
                  slot: slot,
                  wheel: assignedWheels[slot],
                  availableNodes: meshNodes,
                  onSelected: (nodeIdx) => onReassignWheel(slot, nodeIdx),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.settings_ethernet_rounded,
                title: 'Drivetrain & Axles',
                subtitle: 'Configure steering and power distribution',
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'FWD', label: Text('FWD')),
                  ButtonSegment(value: 'RWD', label: Text('RWD')),
                  ButtonSegment(value: 'AWD', label: Text('AWD')),
                ],
                selected: {drive},
                onSelectionChanged: (value) => onDriveChanged(value.first),
              ),
              const SizedBox(height: 14),
              _WheelRow(
                label: 'Front axle',
                nodeName: 'FL + FR wheels',
                steering: frontSteering,
                traction: frontTraction,
                onSteeringChanged: onFrontSteeringChanged,
                onTractionChanged: onFrontTractionChanged,
              ),
              const SizedBox(height: 8),
              _WheelRow(
                label: 'Rear axle',
                nodeName: 'RL + RR wheels',
                steering: rearSteering,
                traction: rearTraction,
                onSteeringChanged: onRearSteeringChanged,
                onTractionChanged: onRearTractionChanged,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNextStep,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Proceed to Tune Physics'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF713D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WheelAssignmentTile extends StatelessWidget {
  const _WheelAssignmentTile({
    required this.slot,
    required this.wheel,
    required this.availableNodes,
    required this.onSelected,
  });

  final String slot;
  final DetectedWheel? wheel;
  final List<SceneNode> availableNodes;
  final ValueChanged<int?> onSelected;

  String get _title {
    switch (slot) {
      case 'FL':
        return 'Front Left (FL)';
      case 'FR':
        return 'Front Right (FR)';
      case 'RL':
        return 'Rear Left (RL)';
      case 'RR':
        return 'Rear Right (RR)';
      default:
        return slot;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111A21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: wheel != null
              ? const Color(0xFF2C3E4C)
              : const Color(0xFF5A3030),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF213642),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  slot,
                  style: const TextStyle(
                    color: Color(0xFFFFB15C),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _title,
                style: const TextStyle(
                  color: Color(0xFFE2E9EC),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (wheel != null)
                Text(
                  '${(wheel!.confidence * 100).toInt()}% conf.',
                  style: TextStyle(
                    color: wheel!.confidence >= 0.8
                        ? const Color(0xFF6BD2A0)
                        : const Color(0xFFFFB15C),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                const Text(
                  'Unassigned',
                  style: TextStyle(color: Color(0xFFE86F6F), fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (availableNodes.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: wheel?.nodeIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: availableNodes.map((node) {
                final pos = node.worldTransform.translation;
                return DropdownMenuItem<int>(
                  value: node.index,
                  child: Text(
                    '${node.name} (${pos.x.toStringAsFixed(2)}, ${pos.y.toStringAsFixed(2)}, ${pos.z.toStringAsFixed(2)})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
              onChanged: onSelected,
            )
          else
            Text(
              wheel?.nodeName ?? 'No nodes found in model',
              style: const TextStyle(color: Color(0xFF8FA0AA), fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ── Step 3: Physics Inspector ───────────────────────────────────────────────

class _PhysicsInspector extends StatelessWidget {
  const _PhysicsInspector({
    required this.mass,
    required this.engineForce,
    required this.grip,
    required this.suspension,
    required this.centerOfMass,
    required this.onMassChanged,
    required this.onEngineForceChanged,
    required this.onGripChanged,
    required this.onSuspensionChanged,
    required this.onCenterOfMassChanged,
    required this.onNextStep,
  });

  final double mass;
  final double engineForce;
  final double grip;
  final double suspension;
  final double centerOfMass;
  final ValueChanged<double> onMassChanged;
  final ValueChanged<double> onEngineForceChanged;
  final ValueChanged<double> onGripChanged;
  final ValueChanged<double> onSuspensionChanged;
  final ValueChanged<double> onCenterOfMassChanged;
  final VoidCallback onNextStep;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.speed_rounded,
            title: 'Vehicle Physics',
            subtitle: 'Fine-tune values for Godot VehicleBody3D',
          ),
          const SizedBox(height: 14),
          _SliderField(
            label: 'Mass',
            value: mass,
            min: 400,
            max: 2800,
            suffix: ' kg',
            divisions: 48,
            onChanged: onMassChanged,
          ),
          _SliderField(
            label: 'Engine force',
            value: engineForce,
            min: 50,
            max: 800,
            suffix: ' N',
            divisions: 75,
            onChanged: onEngineForceChanged,
          ),
          _SliderField(
            label: 'Tire grip',
            value: grip,
            min: 0.2,
            max: 2.0,
            suffix: '',
            divisions: 18,
            onChanged: onGripChanged,
          ),
          _SliderField(
            label: 'Suspension stiffness',
            value: suspension,
            min: 1,
            max: 12,
            suffix: '',
            divisions: 22,
            onChanged: onSuspensionChanged,
          ),
          _SliderField(
            label: 'Center of mass height',
            value: centerOfMass,
            min: -0.5,
            max: 0.4,
            suffix: ' m',
            divisions: 18,
            onChanged: onCenterOfMassChanged,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNextStep,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Proceed to Export'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF713D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 4: Export Inspector ────────────────────────────────────────────────

class _ExportInspector extends StatelessWidget {
  const _ExportInspector({required this.onExport});
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.rocket_launch_outlined,
            title: 'Godot 4 Rig Package',
            subtitle: 'Exported with real wheel positions',
          ),
          const SizedBox(height: 16),
          const _ExportFile(
            icon: Icons.account_tree_outlined,
            name: 'rig_car.tscn',
            detail: 'VehicleBody3D with real wheel 3D coordinates',
          ),
          const _ExportFile(
            icon: Icons.code_rounded,
            name: 'rig_car.gd',
            detail: 'Input + engine controller script',
          ),
          const _ExportFile(
            icon: Icons.data_object_rounded,
            name: 'rig_car_config.json',
            detail: 'Editable rig settings & telemetry',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Download Godot Rig Files'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF713D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers & Reusable Widgets ──────────────────────────────────────────────

class _DetectionMetric extends StatelessWidget {
  const _DetectionMetric({
    required this.label,
    required this.value,
    required this.isGood,
  });

  final String label;
  final String value;
  final bool isGood;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isGood ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 14,
          color: isGood ? const Color(0xFF6BD2A0) : const Color(0xFFFFB15C),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8FA0AA), fontSize: 11),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isGood ? const Color(0xFFE2E9EC) : const Color(0xFFFFB15C),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF172129),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF293943)),
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2524),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: const Color(0xFFFF986D), size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  final RigPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2B2422) : const Color(0xFF111A21),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? const Color(0xFFFF713D) : const Color(0xFF2B3A44),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: preset.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: const TextStyle(
                      color: Color(0xFFE5ECEF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.description,
                    style: const TextStyle(
                      color: Color(0xFF83919A),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFFF713D),
                size: 17,
              ),
          ],
        ),
      ),
    );
  }
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    required this.label,
    required this.nodeName,
    required this.steering,
    required this.traction,
    required this.onSteeringChanged,
    required this.onTractionChanged,
  });
  final String label;
  final String nodeName;
  final bool steering;
  final bool traction;
  final ValueChanged<bool> onSteeringChanged;
  final ValueChanged<bool> onTractionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111A21),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFE2E9EC),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nodeName,
                  style: const TextStyle(color: Color(0xFF71818B), fontSize: 9),
                ),
              ],
            ),
          ),
          const Text('Steer', style: TextStyle(fontSize: 10)),
          Switch(
            value: steering,
            onChanged: onSteeringChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFFFF713D),
          ),
          const SizedBox(width: 4),
          const Text('Drive', style: TextStyle(fontSize: 10)),
          Switch(
            value: traction,
            onChanged: onTractionChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFFFF713D),
          ),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final valueText = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFFD5DEE2), fontSize: 12),
            ),
            const Spacer(),
            Text(
              '$valueText$suffix',
              style: const TextStyle(
                color: Color(0xFFFF986D),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: const Color(0xFFFF713D),
          inactiveColor: const Color(0xFF30414B),
        ),
      ],
    );
  }
}

class _ExportFile extends StatelessWidget {
  const _ExportFile({
    required this.icon,
    required this.name,
    required this.detail,
  });
  final IconData icon;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF986D), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFE1E9EC),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF7F8F99),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_rounded, color: Color(0xFF6BD2A0), size: 17),
        ],
      ),
    );
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
            color: active ? const Color(0xFF2A2422) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xFFFF713D) : Colors.transparent,
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
                      ? const Color(0xFFFF713D)
                      : const Color(0xFF26343D),
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
                              ? Colors.white
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
                  color: Color(0xFFFF986D),
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFFF713D),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 9),
        const Text(
          'RIG-CAR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
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
  WorkflowStep(number: 1, title: 'Upload & Scan', subtitle: 'Auto-detect GLB'),
  WorkflowStep(
      number: 2, title: 'Review Rig', subtitle: 'Human-assist markers'),
  WorkflowStep(
      number: 3, title: 'Tune physics', subtitle: 'Mass & suspension'),
  WorkflowStep(
    number: 4,
    title: 'Export to Godot',
    subtitle: 'Scene + script + config',
  ),
];

const presets = [
  RigPreset(
    name: 'Sports coupe',
    description: 'Low, fast, rear-biased',
    accent: Color(0xFFFF6E4D),
    secondary: Color(0xFFB92D3F),
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
