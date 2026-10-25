import 'package:flutter/material.dart';

void main() {
  runApp(const RigCarApp());
}

class RigCarApp extends StatelessWidget {
  const RigCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17212B);
    const canvas = Color(0xFFF5F7F8);

    return MaterialApp(
      title: 'RIG-CAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFFF6B35),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: ink,
        ),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          displaySmall: TextStyle(
            color: ink,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
          headlineSmall: TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
          titleLarge: TextStyle(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: ink, fontSize: 15),
          bodyMedium: TextStyle(color: Color(0xFF66737D), fontSize: 13),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _searchController = TextEditingController();
  String _activeFilter = 'All vehicles';
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Vehicle> get _visibleVehicles {
    final normalizedSearch = _searchTerm.trim().toLowerCase();
    return vehicles.where((vehicle) {
      final matchesFilter = _activeFilter == 'All vehicles' ||
          vehicle.category == _activeFilter;
      final matchesSearch = normalizedSearch.isEmpty ||
          '${vehicle.name} ${vehicle.category} ${vehicle.location}'
              .toLowerCase()
              .contains(normalizedSearch);
      return matchesFilter && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 980;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSidebar) const _Sidebar(),
              Expanded(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      showSidebar ? 36 : 20,
                      28,
                      showSidebar ? 44 : 20,
                      44,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(showSidebar: showSidebar),
                        const SizedBox(height: 30),
                        const _WelcomeBanner(),
                        const SizedBox(height: 24),
                        const _SectionHeading(
                          title: 'Fleet overview',
                          actionLabel: 'View reports',
                        ),
                        const SizedBox(height: 14),
                        const _StatsRow(),
                        const SizedBox(height: 30),
                        _SectionHeading(
                          title: 'Your vehicles',
                          actionLabel: '${_visibleVehicles.length} available',
                        ),
                        const SizedBox(height: 14),
                        _SearchAndFilters(
                          controller: _searchController,
                          activeFilter: _activeFilter,
                          onSearchChanged: (value) {
                            setState(() => _searchTerm = value);
                          },
                          onFilterSelected: (filter) {
                            setState(() => _activeFilter = filter);
                          },
                        ),
                        const SizedBox(height: 18),
                        _VehicleGrid(vehicles: _visibleVehicles),
                        if (_visibleVehicles.isEmpty) const _EmptyState(),
                      ],
                    ),
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

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF17212B);
    return Container(
      width: 236,
      color: dark,
      padding: const EdgeInsets.fromLTRB(22, 30, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Brand(compact: false, light: true),
          const SizedBox(height: 58),
          Text(
            'WORKSPACE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          const _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Dashboard',
            active: true,
          ),
          const _NavItem(icon: Icons.directions_car_filled, label: 'Vehicles'),
          const _NavItem(icon: Icons.calendar_month_rounded, label: 'Bookings'),
          const _NavItem(icon: Icons.people_alt_rounded, label: 'Customers'),
          const SizedBox(height: 30),
          Text(
            'MANAGE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          const _NavItem(icon: Icons.analytics_outlined, label: 'Analytics'),
          const _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: Color(0xFFFFB15C),
                  child: Text(
                    'AJ',
                    style: TextStyle(
                      color: Color(0xFF17212B),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alex Johnson',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Fleet manager',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
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

class _Brand extends StatelessWidget {
  const _Brand({required this.compact, required this.light});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : const Color(0xFF17212B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Text(
            'RIG-CAR',
            style: TextStyle(
              color: foreground,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, this.active = false});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Colors.white54;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFF6B35) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, color: foreground, size: 19),
        title: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showSidebar});

  final bool showSidebar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!showSidebar) const _Brand(compact: false, light: false),
        const Spacer(),
        IconButton(
          onPressed: () {},
          tooltip: 'Notifications',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF17212B),
          ),
          icon: const Badge(
            smallSize: 7,
            backgroundColor: Color(0xFFFF6B35),
            child: Icon(Icons.notifications_none_rounded, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 19,
          backgroundColor: Color(0xFFFFB15C),
          child: Text(
            'AJ',
            style: TextStyle(
              color: Color(0xFF17212B),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4D2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 22,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning, Alex',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                      ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Keep your fleet moving. Everything you need to manage your cars is right here.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF7A4B37),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add vehicle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF17212B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _BannerIllustration(),
        ],
      ),
    );
  }
}

class _BannerIllustration extends StatelessWidget {
  const _BannerIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            top: 5,
            child: Container(
              width: 126,
              height: 126,
              decoration: const BoxDecoration(
                color: Color(0xFFFFB15C),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            bottom: 18,
            left: 0,
            child: Icon(
              Icons.directions_car_filled_rounded,
              color: Color(0xFF17212B),
              size: 122,
            ),
          ),
          const Positioned(
            right: 19,
            bottom: 12,
            child: Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        TextButton(
          onPressed: () {},
          child: Text(
            actionLabel,
            style: const TextStyle(
              color: Color(0xFFFF6B35),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final items = [
          const _StatCard(
            icon: Icons.directions_car_filled_rounded,
            value: '24',
            label: 'Total vehicles',
            trend: '+12%',
            color: Color(0xFFE2F0FF),
            iconColor: Color(0xFF3B82F6),
          ),
          const _StatCard(
            icon: Icons.check_circle_rounded,
            value: '08',
            label: 'On the road',
            trend: '+8%',
            color: Color(0xFFE1F7EF),
            iconColor: Color(0xFF18A673),
          ),
          const _StatCard(
            icon: Icons.build_circle_rounded,
            value: '03',
            label: 'In service',
            trend: '-2%',
            color: Color(0xFFFFF0D9),
            iconColor: Color(0xFFE58A00),
          ),
        ];
        return Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                SizedBox(
                  width: compact ? 0 : 14,
                  height: compact ? 12 : 0,
                ),
              if (compact)
                SizedBox(width: double.infinity, child: items[index])
              else
                Expanded(child: items[index]),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.trend,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final String trend;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(width: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const Spacer(),
          Text(
            trend,
            style: TextStyle(
              color: trend.startsWith('-')
                  ? const Color(0xFFE58A00)
                  : const Color(0xFF18A673),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.activeFilter,
    required this.onSearchChanged,
    required this.onFilterSelected,
  });

  final TextEditingController controller;
  final String activeFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    const filters = ['All vehicles', 'SUV', 'Sedan', 'Truck'];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search vehicles',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE7EBEE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE7EBEE)),
              ),
            ),
          ),
        ),
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter),
            selected: activeFilter == filter,
            onSelected: (_) => onFilterSelected(filter),
            selectedColor: const Color(0xFFFF6B35),
            labelStyle: TextStyle(
              color: activeFilter == filter
                  ? Colors.white
                  : const Color(0xFF66737D),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: const BorderSide(color: Color(0xFFE1E6E9)),
            backgroundColor: Colors.white,
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _VehicleGrid extends StatelessWidget {
  const _VehicleGrid({required this.vehicles});

  final List<Vehicle> vehicles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: vehicles.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 248,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, index) => _VehicleCard(vehicle: vehicles[index]),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: vehicle.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _StatusPill(status: vehicle.status),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      size: 76,
                      color: vehicle.iconColor,
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 10,
                    child: Text(
                      vehicle.year,
                      style: TextStyle(
                        color: vehicle.iconColor.withValues(alpha: .65),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${vehicle.category}  •  ${vehicle.location}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                vehicle.price,
                style: const TextStyle(
                  color: Color(0xFFFF6B35),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final available = status == 'Available';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: available ? Colors.white : const Color(0xFFFFF0D9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: available
                  ? const Color(0xFF18A673)
                  : const Color(0xFFE58A00),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              color: available
                  ? const Color(0xFF167753)
                  : const Color(0xFF9A5D00),
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBEE)),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off_rounded, size: 34, color: Color(0xFF9AA5AC)),
          SizedBox(height: 10),
          Text(
            'No vehicles match your search.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.name,
    required this.category,
    required this.location,
    required this.year,
    required this.price,
    required this.status,
    required this.colors,
    required this.iconColor,
  });

  final String name;
  final String category;
  final String location;
  final String year;
  final String price;
  final String status;
  final List<Color> colors;
  final Color iconColor;
}

const vehicles = [
  Vehicle(
    name: 'Ranger XLT',
    category: 'Truck',
    location: 'Austin',
    year: '2024',
    price: '\$68/day',
    status: 'Available',
    colors: [Color(0xFFDCE8F4), Color(0xFFB9D1E6)],
    iconColor: Color(0xFF284B63),
  ),
  Vehicle(
    name: 'Civic Touring',
    category: 'Sedan',
    location: 'Dallas',
    year: '2023',
    price: '\$52/day',
    status: 'Available',
    colors: [Color(0xFFEAE7F7), Color(0xFFD8D0F0)],
    iconColor: Color(0xFF594E86),
  ),
  Vehicle(
    name: 'Model Y Long Range',
    category: 'SUV',
    location: 'Houston',
    year: '2024',
    price: '\$74/day',
    status: 'In service',
    colors: [Color(0xFFFBE2E2), Color(0xFFF2C7C7)],
    iconColor: Color(0xFF873D43),
  ),
  Vehicle(
    name: 'Bronco Outer Banks',
    category: 'SUV',
    location: 'Austin',
    year: '2022',
    price: '\$81/day',
    status: 'Available',
    colors: [Color(0xFFE7F0DD), Color(0xFFD1E1BD)],
    iconColor: Color(0xFF48603A),
  ),
];
