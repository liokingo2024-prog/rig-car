import 'dart:convert';
import 'package:flutter/material.dart';

import 'download_config.dart';
import 'main.dart';
import 'pre_rigged_cars.dart';

class RigHomeScreen extends StatefulWidget {
  const RigHomeScreen({super.key});

  @override
  State<RigHomeScreen> createState() => _RigHomeScreenState();
}

class _RigHomeScreenState extends State<RigHomeScreen> {
  String _selectedCategory = 'All';

  List<PreRiggedCar> get _filteredCars {
    if (_selectedCategory == 'All') return preRiggedCars;
    return preRiggedCars
        .where((car) => car.category == _selectedCategory)
        .toList();
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
          content: Text('Exported Godot 4 package for ${car.name}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF25343E),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1080;
          final isTablet = constraints.maxWidth >= 700;

          return Column(
            children: [
              // ── Top Navigation Bar ────────────────────────────────────────
              _HomeNavbar(onRigYourCar: () => _openWorkbench()),

              // ── Scrollable Body ───────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 36 : 16,
                    24,
                    isDesktop ? 36 : 16,
                    48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Hero Banner ───────────────────────────────────────
                      _HeroBanner(
                        isDesktop: isDesktop,
                        onRigYourCar: () => _openWorkbench(),
                      ),
                      const SizedBox(height: 32),

                      // ── Fleet Library Header & Categories ─────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PRE-RIGGED VEHICLE FLEET',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Calibrated Godot 4 VehicleBody3D setups with custom physics and wheel topologies',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (isDesktop) ...[
                            const SizedBox(width: 16),
                            FilledButton.icon(
                              onPressed: () => _openWorkbench(),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Rig Your Custom Car'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF713D),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Category Filters
                      _CategoryFilters(
                        selectedCategory: _selectedCategory,
                        onCategorySelected: (cat) {
                          setState(() => _selectedCategory = cat);
                        },
                      ),
                      const SizedBox(height: 24),

                      // ── Vehicle Cards Grid ────────────────────────────────
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

// ── Top Navbar ──────────────────────────────────────────────────────────────

class _HomeNavbar extends StatelessWidget {
  const _HomeNavbar({required this.onRigYourCar});
  final VoidCallback onRigYourCar;

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
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFF713D),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RIG-CAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'GODOT 4 FLEET & AUTO-RIGGER',
                style: TextStyle(
                  color: Color(0xFF82919B),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onRigYourCar,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Rig Your Car'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF713D),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF221A18),
            Color(0xFF17232B),
            Color(0xFF10181F),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A4B56)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x33FF713D),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF713D)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 13, color: Color(0xFFFF986D)),
                    SizedBox(width: 4),
                    Text(
                      'MIXAMO-STYLE CAR RIGGING',
                      style: TextStyle(
                        color: Color(0xFFFFB15C),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'GODOT 4.x READY',
                style: TextStyle(
                  color: Color(0xFF70838F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Vehicle Rigging & Fleet Library',
            style: TextStyle(
              color: Colors.white,
              fontSize: isDesktop ? 28 : 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: const Text(
              'Instantly export pre-calibrated Godot 4 VehicleBody3D rigs, or upload your custom 3D model (.glb / .gltf) for automated wheel detection and real coordinate extraction.',
              style: TextStyle(
                color: Color(0xFFBAC7CE),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onRigYourCar,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Rig Your Custom 3D Car'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF713D),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.directions_car_outlined, size: 18),
                label: const Text('Explore Pre-Rigged Fleet ↓'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE2E9EC),
                  side: const BorderSide(color: Color(0xFF3E505B)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
    'All',
    'Sports',
    'Off-Road',
    'Utility',
    'Electric',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => onCategorySelected(cat),
              backgroundColor: const Color(0xFF141F27),
              selectedColor: const Color(0xFFFF713D),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF713D)
                    : const Color(0xFF283640),
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF8FA0AA),
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
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        mainAxisExtent: 380,
      ),
      itemBuilder: (context, index) {
        final car = cars[index];
        return _VehicleCard(
          car: car,
          onOpenWorkbench: () => onOpenWorkbench(car),
          onExport: () => onExport(car),
        );
      },
    );
  }
}

// ── Vehicle Card ────────────────────────────────────────────────────────────

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.car,
    required this.onOpenWorkbench,
    required this.onExport,
  });

  final PreRiggedCar car;
  final VoidCallback onOpenWorkbench;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF152028),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF263640)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header / Graphic ─────────────────────────────────────────
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  car.accentColor.withValues(alpha: 0.35),
                  const Color(0xFF0F171D),
                ],
              ),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF263640)),
              ),
            ),
            child: Stack(
              children: [
                // Top Tag
                Positioned(
                  top: 12,
                  left: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xC010181E),
                      borderRadius: BorderRadius.circular(6),
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
                // Drive Badge
                Positioned(
                  top: 12,
                  right: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2D37),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      car.drive,
                      style: const TextStyle(
                        color: Color(0xFFE2E9EC),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                // Center Icon / Graphic
                Center(
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    size: 54,
                    color: car.accentColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          // ── Card Content ──────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    car.name,
                    style: const TextStyle(
                      color: Color(0xFFEEF2F4),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
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

                  // Metrics Row
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10171D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CardStat('MASS', '${car.mass.toInt()}kg'),
                        _CardStat('FORCE', '${car.engineForce.toInt()}N'),
                        _CardStat('GRIP', car.grip.toStringAsFixed(2)),
                        _CardStat('SUSP', car.suspension.toStringAsFixed(1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onExport,
                          icon: const Icon(Icons.file_download_outlined, size: 15),
                          label: const Text('Export Rig'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFBAC6CC),
                            side: const BorderSide(color: Color(0xFF334551)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onOpenWorkbench,
                          icon: const Icon(Icons.tune_rounded, size: 15),
                          label: const Text('Rig & Tune'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF713D),
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5E6F7A),
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFD8E2E7),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
