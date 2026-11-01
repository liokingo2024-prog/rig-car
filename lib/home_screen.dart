import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'download_config.dart';
import 'main.dart';
import 'model_data.dart';
import 'pre_rigged_cars.dart';

class RigHomeScreen extends StatefulWidget {
  const RigHomeScreen({super.key});

  @override
  State<RigHomeScreen> createState() => _RigHomeScreenState();
}

class _RigHomeScreenState extends State<RigHomeScreen>
    with SingleTickerProviderStateMixin {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  List<PreRiggedCar> get _filteredCars {
    return preRiggedCars.where((car) {
      final matchesCategory =
          _selectedCategory == 'All' || car.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          car.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          car.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          car.drive.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _openWorkbench([PreRiggedCar? car]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RigWorkbenchPage(initialCar: car),
      ),
    );
  }

  Future<void> _exportCar(PreRiggedCar car) async {
    final config = car.toRigConfig();
    await downloadTextFile(
      '${car.id}_config.json',
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      'application/json',
    );
    await downloadTextFile(
      '${car.id}.gd',
      config.toGdScript(),
      'text/plain',
    );
    await downloadTextFile(
      '${car.id}.tscn',
      config.toTscn(),
      'text/plain',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF6BD2A0), size: 18),
              const SizedBox(width: 10),
              Text('Exported Godot 4 package for ${car.name}'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1B2832),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1080;
          final isTablet = constraints.maxWidth >= 720;

          return Column(
            children: [
              // ── Futuristic Top Navigation Bar ─────────────────────────────
              _HomeNavbar(
                onRigYourCar: () => _openWorkbench(),
                isDesktop: isDesktop,
              ),

              // ── Main Content Area with Ambient Animated Background ────────
              Expanded(
                child: Stack(
                  children: [
                    // Ambient Cyber Glow
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _ambientController,
                        builder: (context, _) {
                          final angle = _ambientController.value * 2 * pi;
                          return CustomPaint(
                            painter: _AmbientCyberGlowPainter(angle: angle),
                          );
                        },
                      ),
                    ),

                    // Scrollable Cards & Hero
                    SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 42 : 18,
                        28,
                        isDesktop ? 42 : 18,
                        60,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Hero Banner ───────────────────────────────────
                          _HeroBanner(
                            isDesktop: isDesktop,
                            onRigYourCar: () => _openWorkbench(),
                          ),
                          const SizedBox(height: 36),

                          // ── Fleet Section Header & Search ─────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF713D),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0x80FF713D),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'PRE-RIGGED VEHICLE FLEET',
                                          style: TextStyle(
                                            color: Color(0xFFEEF3F6),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Production-ready Godot 4 VehicleBody3D models with calibrated suspension, steering & traction',
                                      style: TextStyle(
                                        color: Color(0xFF8697A2),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isDesktop) ...[
                                const SizedBox(width: 24),
                                // Search Input
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    onChanged: (val) {
                                      setState(() => _searchQuery = val);
                                    },
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      hintText: 'Search fleet...',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFF647580),
                                        fontSize: 12,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                        size: 16,
                                        color: Color(0xFF8294A0),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF263642),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Category Filters Bar
                          _CategoryFilters(
                            selectedCategory: _selectedCategory,
                            onCategorySelected: (cat) {
                              setState(() => _selectedCategory = cat);
                            },
                          ),
                          const SizedBox(height: 24),

                          // ── Vehicle Cards Grid ────────────────────────────
                          _VehicleGrid(
                            cars: _filteredCars,
                            isDesktop: isDesktop,
                            isTablet: isTablet,
                            onOpenWorkbench: _openWorkbench,
                            onExport: _exportCar,
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

// ── Top Navigation Bar ──────────────────────────────────────────────────────

class _HomeNavbar extends StatelessWidget {
  const _HomeNavbar({required this.onRigYourCar, required this.isDesktop});
  final VoidCallback onRigYourCar;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F161C),
        border: Border(bottom: BorderSide(color: Color(0xFF22313B))),
      ),
      child: Row(
        children: [
          // Logo & Title
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF713D), Color(0xFFFF416C)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40FF713D),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RIG-CAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                'GODOT 4 AUTO-RIGGER & FLEET',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Spacer(),

          // System telemetry indicator
          if (isDesktop) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF141F27),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF253744)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFF00E676)),
                  SizedBox(width: 6),
                  Text(
                    'ENGINE 4.x READY',
                    style: TextStyle(
                      color: Color(0xFF8BA2B0),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Primary "Rig Your Car" CTA Button
          FilledButton.icon(
            onPressed: onRigYourCar,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Rig Your Car'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF713D),
              elevation: 4,
              shadowColor: const Color(0x60FF713D),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero Banner ─────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.isDesktop, required this.onRigYourCar});
  final bool isDesktop;
  final VoidCallback onRigYourCar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isDesktop ? 36 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF241C1A),
            Color(0xFF16222A),
            Color(0xFF0E151A),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF384B56), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Cyber Lines
          Positioned.fill(
            child: CustomPaint(painter: _HeroGridLinesPainter()),
          ),

          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge row
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _HeroPill(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'MIXAMO-STYLE CAR RIGGING',
                    color: const Color(0xFFFF713D),
                  ),
                  _HeroPill(
                    icon: Icons.gps_fixed_rounded,
                    label: 'REAL WHEEL 3D COORDINATES',
                    color: const Color(0xFF00E5FF),
                  ),
                  _HeroPill(
                    icon: Icons.code_rounded,
                    label: 'INSTANT .TSCN + .GD EMITTER',
                    color: const Color(0xFF6BD2A0),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Godot 4 Car Auto-Rigger & Fleet Library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 32 : 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const Text(
                  'Drop any 3D car asset (.glb / .gltf) into the browser to auto-detect wheels, axles, and car body topology with interactive 3D review, or instantly export from our curated collection of calibrated Godot 4 vehicle rigs.',
                  style: TextStyle(
                    color: Color(0xFFB4C2C9),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 26),

              // Action buttons
              Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onRigYourCar,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 19),
                    label: const Text('Rig Your Custom 3D Car'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF713D),
                      elevation: 6,
                      shadowColor: const Color(0x60FF713D),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                    label: const Text('Browse 6 Pre-Rigged Rigs ↓'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE2EBF0),
                      side: const BorderSide(color: Color(0xFF3F5460)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category Filters ────────────────────────────────────────────────────────

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  static const categories = [
    {'name': 'All', 'icon': Icons.apps_rounded, 'count': '6'},
    {'name': 'Sports', 'icon': Icons.speed_rounded, 'count': '2'},
    {'name': 'Off-Road', 'icon': Icons.terrain_rounded, 'count': '1'},
    {'name': 'Utility', 'icon': Icons.local_shipping_rounded, 'count': '2'},
    {'name': 'Electric', 'icon': Icons.electric_bolt_rounded, 'count': '1'},
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final name = cat['name'] as String;
          final icon = cat['icon'] as IconData;
          final count = cat['count'] as String;
          final isSelected = selectedCategory == name;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              avatar: Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : const Color(0xFF7E929F),
              ),
              label: Text('$name ($count)'),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => onCategorySelected(name),
              backgroundColor: const Color(0xFF131D24),
              selectedColor: const Color(0xFFFF713D),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF713D)
                    : const Color(0xFF263742),
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF8EA0AA),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Vehicle Grid ────────────────────────────────────────────────────────────

class _VehicleGrid extends StatelessWidget {
  const _VehicleGrid({
    required this.cars,
    required this.isDesktop,
    required this.isTablet,
    required this.onOpenWorkbench,
    required this.onExport,
  });

  final List<PreRiggedCar> cars;
  final bool isDesktop;
  final bool isTablet;
  final void Function(PreRiggedCar) onOpenWorkbench;
  final void Function(PreRiggedCar) onExport;

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = isDesktop ? 3 : (isTablet ? 2 : 1);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cars.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        mainAxisExtent: 440,
      ),
      itemBuilder: (context, index) {
        final car = cars[index];
        return _InteractiveVehicleCard(
          car: car,
          onOpenWorkbench: () => onOpenWorkbench(car),
          onExport: () => onExport(car),
        );
      },
    );
  }
}

// ── Interactive Animated Vehicle Card ───────────────────────────────────────

class _InteractiveVehicleCard extends StatefulWidget {
  const _InteractiveVehicleCard({
    required this.car,
    required this.onOpenWorkbench,
    required this.onExport,
  });

  final PreRiggedCar car;
  final VoidCallback onOpenWorkbench;
  final VoidCallback onExport;

  @override
  State<_InteractiveVehicleCard> createState() =>
      _InteractiveVehicleCardState();
}

class _InteractiveVehicleCardState extends State<_InteractiveVehicleCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _cardTurntable;

  @override
  void initState() {
    super.initState();
    _cardTurntable = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _cardTurntable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovered ? -5 : 0, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF141F27),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? car.accentColor
                : const Color(0xFF263742),
            width: _isHovered ? 1.6 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? car.accentColor.withValues(alpha: 0.25)
                  : const Color(0x30000000),
              blurRadius: _isHovered ? 18 : 8,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card Header: Animated 3D Mini Wireframe Turntable ───────────
            Container(
              height: 145,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    car.accentColor.withValues(alpha: 0.25),
                    const Color(0xFF0F161C),
                  ],
                ),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF243440)),
                ),
              ),
              child: Stack(
                children: [
                  // 3D Mini Wireframe Turntable
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _cardTurntable,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _MiniCarTurntablePainter(
                            angle: _cardTurntable.value * 2 * pi,
                            accentColor: car.accentColor,
                            secondaryColor: car.secondaryColor,
                            category: car.category,
                            wheelPositions: car.wheelPositions,
                          ),
                        );
                      },
                    ),
                  ),

                  // Category tag
                  Positioned(
                    top: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xC0101820),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: car.accentColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        car.category.toUpperCase(),
                        style: TextStyle(
                          color: car.accentColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),

                  // Drive tag
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2F3A),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        car.drive,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Card Body ───────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      car.name,
                      style: const TextStyle(
                        color: Color(0xFFEEF3F6),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Description
                    Text(
                      car.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8697A2),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const Spacer(),

                    // High-Tech Telemetry Stats Grid
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F171D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF22323D)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StatCell('POWER', '${car.estimatedHp}HP'),
                          _StatCell('0-100', '${car.zeroToHundred}s'),
                          _StatCell('TOP', '${car.topSpeedKmh}km/h'),
                          _StatCell('MASS', '${car.mass.toInt()}kg'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.onExport,
                            icon: const Icon(Icons.file_download_outlined,
                                size: 14),
                            label: const Text('Export Rig'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFBAC8CF),
                              side: const BorderSide(color: Color(0xFF334652)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: widget.onOpenWorkbench,
                            icon: const Icon(Icons.tune_rounded, size: 14),
                            label: const Text('Rig & Tune'),
                            style: FilledButton.styleFrom(
                              backgroundColor: car.accentColor,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5B6E7A),
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFD4E0E6),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ── Mini 3D Car Turntable Painter ───────────────────────────────────────────

class _MiniCarTurntablePainter extends CustomPainter {
  _MiniCarTurntablePainter({
    required this.angle,
    required this.accentColor,
    required this.secondaryColor,
    required this.category,
    required this.wheelPositions,
  });

  final double angle;
  final Color accentColor;
  final Color secondaryColor;
  final String category;
  final List<Vec3> wheelPositions;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width * 0.5, size.height * 0.56);
    final cosA = cos(angle);
    final sinA = sin(angle);

    // 3D rotation around Y and isometric projection to 2D
    Offset project(double x, double y, double z) {
      // Rotate around Y
      final rx = x * cosA - z * sinA;
      final rz = x * sinA + z * cosA;
      // Isometric projection
      final scale = size.height * 0.28;
      final px = center.dx + rx * scale;
      final py = center.dy - y * scale + rz * (scale * 0.35);
      return Offset(px, py);
    }

    final bodyPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    final wheelPaint = Paint()
      ..color = const Color(0xFFFFB15C)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    // Archetype-specific vertices
    final isTruck = category == 'Utility';
    final isOffRoad = category == 'Off-Road';
    final roofY = isTruck ? 1.2 : (isOffRoad ? 1.1 : 0.85);
    final groundY = isOffRoad ? 0.35 : 0.15;

    final vertices = [
      project(-0.8, groundY, -1.5), // 0: FL bottom
      project(0.8, groundY, -1.5),  // 1: FR bottom
      project(0.8, groundY, 1.5),   // 2: RR bottom
      project(-0.8, groundY, 1.5),  // 3: RL bottom
      project(-0.7, 0.55, -1.4),    // 4: Hood FL
      project(0.7, 0.55, -1.4),     // 5: Hood FR
      project(-0.6, roofY, -0.2),   // 6: Roof FL
      project(0.6, roofY, -0.2),    // 7: Roof FR
      project(-0.6, roofY, 0.9),    // 8: Roof RL
      project(0.6, roofY, 0.9),     // 9: Roof RR
      project(-0.7, 0.6, 1.45),     // 10: Trunk RL
      project(0.7, 0.6, 1.45),      // 11: Trunk RR
    ];

    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0], // Bottom frame
      [0, 4], [1, 5], [4, 5],         // Hood
      [4, 6], [5, 7], [6, 7],         // Windshield
      [6, 8], [7, 9], [8, 9],         // Roof
      [8, 10], [9, 11], [10, 11],     // Rear window
      [10, 3], [11, 2],               // Trunk down
    ];

    for (final e in edges) {
      canvas.drawLine(vertices[e[0]], vertices[e[1]], bodyPaint);
    }

    // 4 Wheels
    final wheelRadius = isOffRoad ? 0.32 : 0.24;
    for (final wp in wheelPositions) {
      final p = project(wp.x, wp.y, wp.z);
      canvas.drawCircle(p, wheelRadius * (size.height * 0.28), wheelPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniCarTurntablePainter oldDelegate) =>
      oldDelegate.angle != angle;
}

// ── Background Cyber Grid Lines ─────────────────────────────────────────────

class _HeroGridLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1200E5FF)
      ..strokeWidth = 1.0;

    for (var x = 0.0; x < size.width; x += 36.0) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 36.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Ambient Cyber Glow Background ───────────────────────────────────────────

class _AmbientCyberGlowPainter extends CustomPainter {
  _AmbientCyberGlowPainter({required this.angle});
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle animated orange orb
    final orb1 = Offset(
      size.width * 0.8 + 60 * cos(angle),
      size.height * 0.2 + 40 * sin(angle),
    );
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x18FF713D),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb1, radius: 280));
    canvas.drawCircle(orb1, 280, paint1);

    // Subtle animated cyan orb
    final orb2 = Offset(
      size.width * 0.2 + 50 * sin(angle),
      size.height * 0.7 + 35 * cos(angle),
    );
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x1500F5FF),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb2, radius: 300));
    canvas.drawCircle(orb2, 300, paint2);
  }

  @override
  bool shouldRepaint(covariant _AmbientCyberGlowPainter oldDelegate) =>
      oldDelegate.angle != angle;
}
