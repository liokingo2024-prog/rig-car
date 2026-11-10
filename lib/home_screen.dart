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

class _RigHomeScreenState extends State<RigHomeScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

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

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFleet() {
    _scrollController.animateTo(
      380.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
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

              // ── Main Content Area ─────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
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
                        onBrowseFleet: _scrollToFleet,
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
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'PRE-RIGGED VEHICLE FLEET',
                                      style: TextStyle(
                                        color: Color(0xFFF0FDF4),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Production-ready Godot 4 VehicleBody3D models with calibrated suspension, steering & traction',
                                  style: TextStyle(
                                    color: Color(0xFF86978C),
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
                                    color: Color(0xFF6E7681),
                                    fontSize: 12,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 16,
                                    color: Color(0xFF86978C),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF223127),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!isDesktop) ...[
                        const SizedBox(height: 14),
                        TextField(
                          onChanged: (val) {
                            setState(() => _searchQuery = val);
                          },
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search fleet...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF6E7681),
                              fontSize: 12,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: Color(0xFF86978C),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF223127),
                              ),
                            ),
                          ),
                        ),
                      ],
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
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111714),
        border: Border(bottom: BorderSide(color: Color(0xFF223127))),
      ),
      child: Row(
        children: [
          // Logo & Title
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF1A231E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF223127)),
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 19),
          ),
          const SizedBox(width: 12),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RIG-CAR',
                style: TextStyle(
                  color: Color(0xFFF0FDF4),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                'GODOT 4 VEHICLE TOOLKIT',
                style: TextStyle(
                  color: Color(0xFF86978C),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
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
                color: const Color(0xFF0D120F),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF223127)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text(
                    'Godot 4.x Compatible',
                    style: TextStyle(
                      color: Color(0xFF86978C),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Rig Your Car'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF041D14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
  const _HeroBanner({
    required this.isDesktop,
    required this.onRigYourCar,
    this.onBrowseFleet,
  });
  final bool isDesktop;
  final VoidCallback onRigYourCar;
  final VoidCallback? onBrowseFleet;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF111714),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223127)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Professional Eyebrow Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF16201B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF223127)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 12, color: Color(0xFF10B981)),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Godot 4 Vehicle Rigging & Simulation Toolkit',
                    style: TextStyle(
                      color: Color(0xFFD1FAE5),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Title
          Text(
            'Godot 4 Car Auto-Rigger & Fleet Library',
            style: TextStyle(
              color: const Color(0xFFF0FDF4),
              fontSize: isDesktop ? 30 : 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),

          // Subtitle
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const Text(
              'Drop any 3D car asset (.glb / .gltf) into the browser to auto-detect wheels, axles, and car body topology with interactive 3D review, or instantly export from our curated collection of calibrated Godot 4 vehicle rigs.',
              style: TextStyle(
                color: Color(0xFF86978C),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onRigYourCar,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Rig Your Custom 3D Car'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF041D14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RigWorkbenchPage(
                        initialCar: preRiggedCars.first,
                        startInTestDrive: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.sports_motorsports_rounded, size: 18),
                label: const Text('Test Drive Simulator (Godot 4)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A231E),
                  foregroundColor: const Color(0xFFF0FDF4),
                  side: const BorderSide(color: Color(0xFF223127)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onBrowseFleet,
                icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                label: const Text('Browse 6 Pre-Rigged Rigs ↓'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC9D1D9),
                  side: const BorderSide(color: Color(0xFF223127)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
                color: isSelected ? const Color(0xFF041D14) : const Color(0xFF86978C),
              ),
              label: Text('$name ($count)'),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => onCategorySelected(name),
              backgroundColor: const Color(0xFF111714),
              selectedColor: const Color(0xFF10B981),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF10B981)
                    : const Color(0xFF223127),
              ),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF041D14) : const Color(0xFFC9D1D9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF111714),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? const Color(0xFF10B981)
                : const Color(0xFF223127),
            width: _isHovered ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.45 : 0.2),
              blurRadius: _isHovered ? 14 : 4,
              offset: Offset(0, _isHovered ? 6 : 2),
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
              decoration: const BoxDecoration(
                color: Color(0xFF090D0B),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF16201B)),
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
                        color: const Color(0xFF16201B),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: const Color(0xFF223127),
                        ),
                      ),
                      child: Text(
                        car.category.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF86978C),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),

                  // Drive & Test Drive tags
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RigWorkbenchPage(
                                  initialCar: car,
                                  startInTestDrive: true,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A231E),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF223127),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sports_motorsports_rounded,
                                  size: 11,
                                  color: Color(0xFF34D399),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'TEST DRIVE',
                                  style: TextStyle(
                                    color: Color(0xFFC9D1D9),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A231E),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFF223127)),
                          ),
                          child: Text(
                            car.drive,
                            style: const TextStyle(
                              color: Color(0xFFC9D1D9),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
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
                        color: Color(0xFFF0FDF4),
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
                        color: Color(0xFF86978C),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const Spacer(),

                    // Precision Telemetry Stats Grid
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D0B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF16201B)),
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
                              foregroundColor: const Color(0xFFC9D1D9),
                              side: const BorderSide(color: Color(0xFF223127)),
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
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: const Color(0xFF041D14),
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
            color: Color(0xFF8B949E),
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFF0F6FC),
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
      ..color = const Color(0xFF34D399)
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
