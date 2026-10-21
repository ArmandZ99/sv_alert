import 'package:flutter/material.dart';

void main() {
  runApp(const SuceavaPulseApp());
}

class SuceavaPulseApp extends StatelessWidget {
  const SuceavaPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF246BFD);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Suceava Pulse',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FB),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE7EBF2)),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

enum TransportType { all, train, flight, coach }

enum ArrivalStatus { onTime, delayed, scheduled }

class TravelService {
  const TravelService({
    required this.id,
    required this.type,
    required this.serviceName,
    required this.route,
    required this.arrivalPoint,
    required this.minutesUntilArrival,
    required this.status,
    this.delayMinutes = 0,
    this.sourceLabel = 'Date demonstrative',
  });

  final String id;
  final TransportType type;
  final String serviceName;
  final String route;
  final String arrivalPoint;
  final int minutesUntilArrival;
  final ArrivalStatus status;
  final int delayMinutes;
  final String sourceLabel;

  DateTime get estimatedArrival =>
      DateTime.now().add(Duration(minutes: minutesUntilArrival));

  String get arrivalTime {
    final time = estimatedArrival;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

const List<TravelService> demoServices = [
  TravelService(
    id: 'train-demo-1',
    type: TransportType.train,
    serviceName: 'Tren demo IR 1831',
    route: 'Iași → Suceava → Timișoara Nord',
    arrivalPoint: 'Gara Suceava',
    minutesUntilArrival: 15,
    status: ArrivalStatus.onTime,
  ),
  TravelService(
    id: 'flight-demo-1',
    type: TransportType.flight,
    serviceName: 'Zbor demo W4 1234',
    route: 'Londra Luton (LTN) → Suceava (SCV)',
    arrivalPoint: 'Aeroportul Suceava',
    minutesUntilArrival: 24,
    status: ArrivalStatus.delayed,
    delayMinutes: 40,
  ),
  TravelService(
    id: 'coach-demo-1',
    type: TransportType.coach,
    serviceName: 'Autocar demo · Operator RVG',
    route: 'Botoșani → Suceava',
    arrivalPoint: 'Autogara — punct de confirmat',
    minutesUntilArrival: 36,
    status: ArrivalStatus.scheduled,
  ),
  TravelService(
    id: 'train-demo-2',
    type: TransportType.train,
    serviceName: 'Tren demo R 5602',
    route: 'Pașcani → Suceava',
    arrivalPoint: 'Gara Suceava',
    minutesUntilArrival: 49,
    status: ArrivalStatus.scheduled,
  ),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedTab = 0;
  TransportType _filter = TransportType.all;
  bool _arrivalAlerts = true;
  bool _delayAlerts = true;
  bool _trainAlerts = true;
  bool _flightAlerts = true;
  bool _coachAlerts = true;
  int _arrivalThreshold = 15;
  int _delayThreshold = 15;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(),
      _buildArrivalsPage(),
      _buildSettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedTab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Panou',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_transit_outlined),
            selectedIcon: Icon(Icons.directions_transit),
            label: 'Sosiri',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Setări',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final upcoming = demoServices
        .where((service) => service.minutesUntilArrival <= 60)
        .length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: _header()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          sliver: SliverToBoxAdapter(child: _demandRadar(upcoming)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sosiri în apropiere',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedTab = 1),
                  child: const Text('Vezi toate'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.separated(
            itemCount: demoServices.take(3).length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => ArrivalCard(
              service: demoServices[index],
              onTap: () => _showServiceDetails(demoServices[index]),
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(child: DemoDataNotice()),
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SUCEAVA PULSE',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
              SizedBox(height: 3),
              Text('Sosiri și oportunități locale', style: TextStyle(color: Color(0xFF697586), fontSize: 12)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => setState(() => _selectedTab = 2),
          tooltip: 'Setări notificări',
          icon: const Icon(Icons.notifications_active_outlined),
        ),
      ],
    );
  }

  Widget _demandRadar(int upcoming) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172B4D), Color(0xFF234E91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.radar, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('DEMAND RADAR', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD166).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text('DEMO', style: TextStyle(color: Color(0xFFFFD166), fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Posibilă activitate în creștere',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 8),
          Text(
            '$upcoming sosiri demonstrative în următoarea oră',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(child: _HubPill(icon: Icons.train, label: 'Gară')),
              SizedBox(width: 8),
              Expanded(child: _HubPill(icon: Icons.flight, label: 'Aeroport')),
              SizedBox(width: 8),
              Expanded(child: _HubPill(icon: Icons.directions_bus, label: 'Autogări')),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Sosirile pot indica cerere potențială, dar nu garantează comenzi Bolt.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalsPage() {
    final filtered = demoServices.where((service) {
      return _filter == TransportType.all || service.type == _filter;
    }).toList()
      ..sort((a, b) => a.minutesUntilArrival.compareTo(b.minutesUntilArrival));

    return CustomScrollView(
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
          sliver: SliverToBoxAdapter(
            child: Text('Sosiri estimate', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
          sliver: SliverToBoxAdapter(
            child: Text('Curse către punctele de transport din Suceava', style: TextStyle(color: Color(0xFF697586))),
          ),
        ),
        SliverToBoxAdapter(child: _filterChips()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          sliver: filtered.isEmpty
              ? const SliverToBoxAdapter(child: Text('Nu există curse pentru filtrul selectat.'))
              : SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => ArrivalCard(
                    service: filtered[index],
                    onTap: () => _showServiceDetails(filtered[index]),
                  ),
                ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(child: DemoDataNotice()),
        ),
      ],
    );
  }

  Widget _filterChips() {
    const options = [
      (TransportType.all, 'Toate', Icons.view_agenda_outlined),
      (TransportType.train, 'Trenuri', Icons.train_outlined),
      (TransportType.flight, 'Avioane', Icons.flight_outlined),
      (TransportType.coach, 'Autocare', Icons.directions_bus_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: options.map((option) {
          final selected = _filter == option.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              avatar: Icon(option.$3, size: 17),
              label: Text(option.$2),
              onSelected: (_) => setState(() => _filter = option.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text('Setări', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Alege ce notificări vrei să primești.', style: TextStyle(color: Color(0xFF697586))),
        const SizedBox(height: 22),
        _settingsSectionTitle('Notificări'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: _arrivalAlerts,
                onChanged: (value) => setState(() => _arrivalAlerts = value),
                title: const Text('Alerte înainte de sosire', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Pentru cursele urmărite'),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                value: _delayAlerts,
                onChanged: (value) => setState(() => _delayAlerts = value),
                title: const Text('Alerte de întârziere', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Când întârzierea depășește pragul ales'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _settingsSectionTitle('Praguri'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alertă înainte de sosire: $_arrivalThreshold minute', style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(
                  value: _arrivalThreshold.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  label: '$_arrivalThreshold min',
                  onChanged: (value) => setState(() => _arrivalThreshold = value.round()),
                ),
                const SizedBox(height: 8),
                Text('Întârziere minimă: $_delayThreshold minute', style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(
                  value: _delayThreshold.toDouble(),
                  min: 5,
                  max: 90,
                  divisions: 17,
                  label: '$_delayThreshold min',
                  onChanged: (value) => setState(() => _delayThreshold = value.round()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _settingsSectionTitle('Tipuri de transport'),
        Card(
          child: Column(
            children: [
              SwitchListTile(value: _trainAlerts, onChanged: (value) => setState(() => _trainAlerts = value), title: const Text('Trenuri')),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(value: _flightAlerts, onChanged: (value) => setState(() => _flightAlerts = value), title: const Text('Avioane')),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(value: _coachAlerts, onChanged: (value) => setState(() => _coachAlerts = value), title: const Text('Autocare și autobuze')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const DemoDataNotice(),
      ],
    );
  }

  Widget _settingsSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1.0, fontWeight: FontWeight.w900, color: Color(0xFF697586))),
      );

  void _showServiceDetails(TravelService service) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(service.serviceName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(service.route, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              _DetailRow(label: 'Punct de sosire', value: service.arrivalPoint),
              _DetailRow(label: 'Sosire estimată (demo)', value: service.arrivalTime),
              _DetailRow(label: 'Timp rămas (demo)', value: '${service.minutesUntilArrival} minute'),
              if (service.status == ArrivalStatus.delayed)
                _DetailRow(label: 'Întârziere (demo)', value: '+${service.delayMinutes} minute'),
              const SizedBox(height: 12),
              const DemoDataNotice(),
            ],
          ),
        ),
      ),
    );
  }
}

class ArrivalCard extends StatelessWidget {
  const ArrivalCard({required this.service, required this.onTap, super.key});

  final TravelService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, label, iconColor) = switch (service.type) {
      TransportType.train => (Icons.train_rounded, 'TREN', const Color(0xFF246BFD)),
      TransportType.flight => (Icons.flight_rounded, 'AVION', const Color(0xFF8156D9)),
      TransportType.coach => (Icons.directions_bus_rounded, 'AUTOCAR', const Color(0xFF008A72)),
      TransportType.all => (Icons.directions_transit_rounded, 'TRANSPORT', colorScheme.primary),
    };
    final (statusLabel, statusColor) = switch (service.status) {
      ArrivalStatus.onTime => ('La timp · demo', const Color(0xFF16835D)),
      ArrivalStatus.delayed => ('Întârziat +${service.delayMinutes} min · demo', const Color(0xFFC65D16)),
      ArrivalStatus.scheduled => ('Programat · demo', const Color(0xFF64748B)),
    };

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: iconColor, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(color: iconColor, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.1)),
                        const SizedBox(height: 3),
                        Text(service.serviceName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(service.route, style: const TextStyle(color: Color(0xFF697586), fontSize: 12, height: 1.3)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
                ],
              ),
              const SizedBox(height: 15),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF697586)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(service.arrivalPoint, style: const TextStyle(color: Color(0xFF475467), fontSize: 12))),
                  Text(service.arrivalTime, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: statusColor),
                  const SizedBox(width: 5),
                  Expanded(child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800))),
                  Text('În ${service.minutesUntilArrival} min', style: const TextStyle(color: Color(0xFF475467), fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DemoDataNotice extends StatelessWidget {
  const DemoDataNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3D98B)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF8A5A00)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Date demonstrative. Orele, cursele și întârzierile nu sunt informații în timp real. Cererea Bolt nu este măsurată de această aplicație.',
              style: TextStyle(color: Color(0xFF765000), fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubPill extends StatelessWidget {
  const _HubPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF697586), fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}
