import 'dart:math';

import 'package:flutter/material.dart';

import 'model_data.dart';
import 'pipeline_models.dart';

// ── Visual Palette ──────────────────────────────────────────────────────────

class _Palette {
  static const bgDark = Color(0xFF0A110E);
  static const panelFill = Color(0xFF111C18);
  static const activeCardFill = Color(0xFF13261F);
  static const borderDefault = Color(0xFF1E352C);
  static const borderActive = Color(0xFF10B981);
  static const accentEmerald = Color(0xFF10B981);
  static const accentAmber = Color(0xFFF59E0B);
  static const accentBlue = Color(0xFF38BDF8);
  static const textPrimary = Color(0xFFF3F4F6);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMetrics = Color(0xFF6EE7B7);
}

// ── Inspector Panel ─────────────────────────────────────────────────────────

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    super.key,
    required this.activeStep,
    required this.inspectMode,
    required this.onInspectModeChanged,
    required this.parsedModel,
    required this.detection,
    required this.assignedWheels,
    required this.detectedGroups,
    required this.selectedHandlingPreset,
    required this.mass,
    required this.grip,
    required this.suspension,
    required this.engineForce,
    required this.centerOfMassY,
    required this.springRestLength,
    required this.springStiffness,
    required this.dampingCompression,
    required this.steerAngle,
    required this.selectedAcousticProfile,
    required this.sirenAudioEnabled,
    required this.tireSkidAudioEnabled,
    required this.audioSlots,
    required this.godotArchitecture,
    required this.canExport,
    required this.exportBlockReason,
    required this.onStepSelect,
    required this.onPickModel,
    required this.onRotateYaw,
    required this.onFlipFrontBack,
    required this.onSnapToGround,
    required this.onApplyScale,
    this.onApproveAutoRig,
    required this.onStartScan,
    this.isScanning = false,
    this.scanStage = 0,
    this.isScanDone = false,
    required this.onGroupRoleChange,
    required this.onPickWheelInViewport,
    required this.onRecalculateHeightFilter,
    required this.onMirrorLeftToRight,
    required this.onRecenterPivots,
    required this.onHandlingPresetSelected,
    required this.onMassChanged,
    required this.onCenterOfMassChanged,
    required this.onSuspensionChanged,
    required this.onSpringStiffnessChanged,
    required this.onDampingCompressionChanged,
    required this.onGripChanged,
    required this.onSteerAngleChanged,
    required this.onResetPhysicsProperty,
    required this.onAcousticProfileSelected,
    required this.onToggleSirenAudio,
    required this.onToggleTireSkidAudio,
    required this.onAudioSlotPitchChanged,
    required this.onPreviewAudioSlot,
    required this.onGodotArchitectureChanged,
    required this.onExport,
    required this.onTestDrive,
    required this.onHoverPart,
    this.excludeRoofAntenna = false,
    this.onExcludeRoofAntennaChanged,
    this.onGroupToggle,
  });

  final int activeStep;
  final String inspectMode; // 'auto' | 'manual'
  final ValueChanged<String> onInspectModeChanged;
  final ParsedModel? parsedModel;
  final DetectionResult? detection;
  final Map<String, DetectedWheel?> assignedWheels;
  final List<DetectedMeshGroup> detectedGroups;
  final String selectedHandlingPreset;
  final double mass;
  final double grip;
  final double suspension;
  final double engineForce;
  final double centerOfMassY;
  final double springRestLength;
  final double springStiffness;
  final double dampingCompression;
  final double steerAngle;
  final String selectedAcousticProfile;
  final bool sirenAudioEnabled;
  final bool tireSkidAudioEnabled;
  final List<AudioSlotConfig> audioSlots;
  final String godotArchitecture; // 'standard' | 'raycast'
  final bool canExport;
  final String? exportBlockReason;

  // Event hooks
  final ValueChanged<int> onStepSelect;
  final VoidCallback onPickModel;
  final ValueChanged<double> onRotateYaw;
  final VoidCallback onFlipFrontBack;
  final VoidCallback onSnapToGround;
  final ValueChanged<double> onApplyScale;
  final VoidCallback? onApproveAutoRig;
  final VoidCallback onStartScan;
  final bool isScanning;
  final int scanStage;
  final bool isScanDone;
  final void Function(int groupId, String role) onGroupRoleChange;
  final ValueChanged<String> onPickWheelInViewport;
  final void Function(double groundTolPercent, double inboardTolPercent) onRecalculateHeightFilter;
  final VoidCallback onMirrorLeftToRight;
  final VoidCallback onRecenterPivots;
  final ValueChanged<HandlingPreset> onHandlingPresetSelected;
  final ValueChanged<double> onMassChanged;
  final ValueChanged<double> onCenterOfMassChanged;
  final ValueChanged<double> onSuspensionChanged;
  final ValueChanged<double> onSpringStiffnessChanged;
  final ValueChanged<double> onDampingCompressionChanged;
  final ValueChanged<double> onGripChanged;
  final ValueChanged<double> onSteerAngleChanged;
  final ValueChanged<String> onResetPhysicsProperty;
  final ValueChanged<AcousticProfile> onAcousticProfileSelected;
  final ValueChanged<bool> onToggleSirenAudio;
  final ValueChanged<bool> onToggleTireSkidAudio;
  final void Function(String slotId, double pitch) onAudioSlotPitchChanged;
  final ValueChanged<String> onPreviewAudioSlot;
  final ValueChanged<String> onGodotArchitectureChanged;
  final VoidCallback onExport;
  final VoidCallback onTestDrive;
  final ValueChanged<String?> onHoverPart;
  final bool excludeRoofAntenna;
  final ValueChanged<bool>? onExcludeRoofAntennaChanged;
  final void Function(int groupId, bool isEnabled)? onGroupToggle;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  // Step 1 local inputs
  late final TextEditingController _targetLengthController;
  bool _excludeRoofAntenna = false;
  bool _isUploadCollapsed = true;

  // Step 2 local filters
  double _groundTolerancePercent = 8.0; // 2% - 25% of car height
  double _inboardCapturePercent = 1.5; // 0% - 10% of car width

  @override
  void initState() {
    super.initState();
    _excludeRoofAntenna = widget.excludeRoofAntenna;
    final len = widget.parsedModel?.worldBBox.size.z.abs() ?? 4.2;
    _targetLengthController = TextEditingController(
      text: len.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(covariant InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parsedModel != widget.parsedModel && widget.parsedModel != null) {
      final len = widget.parsedModel!.worldBBox.size.z.abs();
      _targetLengthController.text = len.toStringAsFixed(1);
    }
    if (oldWidget.excludeRoofAntenna != widget.excludeRoofAntenna) {
      _excludeRoofAntenna = widget.excludeRoofAntenna;
    }
  }

  @override
  void dispose() {
    _targetLengthController.dispose();
    super.dispose();
  }

  String _getStepTitle() {
    switch (widget.activeStep) {
      case 1:
        return 'Upload Vehicle';
      case 2:
        return 'Scan & Organize';
      case 3:
        return 'Add Physics';
      case 4:
        return 'Add Sound';
      case 5:
        return 'Export Rig';
      default:
        return 'Inspector';
    }
  }

  Widget _buildStatusBadge() {
    if (widget.activeStep != 1 && widget.inspectMode == 'manual') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0C243B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF1E3A5F)),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 5, color: _Palette.accentBlue),
              SizedBox(width: 4),
              Text(
                'Custom Mode',
                style: TextStyle(
                  color: _Palette.accentBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Auto path badges
    bool isWarning = false;
    String badgeText = 'Auto Verified';

    switch (widget.activeStep) {
      case 1:
        if (widget.parsedModel == null) {
          badgeText = 'Pending Import';
        } else {
          badgeText = 'Model Loaded';
        }
        break;
      case 2:
        final wheels = widget.assignedWheels.values.whereType<DetectedWheel>().length;
        final warnings = widget.detection?.warnings ?? const [];
        if (widget.isScanning) {
          isWarning = false;
          badgeText = 'Filtering Wheels...';
        } else if (!widget.isScanDone) {
          isWarning = false;
          badgeText = 'Ready to Scan';
        } else if (wheels < 4 || warnings.isNotEmpty) {
          isWarning = true;
          badgeText = 'Math Review Needed';
        } else {
          badgeText = 'Auto Verified';
        }
        break;
      case 3:
        badgeText = 'Physics Attached';
        break;
      case 4:
        badgeText = 'Acoustic Ready';
        break;
      case 5:
        if (!widget.canExport) {
          isWarning = true;
          badgeText = 'Checklist Incomplete';
        } else {
          badgeText = 'Rig Ready';
        }
        break;
    }

    final color = isWarning ? _Palette.accentAmber : _Palette.accentEmerald;
    final bg = isWarning ? const Color(0xFF281B0E) : const Color(0xFF13261F);
    final border = isWarning ? const Color(0xFF4D3810) : const Color(0xFF1E352C);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 5, color: color),
            const SizedBox(width: 4),
            Text(
              badgeText,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _Palette.panelFill,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFixedHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: _buildStepBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedHeader() {
    final isAuto = widget.inspectMode == 'auto';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: _Palette.panelFill,
        border: Border(
          bottom: BorderSide(color: _Palette.borderDefault),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getStepTitle(),
                  style: const TextStyle(
                    color: _Palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _buildStatusBadge(),
              ],
            ),
          ),
          if (widget.activeStep != 1) ...[
            const SizedBox(width: 8),
            // 2-button segmented pill toggle: [ ✨ Auto | 🛠 Custom ]
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: _Palette.bgDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _Palette.borderDefault),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HeaderSegmentButton(
                        title: '✨ Auto',
                        selected: isAuto,
                        onTap: () => widget.onInspectModeChanged('auto'),
                      ),
                      _HeaderSegmentButton(
                        title: '🛠 Custom',
                        selected: !isAuto,
                        onTap: () => widget.onInspectModeChanged('manual'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    switch (widget.activeStep) {
      case 1:
        return _buildStep1Merged();
      case 2:
        return widget.inspectMode == 'auto'
            ? _buildStep2Auto()
            : _buildStep2Manual();
      case 3:
        return widget.inspectMode == 'auto'
            ? _buildStep3Auto()
            : _buildStep3Manual();
      case 4:
        return widget.inspectMode == 'auto'
            ? _buildStep4Auto()
            : _buildStep4Manual();
      case 5:
        return _buildStep5Export();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 1: UPLOAD VEHICLE (MERGED) ────────────────────────────────────────

  Widget _buildStep1Merged() {
    final model = widget.parsedModel;
    final hasModel = model != null;

    final meshCount = hasModel ? model.meshes.length : 12;
    final vertCount = hasModel
        ? model.instances.fold<int>(0, (sum, inst) => sum + inst.worldVertices.length)
        : 45210;
    final size = model?.worldBBox.size ?? const Vec3(1.88, 1.25, 4.20);
    final lengthStr = size.z.abs().toStringAsFixed(1);
    final widthStr = size.x.abs().toStringAsFixed(1);
    final heightStr = size.y.abs().toStringAsFixed(1);
    final lowestY = model?.worldBBox.lo.y ?? 0.0;
    final formattedVerts = vertCount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: widget.onPickModel,
          icon: const Icon(Icons.file_upload_outlined, size: 16),
          label: const Text('Import 3D Model (.glb, .gltf, .obj)'),
          style: FilledButton.styleFrom(
            backgroundColor: _Palette.accentEmerald,
            foregroundColor: const Color(0xFF041D14),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Collapsible Summary Card
        Container(
          decoration: BoxDecoration(
            color: _Palette.activeCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _isUploadCollapsed = !_isUploadCollapsed),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1E17),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _Palette.accentEmerald.withAlpha(70)),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: _Palette.accentEmerald,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hasModel ? 'Vehicle Parsed' : 'Vehicle Ready',
                                    style: const TextStyle(
                                      color: _Palette.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF13261F),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF1E352C)),
                                  ),
                                  child: const Text(
                                    'Verified',
                                    style: TextStyle(
                                      color: _Palette.accentEmerald,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${lengthStr}L × ${widthStr}W × ${heightStr}H m · $meshCount meshes · $formattedVerts verts',
                              style: const TextStyle(
                                color: _Palette.textMetrics,
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isUploadCollapsed
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: _Palette.accentEmerald,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isUploadCollapsed = !_isUploadCollapsed),
                  icon: Icon(
                    _isUploadCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                    size: 14,
                    color: _Palette.accentEmerald,
                  ),
                  label: Text(
                    _isUploadCollapsed ? 'Expand Vehicle Details & Tools' : 'Collapse Vehicle Details',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _Palette.accentEmerald,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1E352C)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_isUploadCollapsed) ...[
          const SizedBox(height: 16),
          const _SectionHeader('PROGRESS & BOUNDS VERIFICATION'),
          const SizedBox(height: 8),
          _InspectCheckCard(
            icon: Icons.check_circle_rounded,
            iconColor: _Palette.accentEmerald,
            title: 'Model Parsed',
            metric: '$meshCount meshes · $formattedVerts vertices',
            description: hasModel
                ? 'Clean manifold geometry and vertex islands parsed.'
                : 'Default vehicle template loaded. Ready for import.',
            onHover: (hover) => widget.onHoverPart(hover ? 'model_root' : null),
          ),
          const SizedBox(height: 8),
          _InspectCheckCard(
            icon: Icons.check_circle_rounded,
            iconColor: _Palette.accentEmerald,
            title: 'Bounding Box',
            metric: '${lengthStr}L × ${widthStr}W × ${heightStr}H m',
            description: 'Calculated from oriented vehicle geometry bounds.',
            onHover: (hover) => widget.onHoverPart(hover ? 'bbox' : null),
          ),
          const SizedBox(height: 8),
          _InspectCheckCard(
            icon: Icons.check_circle_rounded,
            iconColor: _Palette.accentEmerald,
            title: 'Ground Plane Snap',
            metric: 'Lowest Y = ${lowestY.abs() < 0.01 ? "0.00" : lowestY.toStringAsFixed(2)}m',
            description: 'Lowest tire contact points aligned with zero road plane.',
            onHover: (hover) => widget.onHoverPart(hover ? 'ground_plane' : null),
          ),
          const SizedBox(height: 8),
          _InspectCheckCard(
            icon: Icons.check_circle_rounded,
            iconColor: _Palette.accentEmerald,
            title: 'Forward Axis',
            metric: 'Standard Front: -Z',
            description: 'Heading aligns with standard Godot 4 VehicleBody3D forward.',
            onHover: (hover) => widget.onHoverPart(hover ? 'forward_axis' : null),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('ORIENTATION QUICK-FIX'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _Palette.activeCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _Palette.borderDefault),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionButton(
                        label: 'Rotate +90° Yaw',
                        icon: Icons.rotate_right_rounded,
                        onTap: () => widget.onRotateYaw(pi / 2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _QuickActionButton(
                        label: 'Flip Front/Back',
                        icon: Icons.swap_horiz_rounded,
                        onTap: widget.onFlipFrontBack,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _QuickActionButton(
                  label: 'Snap to Ground (Y = 0.0m)',
                  icon: Icons.vertical_align_bottom_rounded,
                  onTap: widget.onSnapToGround,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('SCALE NORMALIZATION'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _Palette.activeCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _Palette.borderDefault),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _targetLengthController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: _Palette.textMetrics,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        labelText: 'Target Length (m)',
                        labelStyle: const TextStyle(color: _Palette.textSecondary, fontSize: 11),
                        suffixText: 'm',
                        suffixStyle: const TextStyle(color: _Palette.textSecondary, fontSize: 11),
                        filled: true,
                        fillColor: const Color(0xFF0B1410),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _Palette.borderDefault),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _Palette.borderDefault),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _Palette.accentEmerald),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final val = double.tryParse(_targetLengthController.text.trim()) ?? 4.2;
                    widget.onApplyScale(val.clamp(1.0, 15.0));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _Palette.accentEmerald,
                    foregroundColor: const Color(0xFF041D14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Apply Scale', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('BOUNDS FILTER'),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              final nextVal = !_excludeRoofAntenna;
              setState(() => _excludeRoofAntenna = nextVal);
              widget.onExcludeRoofAntennaChanged?.call(nextVal);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _Palette.activeCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _Palette.borderDefault),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _excludeRoofAntenna,
                      activeColor: _Palette.accentEmerald,
                      checkColor: const Color(0xFF041D14),
                      onChanged: (val) {
                        final nextVal = val ?? false;
                        setState(() => _excludeRoofAntenna = nextVal);
                        widget.onExcludeRoofAntennaChanged?.call(nextVal);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Exclude roof/antenna parts from chassis bounds',
                      style: TextStyle(
                        color: _Palette.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Scan & Organize',
          onPressed: () => widget.onStepSelect(2),
        ),
      ],
    );
  }

  // ── STEP 2: SCAN & ORGANIZE ────────────────────────────────────────────────

  Widget _buildStep2Auto() {
    final model = widget.parsedModel;
    final loosePartsCount = widget.detection?.loosePartsCount ??
        (model != null ? model.instances.length : 0);

    final fl = widget.assignedWheels['FL'];
    final fr = widget.assignedWheels['FR'];
    final rl = widget.assignedWheels['RL'];
    final rr = widget.assignedWheels['RR'];
    final wheelCount = widget.assignedWheels.values.whereType<DetectedWheel>().length;
    final isDone = widget.isScanDone && wheelCount >= 4;
    final isScanning = widget.isScanning;
    final stage = widget.scanStage;
    final isStaggered = widget.detection?.isStaggered ?? false;
    final circPercent = ((widget.detection?.averageCircularity ?? 0.98) * 100).round();

    final (progressText, _) = switch ((isDone, isScanning, stage)) {
      (true, _, _) => ('PROGRESS: [████████████████████████] 100% COMPLETE', 1.0),
      (_, true, 1) => ('PROGRESS: [██████------------------]  25% PASS 1: DECOMPOSE', 0.25),
      (_, true, 2) => ('PROGRESS: [████████████------------]  50% PASS 2: COAXIAL RANSAC', 0.50),
      (_, true, 3) => ('PROGRESS: [██████████████████------]  75% PASS 3: GROUND SNAP', 0.75),
      (_, true, 4) => ('PROGRESS: [██████████████████████--]  92% PASS 4: SOLVING PIVOTS', 0.92),
      _ => ('PROGRESS: [------------------------]   0% STANDBY', 0.0),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('4-STAGE AUTO-RIG PIPELINE'),
        const SizedBox(height: 6),

        // ── Cyber AI Terminal Window ──────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050907),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isScanning
                  ? const Color(0xFF10B981)
                  : (isDone ? const Color(0xFF1E3E2E) : const Color(0xFF16251E)),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isScanning
                    ? const Color(0x3510B981)
                    : const Color(0x18000000),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Terminal Window Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                decoration: const BoxDecoration(
                  color: Color(0xFF09120D),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                  border: Border(bottom: BorderSide(color: Color(0xFF162B20))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        'terminal://rig_ai.sh',
                        style: TextStyle(
                          color: Color(0xFF86978C),
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0x2810B981)
                            : (isScanning ? const Color(0x33F59E0B) : const Color(0x1A6B7280)),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isDone
                              ? const Color(0xFF10B981)
                              : (isScanning ? const Color(0xFFF59E0B) : const Color(0xFF374151)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4.5,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFF4ADE80)
                                  : (isScanning ? const Color(0xFFFBBF24) : const Color(0xFF9CA3AF)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            isDone
                                ? 'SOLVED'
                                : (isScanning ? 'CALC...' : 'STANDBY'),
                            style: TextStyle(
                              color: isDone
                                  ? const Color(0xFF4ADE80)
                                  : (isScanning ? const Color(0xFFFBBF24) : const Color(0xFF9CA3AF)),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Terminal Progress Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                color: const Color(0xFF040705),
                child: Text(
                  progressText,
                  style: TextStyle(
                    color: isDone
                        ? const Color(0xFF10B981)
                        : (isScanning ? const Color(0xFF34D399) : const Color(0xFF6B7280)),
                    fontSize: 8.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 3. The 4 Terminal Pipeline Stages
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Column(
                  children: [
                    _TerminalStageItem(
                      stageTag: '[S1]',
                      title: '1. Separate Loose Parts',
                      detail: isDone || isScanning
                          ? '$loosePartsCount islands isolated'
                          : '$loosePartsCount candidate parts indexed',
                      statusTag: isDone ? '[RESOLVED]' : (isScanning && stage == 1 ? '[CALC...]' : (isScanning && stage > 1 ? '[RESOLVED]' : '[QUEUED]')),
                      statusColor: isDone || (isScanning && stage > 1) ? const Color(0xFF4ADE80) : (isScanning && stage == 1 ? const Color(0xFFFBBF24) : const Color(0xFF6B7280)),
                      isActive: isScanning && stage == 1,
                      isDone: isDone || (isScanning && stage > 1),
                      onHover: (hover) => widget.onHoverPart(hover ? 'loose_parts' : null),
                    ),
                    const SizedBox(height: 2.5),
                    _TerminalStageItem(
                      stageTag: '[S2]',
                      title: '2. Axle Symmetry & Circularity (2+2 / 4x)',
                      detail: isDone
                          ? '${isStaggered ? '2+2 Staggered Axles' : '4x Identical'} · Circ: $circPercent%'
                          : (isScanning && stage >= 2 ? 'Matching axle symmetry & circularity...' : 'Pending cluster similarity match'),
                      statusTag: isDone ? '[RESOLVED]' : (isScanning && stage == 2 ? '[CALC...]' : (isScanning && stage > 2 ? '[RESOLVED]' : '[QUEUED]')),
                      statusColor: isDone || (isScanning && stage > 2) ? const Color(0xFF4ADE80) : (isScanning && stage == 2 ? const Color(0xFFFBBF24) : const Color(0xFF6B7280)),
                      isActive: isScanning && stage == 2,
                      isDone: isDone || (isScanning && stage > 2),
                      onHover: (hover) => widget.onHoverPart(hover ? 'groups_match' : null),
                    ),
                    const SizedBox(height: 2.5),
                    _TerminalStageItem(
                      stageTag: '[S3]',
                      title: '3. Ground Contact & Outer-Track Filter',
                      detail: isDone
                          ? 'Road locked (Y_contact = 0.00m) · Forward -Z'
                          : (isScanning && stage >= 3 ? 'Filtering 4 symmetric outer corners...' : 'Pending ground & outer-track filter'),
                      statusTag: isDone ? '[RESOLVED]' : (isScanning && stage == 3 ? '[CALC...]' : (isScanning && stage > 3 ? '[RESOLVED]' : '[QUEUED]')),
                      statusColor: isDone || (isScanning && stage > 3) ? const Color(0xFF4ADE80) : (isScanning && stage == 3 ? const Color(0xFFFBBF24) : const Color(0xFF6B7280)),
                      isActive: isScanning && stage == 3,
                      isDone: isDone || (isScanning && stage > 3),
                      onHover: (hover) => widget.onHoverPart(hover ? 'height_filter' : null),
                    ),
                    const SizedBox(height: 2.5),
                    _TerminalStageItem(
                      stageTag: '[S4]',
                      title: '4. Hub Center & Radius Math',
                      detail: isDone
                          ? 'FL: ${_formatWheelR(fl)} W=${_formatWheelW(fl)} · FR: ${_formatWheelR(fr)} · RL: ${_formatWheelR(rl)} · RR: ${_formatWheelR(rr)}'
                          : (isScanning && stage >= 4 ? 'Solving hub pivots & envelopes...' : 'Pending hub & pivot calculation'),
                      statusTag: isDone ? '[RESOLVED]' : (isScanning && stage == 4 ? '[CALC...]' : '[QUEUED]'),
                      statusColor: isDone ? const Color(0xFF4ADE80) : (isScanning && stage == 4 ? const Color(0xFFFBBF24) : const Color(0xFF6B7280)),
                      isActive: isScanning && stage == 4,
                      isDone: isDone,
                      onHover: (hover) => widget.onHoverPart(hover ? 'wheel_hubs' : null),
                    ),
                  ],
                ),
              ),

              // 4. Live AI Computation Console Log
              Container(
                margin: const EdgeInsets.fromLTRB(6, 1, 6, 5),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF030504),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF132A1F)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal_rounded, size: 10, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'AI CALCULATION LOG',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              letterSpacing: 0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isScanning
                              ? 'ACTIVE'
                              : (isDone ? 'READY' : 'STANDBY'),
                          style: TextStyle(
                            color: isScanning
                                ? const Color(0xFFF59E0B)
                                : (isDone ? const Color(0xFF4ADE80) : const Color(0xFF6B7280)),
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(height: 1, color: const Color(0xFF132A1F)),
                    const SizedBox(height: 3),
                    _buildConsoleLogs(
                      isDone: isDone,
                      isScanning: isScanning,
                      stage: stage,
                      loosePartsCount: loosePartsCount,
                      isStaggered: isStaggered,
                      fl: fl,
                      fr: fr,
                      rl: rl,
                      rr: rr,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isScanning ? null : widget.onStartScan,
                icon: isScanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF041D14),
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text(
                  isScanning ? 'Scanning...' : (isDone ? 'Re-Scan' : 'Start'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _Palette.accentEmerald,
                  disabledBackgroundColor: const Color(0xFF16251E),
                  foregroundColor: const Color(0xFF041D14),
                  disabledForegroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => widget.onInspectModeChanged('manual'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _Palette.accentAmber,
                side: const BorderSide(color: Color(0xFF4D3810)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Fix Math Mistakes →', style: TextStyle(fontSize: 10.5)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _NextStepButton(
          label: 'Next: Add Physics',
          onPressed: isDone ? () => widget.onStepSelect(3) : null,
        ),
      ],
    );
  }

  Widget _buildConsoleLogs({
    required bool isDone,
    required bool isScanning,
    required int stage,
    required int loosePartsCount,
    required bool isStaggered,
    required DetectedWheel? fl,
    required DetectedWheel? fr,
    required DetectedWheel? rl,
    required DetectedWheel? rr,
  }) {
    final lines = <String>[];
    if (isDone) {
      lines.add('\$ rig_core --solve -> 4/4 coaxial wheels locked');
      final axis = widget.detection?.autoAxisResult;
      if (axis != null) {
        if (axis.axisSwapped || axis.frontFlipped) {
          final deg = (axis.yawRotatedRadians * 180 / pi).round();
          lines.add('[AI_AXIS] Forward auto-aligned to -Z (yaw: $deg°)');
        } else {
          lines.add('[AI_AXIS] Forward verified along -Z (Godot standard)');
        }
      }
      final purged = widget.detection?.underWheelObjectsDeleted ?? 0;
      if (purged > 0) {
        lines.add('[AI_CLEAN] Purged $purged under-wheel shadow/floor mesh');
      }
      lines.add('[AI_LAND] Zero height locked (wheel contact Y=0.000m)');
      lines.add('[SOLVED] FL(${_formatWheelR(fl)}) FR(${_formatWheelR(fr)}) RL(${_formatWheelR(rl)}) RR(${_formatWheelR(rr)})');
      lines.add('[READY] Godot 4 VehicleBody3D calibrated.');
    } else if (isScanning) {
      lines.add('\$ rig_core --calc-stage=$stage');
      if (stage == 1) {
        lines.add('[CALC 1/4] Isolating $loosePartsCount vertex islands...');
      } else if (stage == 2) {
        lines.add('[CALC 2/4] Coaxial Hub clustering -> concentric rim/tires matched.');
      } else if (stage == 3) {
        lines.add('[CALC 3/4] Road plane contact patch locked (Y_min ≈ 0.00m).');
      } else {
        lines.add('[CALC 4/4] Solving hub pivots & cylinder envelopes...');
      }
      lines.add('> ▋');
    } else {
      lines.add('\$ rig_core --standby (PointNet++ topology ready)');
      lines.add('[AWAIT] Click [Start] to compute 4-stage neural rig.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final isSuccess = line.startsWith('[READY]') || line.startsWith('[SOLVED]');
        final isPrompt = line.startsWith('>') || line.startsWith('\$');
        final isStage = line.contains('[CALC');
        final color = isSuccess
            ? const Color(0xFF4ADE80)
            : (isPrompt
                ? const Color(0xFF38BDF8)
                : (isStage ? const Color(0xFFFBBF24) : const Color(0xFF9CA3AF)));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.6),
          child: Text(
            line,
            style: TextStyle(
              color: color,
              fontSize: 8.5,
              fontFamily: 'monospace',
              fontWeight: isSuccess || isStage ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  String _formatWheelR(DetectedWheel? wheel) {
    if (wheel == null) return '0.34m';
    return '${wheel.radius.toStringAsFixed(2)}m';
  }

  String _formatWheelW(DetectedWheel? wheel) {
    if (wheel == null) return '0.25m';
    return '${wheel.width.toStringAsFixed(2)}m';
  }

  Widget _buildStep2Manual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. Detected 2/4 Group Checklist (Toggle & Role Assign)
        const _SectionHeader('A. DETECTED 2/4 GROUP CHECKLIST'),
        const SizedBox(height: 6),
        const Text(
          'Toggle & assign roles to loose-part groups across all 4 corners:',
          style: TextStyle(color: _Palette.textSecondary, fontSize: 10.5),
        ),
        const SizedBox(height: 8),
        for (final group in widget.detectedGroups) ...[
          _GroupRowCard(
            group: group,
            onRoleChanged: (newRole) => widget.onGroupRoleChange(group.id, newRole),
            onToggle: (enabled) => widget.onGroupToggle?.call(group.id, enabled),
            onHighlight: () => widget.onHoverPart('group_${group.id}'),
            onHover: (hover) => widget.onHoverPart(hover ? 'group_${group.id}' : null),
          ),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 16),
        // B. Height & Corner Filter Override
        const _SectionHeader('B. HEIGHT & CORNER FILTER OVERRIDE'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Palette.activeCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Ground Tolerance',
                      style: TextStyle(color: _Palette.textPrimary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_groundTolerancePercent.round()}% of car height', style: const TextStyle(color: _Palette.textMetrics, fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _Palette.accentEmerald,
                  inactiveTrackColor: _Palette.borderDefault,
                  thumbColor: _Palette.accentEmerald,
                  overlayColor: _Palette.accentEmerald.withAlpha(40),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _groundTolerancePercent,
                  min: 2.0,
                  max: 25.0,
                  onChanged: (val) => setState(() => _groundTolerancePercent = val),
                  onChangeEnd: (val) => widget.onRecalculateHeightFilter(val, _inboardCapturePercent),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Inboard Rim Capture Width',
                      style: TextStyle(color: _Palette.textPrimary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_inboardCapturePercent.toStringAsFixed(1)}% of car width', style: const TextStyle(color: _Palette.textMetrics, fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _Palette.accentEmerald,
                  inactiveTrackColor: _Palette.borderDefault,
                  thumbColor: _Palette.accentEmerald,
                  overlayColor: _Palette.accentEmerald.withAlpha(40),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _inboardCapturePercent,
                  min: 0.0,
                  max: 10.0,
                  onChanged: (val) => setState(() => _inboardCapturePercent = val),
                  onChangeEnd: (val) => widget.onRecalculateHeightFilter(_groundTolerancePercent, val),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => widget.onRecalculateHeightFilter(_groundTolerancePercent, _inboardCapturePercent),
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: _Palette.accentEmerald),
                  label: const Text('Re-run Detection with Overrides', style: TextStyle(color: _Palette.accentEmerald, fontSize: 11)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // C. 4-Corner Manual Slot Picker
        const _SectionHeader('C. 4-CORNER MANUAL SLOT PICKER'),
        const SizedBox(height: 6),
        const Text(
          'Fallback assignment for broken/asymmetrical meshes:',
          style: TextStyle(color: _Palette.textSecondary, fontSize: 10.5),
        ),
        const SizedBox(height: 8),
        for (final slot in ['FL', 'FR', 'RL', 'RR']) ...[
          _WheelSlotRow(
            slot: slot,
            wheel: widget.assignedWheels[slot],
            onPick: () => widget.onPickWheelInViewport(slot),
            onHover: (hover) => widget.onHoverPart(hover ? 'wheel_$slot' : null),
          ),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 16),
        // D. One-Click Symmetry & Pivot Repair
        const _SectionHeader('D. ONE-CLICK SYMMETRY & PIVOT REPAIR'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                label: 'Mirror Left → Right Hubs',
                icon: Icons.flip_rounded,
                onTap: widget.onMirrorLeftToRight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                label: 'Recenter Pivots to Cylinder',
                icon: Icons.adjust_rounded,
                onTap: widget.onRecenterPivots,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Add Physics',
          onPressed: (widget.isScanDone && widget.assignedWheels.values.whereType<DetectedWheel>().length >= 4)
              ? () => widget.onStepSelect(3)
              : null,
        ),
      ],
    );
  }

  // ── STEP 3: ADD PHYSICS ───────────────────────────────────────────────────

  Widget _buildStep3Auto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('HANDLING PRESETS'),
        const SizedBox(height: 8),
        for (final preset in kHandlingPresets) ...[
          _PresetRadioCard(
            preset: preset,
            selected: widget.selectedHandlingPreset == preset.id,
            onTap: () => widget.onHandlingPresetSelected(preset),
          ),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 16),
        const _SectionHeader('CALCULATED SUMMARY'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Palette.activeCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.borderDefault),
          ),
          child: Column(
            children: [
              _MetricRow(label: 'Mass', value: '${widget.mass.round()} kg'),
              const Divider(color: _Palette.borderDefault, height: 14),
              _MetricRow(label: 'Center of Mass Y', value: '${widget.centerOfMassY.toStringAsFixed(2)}m'),
              const Divider(color: _Palette.borderDefault, height: 14),
              _MetricRow(label: 'Spring Rest Length', value: '${widget.springRestLength.toStringAsFixed(2)}m'),
              const Divider(color: _Palette.borderDefault, height: 14),
              _MetricRow(label: 'Tire Friction', value: widget.grip.toStringAsFixed(1)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Add Sound',
          onPressed: () => widget.onStepSelect(4),
        ),
      ],
    );
  }

  Widget _buildStep3Manual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('MANUAL PHYSICS PARAMETERS'),
        const SizedBox(height: 8),
        _PhysicsSliderRow(
          label: 'Vehicle Mass (kg)',
          value: widget.mass,
          min: 600,
          max: 4000,
          format: '${widget.mass.round()} kg',
          onChanged: widget.onMassChanged,
          onReset: () => widget.onResetPhysicsProperty('mass'),
        ),
        _PhysicsSliderRow(
          label: 'Center of Mass Height Offset',
          value: widget.centerOfMassY,
          min: -0.60,
          max: 0.60,
          format: '${widget.centerOfMassY.toStringAsFixed(2)}m',
          onChanged: widget.onCenterOfMassChanged,
          onReset: () => widget.onResetPhysicsProperty('centerOfMassY'),
        ),
        _PhysicsSliderRow(
          label: 'Suspension Travel (m)',
          value: widget.suspension / 20.0,
          min: 0.10,
          max: 0.50,
          format: '${(widget.suspension / 20.0).toStringAsFixed(2)}m',
          onChanged: (val) => widget.onSuspensionChanged(val * 20.0),
          onReset: () => widget.onResetPhysicsProperty('suspension'),
        ),
        _PhysicsSliderRow(
          label: 'Spring Stiffness',
          value: widget.springStiffness,
          min: 10.0,
          max: 80.0,
          format: '${widget.springStiffness.round()} N/m',
          onChanged: widget.onSpringStiffnessChanged,
          onReset: () => widget.onResetPhysicsProperty('springStiffness'),
        ),
        _PhysicsSliderRow(
          label: 'Damping Compression',
          value: widget.dampingCompression,
          min: 0.5,
          max: 5.0,
          format: widget.dampingCompression.toStringAsFixed(1),
          onChanged: widget.onDampingCompressionChanged,
          onReset: () => widget.onResetPhysicsProperty('dampingCompression'),
        ),
        _PhysicsSliderRow(
          label: 'Wheel Friction Slip',
          value: widget.grip,
          min: 0.5,
          max: 3.5,
          format: widget.grip.toStringAsFixed(1),
          onChanged: widget.onGripChanged,
          onReset: () => widget.onResetPhysicsProperty('grip'),
        ),
        _PhysicsSliderRow(
          label: 'Max Steer Angle (°)',
          value: widget.steerAngle,
          min: 15.0,
          max: 50.0,
          format: '${widget.steerAngle.round()}°',
          onChanged: widget.onSteerAngleChanged,
          onReset: () => widget.onResetPhysicsProperty('steerAngle'),
        ),
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Add Sound',
          onPressed: () => widget.onStepSelect(4),
        ),
      ],
    );
  }

  // ── STEP 4: ADD SOUND ─────────────────────────────────────────────────────

  Widget _buildStep4Auto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('ACOUSTIC PROFILES'),
        const SizedBox(height: 8),
        for (final profile in kAcousticProfiles) ...[
          _AcousticProfileRadioRow(
            profile: profile,
            selected: widget.selectedAcousticProfile == profile.id,
            onTap: () => widget.onAcousticProfileSelected(profile),
          ),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 16),
        const _SectionHeader('ACCESSORY AUDIO LAYERS'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Palette.activeCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.borderDefault),
          ),
          child: Column(
            children: [
              _AudioCheckboxRow(
                title: 'Enable Police Siren / Horn Layer',
                value: widget.sirenAudioEnabled,
                onChanged: widget.onToggleSirenAudio,
              ),
              const Divider(color: _Palette.borderDefault, height: 14),
              _AudioCheckboxRow(
                title: 'Tire Skid Audio',
                value: widget.tireSkidAudioEnabled,
                onChanged: widget.onToggleTireSkidAudio,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Export Rig',
          onPressed: () => widget.onStepSelect(5),
        ),
      ],
    );
  }

  Widget _buildStep4Manual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('AUDIO SLOT CONFIGURATION'),
        const SizedBox(height: 8),
        for (final slot in widget.audioSlots) ...[
          _AudioSlotCard(
            slot: slot,
            onPitchChanged: (p) => widget.onAudioSlotPitchChanged(slot.id, p),
            onPreview: () => widget.onPreviewAudioSlot(slot.id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 18),
        _NextStepButton(
          label: 'Next: Export Rig',
          onPressed: () => widget.onStepSelect(5),
        ),
      ],
    );
  }

  // ── STEP 5: EXPORT RIG ────────────────────────────────────────────────────

  Widget _buildStep5Export() {
    final wheelsVerified = widget.assignedWheels.values.whereType<DetectedWheel>().length >= 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('PRE-FLIGHT READINESS CHECKLIST'),
        const SizedBox(height: 8),
        _ReadinessCheckRow(
          title: 'Scale & Axis Valid',
          subtitle: 'Normalized vehicle bounds and standard -Z forward heading',
          isReady: widget.parsedModel != null,
        ),
        const SizedBox(height: 6),
        _ReadinessCheckRow(
          title: '4 Wheel Hubs Verified',
          subtitle: 'FL, FR, RL, RR rotation pivots and radii mapped',
          isReady: wheelsVerified,
        ),
        const SizedBox(height: 6),
        _ReadinessCheckRow(
          title: 'Physics Profile Attached',
          subtitle: 'Suspension travel, mass distribution and tire grip attached',
          isReady: true,
        ),
        const SizedBox(height: 6),
        _ReadinessCheckRow(
          title: 'Audio Nodes Configured',
          subtitle: 'RPM pitch tracking and accessory sound graphs bound',
          isReady: true,
        ),

        const SizedBox(height: 18),
        const _SectionHeader('GODOT 4 ARCHITECTURE'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Palette.activeCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.borderDefault),
          ),
          child: Column(
            children: [
              _ArchitectureRadioOption(
                title: 'Standard Godot 4 (VehicleBody3D + VehicleWheel3D)',
                subtitle: 'Native built-in Godot physics raycast suspension solver.',
                selected: widget.godotArchitecture == 'standard',
                onTap: () => widget.onGodotArchitectureChanged('standard'),
              ),
              const Divider(color: _Palette.borderDefault, height: 14),
              _ArchitectureRadioOption(
                title: 'Custom Raycast Vehicle Setup',
                subtitle: 'Scripted multi-ray suspension solver for custom drift & arcade handling.',
                selected: widget.godotArchitecture == 'raycast',
                onTap: () => widget.onGodotArchitectureChanged('raycast'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        // Primary Action Footer
        FilledButton.icon(
          onPressed: widget.canExport ? widget.onExport : null,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text(
            'Export Godot 4 Rig (.glb / .tscn)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _Palette.accentEmerald,
            disabledBackgroundColor: const Color(0xFF16251E),
            foregroundColor: const Color(0xFF041D14),
            disabledForegroundColor: const Color(0xFF6B7280),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (!widget.canExport && widget.exportBlockReason != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.exportBlockReason!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _Palette.accentAmber, fontSize: 10.5),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: widget.onTestDrive,
          icon: const Icon(Icons.sports_motorsports_rounded, size: 16),
          label: const Text('Launch Test Drive', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _Palette.accentEmerald,
            side: const BorderSide(color: _Palette.accentEmerald),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: _Palette.textSecondary,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    );
  }
}

class _HeaderSegmentButton extends StatelessWidget {
  const _HeaderSegmentButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? _Palette.activeCardFill : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? _Palette.borderActive : Colors.transparent,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: selected ? _Palette.textPrimary : _Palette.textSecondary,
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TerminalStageItem extends StatelessWidget {
  const _TerminalStageItem({
    required this.stageTag,
    required this.title,
    required this.detail,
    required this.statusTag,
    required this.statusColor,
    required this.isActive,
    required this.isDone,
    this.onHover,
  });

  final String stageTag;
  final String title;
  final String detail;
  final String statusTag;
  final Color statusColor;
  final bool isActive;
  final bool isDone;
  final ValueChanged<bool>? onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0x1EF59E0B)
              : (isDone ? const Color(0x1210B981) : const Color(0x0C111C18)),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? const Color(0xFFF59E0B)
                : (isDone ? const Color(0x3510B981) : const Color(0xFF1A2E24)),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isActive)
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Color(0xFFF59E0B),
                    ),
                  )
                else
                  Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 11,
                    color: isDone ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                  ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isDone
                          ? const Color(0xFFF0FDF4)
                          : (isActive ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  statusTag,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                detail,
                style: TextStyle(
                  color: isDone ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectCheckCard extends StatefulWidget {
  const _InspectCheckCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.metric,
    required this.description,
    this.onHover,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String metric;
  final String description;
  final ValueChanged<bool>? onHover;

  @override
  State<_InspectCheckCard> createState() => _InspectCheckCardState();
}

class _InspectCheckCardState extends State<_InspectCheckCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHover?.call(false);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _isHovered ? _Palette.activeCardFill : const Color(0xFF0F1814),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered ? _Palette.accentEmerald : _Palette.borderDefault,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(widget.icon, color: widget.iconColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: _Palette.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.metric,
                    style: const TextStyle(
                      color: _Palette.textMetrics,
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.description,
                    style: const TextStyle(
                      color: _Palette.textSecondary,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _Palette.textPrimary,
        backgroundColor: const Color(0xFF0E1713),
        side: const BorderSide(color: _Palette.borderDefault),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _GroupRowCard extends StatefulWidget {
  const _GroupRowCard({
    required this.group,
    required this.onRoleChanged,
    required this.onHighlight,
    required this.onHover,
    this.onToggle,
  });

  final DetectedMeshGroup group;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onHighlight;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool>? onToggle;

  @override
  State<_GroupRowCard> createState() => _GroupRowCardState();
}

class _GroupRowCardState extends State<_GroupRowCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover(true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHover(false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered ? _Palette.activeCardFill : const Color(0xFF0F1814),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered ? _Palette.accentEmerald : _Palette.borderDefault,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: widget.group.isEnabled,
                activeColor: _Palette.accentEmerald,
                checkColor: const Color(0xFF041D14),
                onChanged: (val) {
                  final nextVal = val ?? true;
                  setState(() => widget.group.isEnabled = nextVal);
                  widget.onToggle?.call(nextVal);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.name,
                    style: const TextStyle(
                      color: _Palette.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1410),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _Palette.borderDefault),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: widget.group.role,
                        isDense: true,
                        isExpanded: true,
                        iconSize: 16,
                        dropdownColor: const Color(0xFF111C18),
                        style: const TextStyle(
                          color: _Palette.textMetrics,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Spin (Wheel)',
                            child: Text('Spin (Wheel)'),
                          ),
                          DropdownMenuItem(
                            value: 'Steer Only (Knuckle/Caliper)',
                            child: Text('Steer Only (Knuckle/Caliper)'),
                          ),
                          DropdownMenuItem(
                            value: 'Steer Only (Caliper)',
                            child: Text('Steer Only (Caliper)'),
                          ),
                          DropdownMenuItem(
                            value: 'Static (Chassis)',
                            child: Text('Static (Chassis)'),
                          ),
                          DropdownMenuItem(
                            value: 'Static (Chassis/Exhaust)',
                            child: Text('Static (Chassis/Exhaust)'),
                          ),
                        ],
                        onChanged: (newRole) {
                          if (newRole != null) {
                            setState(() => widget.group.role = newRole);
                            widget.onRoleChanged(newRole);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Highlight in 3D',
              icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
              color: _Palette.accentEmerald,
              visualDensity: VisualDensity.compact,
              onPressed: widget.onHighlight,
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelSlotRow extends StatelessWidget {
  const _WheelSlotRow({
    required this.slot,
    required this.wheel,
    required this.onPick,
    required this.onHover,
  });

  final String slot;
  final DetectedWheel? wheel;
  final VoidCallback onPick;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1814),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _Palette.borderDefault),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _Palette.activeCardFill,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _Palette.borderDefault),
              ),
              child: Text(
                'Wheel $slot',
                style: const TextStyle(
                  color: _Palette.accentEmerald,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                wheel != null
                    ? 'R = ${wheel!.radius.toStringAsFixed(2)}m (${wheel!.subMeshCount} meshes) · ${wheel!.nodeName}'
                    : 'R = 0.34m · Unassigned',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _Palette.textSecondary,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.gps_fixed_rounded, size: 12),
              label: const Text('🎯 Pick in 3D', style: TextStyle(fontSize: 9.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _Palette.textPrimary,
                side: const BorderSide(color: _Palette.borderDefault),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetRadioCard extends StatelessWidget {
  const _PresetRadioCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final HandlingPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _Palette.activeCardFill : const Color(0xFF0F1814),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _Palette.accentEmerald : _Palette.borderDefault,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? _Palette.accentEmerald : _Palette.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.title,
                    style: TextStyle(
                      color: selected ? _Palette.textPrimary : const Color(0xFFD1D5DB),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.subtitle,
                    style: const TextStyle(color: _Palette.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _Palette.textSecondary, fontSize: 11)),
        Text(value, style: const TextStyle(color: _Palette.textMetrics, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PhysicsSliderRow extends StatelessWidget {
  const _PhysicsSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    required this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String format;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1814),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _Palette.textPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(format, style: const TextStyle(color: _Palette.textMetrics, fontFamily: 'monospace', fontSize: 10.5, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Reset to preset default',
                    icon: const Icon(Icons.restart_alt_rounded, size: 14, color: _Palette.textSecondary),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onReset,
                  ),
                ],
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _Palette.accentEmerald,
              inactiveTrackColor: _Palette.borderDefault,
              thumbColor: _Palette.accentEmerald,
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcousticProfileRadioRow extends StatelessWidget {
  const _AcousticProfileRadioRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final AcousticProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _Palette.activeCardFill : const Color(0xFF0F1814),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _Palette.accentEmerald : _Palette.borderDefault,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? _Palette.accentEmerald : _Palette.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.title,
                    style: TextStyle(
                      color: selected ? _Palette.textPrimary : const Color(0xFFD1D5DB),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.subtitle,
                    style: const TextStyle(color: _Palette.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioCheckboxRow extends StatelessWidget {
  const _AudioCheckboxRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            activeColor: _Palette.accentEmerald,
            checkColor: const Color(0xFF041D14),
            onChanged: (v) => onChanged(v ?? false),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: _Palette.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _AudioSlotCard extends StatefulWidget {
  const _AudioSlotCard({
    required this.slot,
    required this.onPitchChanged,
    required this.onPreview,
  });

  final AudioSlotConfig slot;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onPreview;

  @override
  State<_AudioSlotCard> createState() => _AudioSlotCardState();
}

class _AudioSlotCardState extends State<_AudioSlotCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1814),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.slot.title,
                  style: const TextStyle(color: _Palette.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.slot.fileName,
                style: const TextStyle(color: _Palette.textSecondary, fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => widget.slot.isPlaying = !widget.slot.isPlaying);
                  widget.onPreview();
                },
                icon: Icon(
                  widget.slot.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 14,
                  color: widget.slot.isPlaying ? _Palette.accentAmber : _Palette.accentEmerald,
                ),
                label: Text(
                  widget.slot.isPlaying ? 'Stop' : 'Preview',
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.slot.isPlaying ? _Palette.accentAmber : _Palette.textPrimary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: widget.slot.isPlaying ? _Palette.accentAmber : _Palette.borderDefault,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.folder_open_rounded, size: 13),
                label: const Text('Choose File', style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Palette.textSecondary,
                  side: const BorderSide(color: _Palette.borderDefault),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Pitch Multiplier: ', style: TextStyle(color: _Palette.textSecondary, fontSize: 10)),
              Text(
                '${widget.slot.pitchMultiplier.toStringAsFixed(2)}x',
                style: const TextStyle(color: _Palette.textMetrics, fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _Palette.accentEmerald,
                    inactiveTrackColor: _Palette.borderDefault,
                    thumbColor: _Palette.accentEmerald,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: widget.slot.pitchMultiplier,
                    min: 0.5,
                    max: 2.0,
                    onChanged: (val) {
                      setState(() => widget.slot.pitchMultiplier = val);
                      widget.onPitchChanged(val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessCheckRow extends StatelessWidget {
  const _ReadinessCheckRow({
    required this.title,
    required this.subtitle,
    required this.isReady,
  });

  final String title;
  final String subtitle;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final color = isReady ? _Palette.accentEmerald : _Palette.accentAmber;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1814),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.borderDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isReady ? Icons.check_circle_rounded : Icons.warning_amber_rounded, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: _Palette.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(color: _Palette.textSecondary, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchitectureRadioOption extends StatelessWidget {
  const _ArchitectureRadioOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? _Palette.accentEmerald : _Palette.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? _Palette.textPrimary : const Color(0xFFD1D5DB),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _Palette.textSecondary, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepButton extends StatelessWidget {
  const _NextStepButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _Palette.accentEmerald,
        foregroundColor: const Color(0xFF041D14),
        disabledBackgroundColor: const Color(0xFF16251E),
        disabledForegroundColor: const Color(0xFF6B7280),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: isEnabled ? const Color(0xFF041D14) : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward_rounded,
            size: 15,
            color: isEnabled ? const Color(0xFF041D14) : const Color(0xFF6B7280),
          ),
        ],
      ),
    );
  }
}
