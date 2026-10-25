import 'dart:convert';

import 'package:flutter/material.dart';

import 'download_config.dart';
import 'file_picker.dart';

void main() {
  runApp(const RigCarApp());
}

class RigCarApp extends StatelessWidget {
  const RigCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFE9EEF2);
    return MaterialApp(
      title: 'RIG-CAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E151B),
        colorScheme:
            ColorScheme.fromSeed(
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
            fontSize: 21,
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
      home: const RigWorkbenchPage(),
    );
  }
}

class RigWorkbenchPage extends StatefulWidget {
  const RigWorkbenchPage({super.key});

  @override
  State<RigWorkbenchPage> createState() => _RigWorkbenchPageState();
}

class _RigWorkbenchPageState extends State<RigWorkbenchPage> {
  int _activeStep = 1;
  RigPreset _preset = presets.first;
  String _modelName = 'No model loaded';
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

  Future<void> _pickModel() async {
    final pickedName = await pickModelFile();
    if (!mounted || pickedName == null) return;
    setState(() => _modelName = pickedName);
    _showMessage('Loaded $pickedName');
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

  RigConfig get _config => RigConfig(
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
  );

  Future<void> _exportGodotFiles() async {
    final config = _config;
    await downloadTextFile(
      'rig_car_config.json',
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      'application/json',
    );
    await downloadTextFile('rig_car.gd', config.toGdScript(), 'text/plain');
    await downloadTextFile('rig_car.tscn', config.toTscn(), 'text/plain');
    if (mounted) _showMessage('Exported Godot rig files');
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
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (desktop)
                            _DesktopTopbar(
                              modelName: _modelName,
                              onExport: _exportGodotFiles,
                            ),
                          if (!desktop)
                            _StepStrip(
                              activeStep: _activeStep,
                              onStepSelected: _selectStep,
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                desktop ? 26 : 16,
                                desktop ? 22 : 16,
                                desktop ? 26 : 16,
                                28,
                              ),
                              child: tablet && desktop
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _PreviewPanel(
                                            preset: _preset,
                                            modelName: _modelName,
                                          ),
                                        ),
                                        const SizedBox(width: 18),
                                        SizedBox(
                                          width: 348,
                                          child: _InspectorPanel(
                                            activeStep: _activeStep,
                                            preset: _preset,
                                            modelName: _modelName,
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
                                              setState(
                                                () => _engineForce = value,
                                              );
                                            },
                                            onGripChanged: (value) {
                                              setState(() => _grip = value);
                                            },
                                            onSuspensionChanged: (value) {
                                              setState(
                                                () => _suspension = value,
                                              );
                                            },
                                            onCenterOfMassChanged: (value) {
                                              setState(
                                                () => _centerOfMass = value,
                                              );
                                            },
                                            onFrontSteeringChanged: (value) {
                                              setState(
                                                () => _frontSteering = value,
                                              );
                                            },
                                            onRearSteeringChanged: (value) {
                                              setState(
                                                () => _rearSteering = value,
                                              );
                                            },
                                            onFrontTractionChanged: (value) {
                                              setState(
                                                () => _frontTraction = value,
                                              );
                                            },
                                            onRearTractionChanged: (value) {
                                              setState(
                                                () => _rearTraction = value,
                                              );
                                            },
                                            onExport: _exportGodotFiles,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _PreviewPanel(
                                          preset: _preset,
                                          modelName: _modelName,
                                        ),
                                        const SizedBox(height: 16),
                                        _InspectorPanel(
                                          activeStep: _activeStep,
                                          preset: _preset,
                                          modelName: _modelName,
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
                                            setState(
                                              () => _engineForce = value,
                                            );
                                          },
                                          onGripChanged: (value) {
                                            setState(() => _grip = value);
                                          },
                                          onSuspensionChanged: (value) {
                                            setState(() => _suspension = value);
                                          },
                                          onCenterOfMassChanged: (value) {
                                            setState(
                                              () => _centerOfMass = value,
                                            );
                                          },
                                          onFrontSteeringChanged: (value) {
                                            setState(
                                              () => _frontSteering = value,
                                            );
                                          },
                                          onRearSteeringChanged: (value) {
                                            setState(
                                              () => _rearSteering = value,
                                            );
                                          },
                                          onFrontTractionChanged: (value) {
                                            setState(
                                              () => _frontTraction = value,
                                            );
                                          },
                                          onRearTractionChanged: (value) {
                                            setState(
                                              () => _rearTraction = value,
                                            );
                                          },
                                          onExport: _exportGodotFiles,
                                        ),
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
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.activeStep,
    required this.onStepSelected,
  });

  final int activeStep;
  final ValueChanged<int> onStepSelected;

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
          const SizedBox(height: 44),
          const _SmallLabel('RIGGING WORKFLOW'),
          const SizedBox(height: 10),
          _SidebarStep(
            number: 1,
            title: 'Import model',
            subtitle: 'GLB / glTF',
            active: activeStep == 1,
            complete: activeStep > 1,
            onTap: () => onStepSelected(1),
          ),
          _SidebarStep(
            number: 2,
            title: 'Rig wheels',
            subtitle: 'Steering & traction',
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
            subtitle: 'Scene + script + config',
            active: activeStep == 4,
            complete: false,
            onTap: () => onStepSelected(4),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2831),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A3B46)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFFFB15C),
                  size: 18,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Built for Godot 4 VehicleBody3D rigs.',
                    style: TextStyle(
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
            'v0.1  •  RIG-CAR LAB',
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

class _DesktopTopbar extends StatelessWidget {
  const _DesktopTopbar({required this.modelName, required this.onExport});

  final String modelName;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        color: Color(0xFF10181E),
        border: Border(bottom: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Row(
        children: [
          const Text(
            'UNTITLED RIG',
            style: TextStyle(
              color: Color(0xFFEEF2F4),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E392F),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'SAVED',
              style: TextStyle(
                color: Color(0xFF6BD2A0),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () {},
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.onExport});

  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF10181E),
        border: Border(bottom: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Row(
        children: [
          const _Brand(),
          const Spacer(),
          IconButton(
            onPressed: onExport,
            tooltip: 'Export Godot rig',
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            onPressed: () {},
            tooltip: 'More options',
            icon: const Icon(Icons.more_horiz_rounded),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.preset, required this.modelName});

  final RigPreset preset;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const Text(
                  '3D VIEWPORT',
                  style: TextStyle(
                    color: Color(0xFFEAF0F2),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 10),
                const _StatusDot(
                  label: 'RIG PREVIEW',
                  color: Color(0xFF6BD2A0),
                ),
                const Spacer(),
                Text(
                  'Orbit  •  Zoom  •  Pan',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.fullscreen_rounded,
                  size: 18,
                  color: Color(0xFF87969F),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 418,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CarViewportPainter(
                      accent: preset.accent,
                      secondary: preset.secondary,
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 16,
                  child: _ViewportTag(
                    icon: Icons.view_in_ar_outlined,
                    label: preset.name,
                  ),
                ),
                Positioned(
                  right: 18,
                  top: 16,
                  child: _ViewportTag(
                    icon: Icons.insert_drive_file_outlined,
                    label: modelName == 'No model loaded'
                        ? 'Procedural preview'
                        : modelName,
                  ),
                ),
                const Positioned(left: 18, bottom: 16, child: _AxisLegend()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const _Metric(label: 'MESH', value: 'READY'),
                const SizedBox(width: 22),
                const _Metric(label: 'WHEELS', value: '4 / 4'),
                const SizedBox(width: 22),
                const _Metric(label: 'PHYSICS', value: 'ATTACHED'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.help_outline_rounded, size: 16),
                  label: const Text('Viewport help'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.activeStep,
    required this.preset,
    required this.modelName,
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
  });

  final int activeStep;
  final RigPreset preset;
  final String modelName;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workflowSteps[activeStep - 1].title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          workflowSteps[activeStep - 1].subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        switch (activeStep) {
          1 => _ImportInspector(
            preset: preset,
            modelName: modelName,
            onPickModel: onPickModel,
            onPresetChanged: onPresetChanged,
          ),
          2 => _WheelInspector(
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
          ),
          _ => _ExportInspector(onExport: onExport),
        },
      ],
    );
  }
}

class _ImportInspector extends StatelessWidget {
  const _ImportInspector({
    required this.preset,
    required this.modelName,
    required this.onPickModel,
    required this.onPresetChanged,
  });

  final RigPreset preset;
  final String modelName;
  final VoidCallback onPickModel;
  final ValueChanged<RigPreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.file_upload_outlined,
                title: 'Vehicle model',
                subtitle: 'Start with a GLB or glTF asset',
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onPickModel,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10191F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF3A4A55),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        color: Color(0xFFFFB15C),
                        size: 28,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        modelName == 'No model loaded'
                            ? 'Drop a model or browse files'
                            : modelName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFE7EEF1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Supported: .glb, .gltf',
                        style: TextStyle(
                          color: Color(0xFF82919B),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 13),
                      OutlinedButton(
                        onPressed: onPickModel,
                        child: const Text('Choose model'),
                      ),
                    ],
                  ),
                ),
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
                icon: Icons.tune_rounded,
                title: 'Quick setup',
                subtitle: 'Use a starting geometry preset',
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

class _WheelInspector extends StatelessWidget {
  const _WheelInspector({
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
  });

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

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.settings_ethernet_rounded,
            title: 'Wheel nodes',
            subtitle: 'Map the four VehicleWheel3D nodes',
          ),
          const SizedBox(height: 14),
          const Text(
            'DRIVETRAIN',
            style: TextStyle(
              color: Color(0xFF75838C),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'FWD', label: Text('FWD')),
              ButtonSegment(value: 'RWD', label: Text('RWD')),
              ButtonSegment(value: 'AWD', label: Text('AWD')),
            ],
            selected: {drive},
            onSelectionChanged: (value) => onDriveChanged(value.first),
            style: ButtonStyle(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: Color(0xFF344650)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFFFF713D)
                    : const Color(0xFF111A21),
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : const Color(0xFFAAB6BC),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _WheelHeader(),
          const SizedBox(height: 8),
          _WheelRow(
            label: 'Front axle',
            nodeName: 'Wheel_FL  /  Wheel_FR',
            steering: frontSteering,
            traction: frontTraction,
            onSteeringChanged: onFrontSteeringChanged,
            onTractionChanged: onFrontTractionChanged,
          ),
          const SizedBox(height: 8),
          _WheelRow(
            label: 'Rear axle',
            nodeName: 'Wheel_RL  /  Wheel_RR',
            steering: rearSteering,
            traction: rearTraction,
            onSteeringChanged: onRearSteeringChanged,
            onTractionChanged: onRearTractionChanged,
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.speed_rounded,
            title: 'Vehicle physics',
            subtitle: 'Tune values exported to VehicleBody3D',
          ),
          const SizedBox(height: 14),
          _SliderField(
            label: 'Mass',
            value: mass,
            min: 400,
            max: 2600,
            suffix: ' kg',
            divisions: 44,
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
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF182A23),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF6BD2A0),
                  size: 17,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Balanced starting point. Test traction and braking in Godot before shipping.',
                    style: TextStyle(
                      color: Color(0xFFA2CBB5),
                      fontSize: 11,
                      height: 1.35,
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
            title: 'Godot package',
            subtitle: 'Ready to drop into a Godot 4 project',
          ),
          const SizedBox(height: 16),
          const _ExportFile(
            icon: Icons.account_tree_outlined,
            name: 'rig_car.tscn',
            detail: 'VehicleBody3D scene',
          ),
          const _ExportFile(
            icon: Icons.code_rounded,
            name: 'rig_car.gd',
            detail: 'Input + engine controller',
          ),
          const _ExportFile(
            icon: Icons.data_object_rounded,
            name: 'rig_car_config.json',
            detail: 'Editable rig settings',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Download Godot files'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF713D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Import the scene, then place your MeshInstance3D and collision shape under RigCar.',
            style: TextStyle(
              color: Color(0xFF8998A1),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
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
              width: 29,
              height: 29,
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
                  const SizedBox(height: 3),
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

class _WheelHeader extends StatelessWidget {
  const _WheelHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Text(
            'AXLE',
            style: TextStyle(
              color: Color(0xFF75838C),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(
          width: 67,
          child: Text(
            'STEER',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF75838C),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(
          width: 67,
          child: Text(
            'DRIVE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF75838C),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
      ],
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
                const SizedBox(height: 3),
                Text(
                  nodeName,
                  style: const TextStyle(color: Color(0xFF71818B), fontSize: 9),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 67,
            child: Switch(
              value: steering,
              onChanged: onSteeringChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFFF713D),
            ),
          ),
          SizedBox(
            width: 67,
            child: Switch(
              value: traction,
              onChanged: onTractionChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFFF713D),
            ),
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

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
          ),
        ),
      ],
    );
  }
}

class _ViewportTag extends StatelessWidget {
  const _ViewportTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xB8141E24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFB8C3C8), size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB8C3C8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisLegend extends StatelessWidget {
  const _AxisLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xB8141E24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'X',
            style: TextStyle(
              color: Color(0xFFE86F6F),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 7),
          Text(
            'Y',
            style: TextStyle(
              color: Color(0xFF6BD2A0),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 7),
          Text(
            'Z',
            style: TextStyle(
              color: Color(0xFF79A9EE),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF65747D),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFDDE6EA),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CarViewportPainter extends CustomPainter {
  const _CarViewportPainter({required this.accent, required this.secondary});

  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1A2831), Color(0xFF0F171D)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final grid = Paint()
      ..color = const Color(0x26384A55)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width + size.height; x += 34) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height * .5, 0),
        grid,
      );
    }
    for (var y = size.height * .58; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final center = Offset(size.width * .52, size.height * .56);
    final shadow = Paint()..color = const Color(0xB8000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(5, 48),
        width: size.width * .55,
        height: 50,
      ),
      shadow,
    );

    final body = Path()
      ..moveTo(center.dx - 170, center.dy + 18)
      ..quadraticBezierTo(
        center.dx - 148,
        center.dy - 40,
        center.dx - 90,
        center.dy - 52,
      )
      ..lineTo(center.dx - 36, center.dy - 114)
      ..quadraticBezierTo(
        center.dx + 16,
        center.dy - 140,
        center.dx + 86,
        center.dy - 111,
      )
      ..lineTo(center.dx + 141, center.dy - 47)
      ..quadraticBezierTo(
        center.dx + 176,
        center.dy - 25,
        center.dx + 182,
        center.dy + 17,
      )
      ..lineTo(center.dx + 159, center.dy + 40)
      ..lineTo(center.dx - 146, center.dy + 40)
      ..close();
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [accent, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(body.getBounds());
    canvas.drawPath(body, bodyPaint);

    final windowPaint = Paint()..color = const Color(0xFF14222A);
    final windows = Path()
      ..moveTo(center.dx - 29, center.dy - 99)
      ..lineTo(center.dx + 27, center.dy - 116)
      ..lineTo(center.dx + 70, center.dy - 99)
      ..lineTo(center.dx + 47, center.dy - 51)
      ..lineTo(center.dx - 53, center.dy - 51)
      ..close();
    canvas.drawPath(windows, windowPaint);
    final divider = Paint()
      ..color = const Color(0xFF40515B)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(center.dx + 11, center.dy - 108),
      Offset(center.dx + 1, center.dy - 52),
      divider,
    );

    final wheelPaint = Paint()..color = const Color(0xFF0A1014);
    final hubPaint = Paint()..color = const Color(0xFF9BAAB1);
    for (final wheel in [
      Offset(center.dx - 122, center.dy + 36),
      Offset(center.dx + 117, center.dy + 36),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: wheel, width: 44, height: 73),
        wheelPaint,
      );
      canvas.drawCircle(wheel, 9, hubPaint);
      canvas.drawCircle(wheel, 4, Paint()..color = const Color(0xFF24323A));
    }

    final headlight = Paint()..color = const Color(0xFFFFE7A4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 152, center.dy + 6),
        width: 20,
        height: 11,
      ),
      headlight,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 163, center.dy + 6),
        width: 20,
        height: 11,
      ),
      headlight,
    );

    final marker = Paint()
      ..color = const Color(0xFFFF713D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(center.dx - 123, center.dy + 36), 32, marker);
    canvas.drawCircle(Offset(center.dx + 118, center.dy + 36), 32, marker);
  }

  @override
  bool shouldRepaint(covariant _CarViewportPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.secondary != secondary;
}

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

class RigConfig {
  const RigConfig({
    required this.modelName,
    required this.presetName,
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
  });

  final String modelName;
  final String presetName;
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

  Map<String, Object> toJson() => {
    'format': 'rig-car.godot.vehicle-body-3d/v1',
    'model': modelName,
    'preset': presetName,
    'godot': {'root_node': 'VehicleBody3D', 'wheel_node': 'VehicleWheel3D'},
    'vehicle_body': {
      'mass': mass,
      'engine_force': engineForce,
      'center_of_mass_y': centerOfMass,
      'drive': drive,
    },
    'wheels': {
      'front': {
        'use_as_steering': frontSteering,
        'use_as_traction': frontTraction,
      },
      'rear': {
        'use_as_steering': rearSteering,
        'use_as_traction': rearTraction,
        'wheel_friction_slip': grip,
        'suspension_stiffness': suspension,
      },
    },
  };

  String toGdScript() =>
      '''extends VehicleBody3D

@export var max_engine_force: float = ${engineForce.toStringAsFixed(1)}
@export var max_brake_force: float = 30.0
@export var max_steering_angle: float = 0.45

func _physics_process(_delta: float) -> void:
    var throttle := Input.get_axis("brake", "accelerate")
    var steer := Input.get_axis("steer_right", "steer_left")
    engine_force = throttle * max_engine_force
    steering = steer * max_steering_angle
    brake = max_brake_force if Input.is_action_pressed("brake") else 0.0
''';

  String toTscn() =>
      '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://rig_car.gd" id="1_rig"]

[sub_resource type="BoxShape3D" id="BoxShape3D_body"]
size = Vector3(1.8, 0.6, 4.2)

[node name="RigCar" type="VehicleBody3D"]
mass = ${mass.toStringAsFixed(1)}
script = ExtResource("1_rig")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, 0.35, 0)
shape = SubResource("BoxShape3D_body")

[node name="Wheel_FL" type="VehicleWheel3D" parent="."]
position = Vector3(-0.85, 0.0, -1.35)
use_as_steering = $frontSteering
use_as_traction = $frontTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_FR" type="VehicleWheel3D" parent="."]
position = Vector3(0.85, 0.0, -1.35)
use_as_steering = $frontSteering
use_as_traction = $frontTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_RL" type="VehicleWheel3D" parent="."]
position = Vector3(-0.85, 0.0, 1.35)
use_as_steering = $rearSteering
use_as_traction = $rearTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_RR" type="VehicleWheel3D" parent="."]
position = Vector3(0.85, 0.0, 1.35)
use_as_steering = $rearSteering
use_as_traction = $rearTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}
''';
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
  WorkflowStep(number: 1, title: 'Import model', subtitle: 'GLB / glTF'),
  WorkflowStep(number: 2, title: 'Rig wheels', subtitle: 'Steering & traction'),
  WorkflowStep(number: 3, title: 'Tune physics', subtitle: 'Mass & suspension'),
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
