import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/arrivals_controller.dart';
import '../state/preferences_controller.dart';
import 'arrivals_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.arrivals,
    required this.preferences,
    super.key,
  });

  final ArrivalsController arrivals;
  final PreferencesController preferences;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keeps "Updated N min ago" and "in N min" current between refreshes.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        arrivals: widget.arrivals,
        preferences: widget.preferences,
        onOpenArrivals: () => setState(() => _tab = 1),
        onOpenSettings: () => setState(() => _tab = 2),
      ),
      ArrivalsPage(arrivals: widget.arrivals, preferences: widget.preferences),
      SettingsPage(preferences: widget.preferences),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: Strings.navDashboard,
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_transit_outlined),
            selectedIcon: Icon(Icons.directions_transit),
            label: Strings.navArrivals,
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: Strings.navSettings,
          ),
        ],
      ),
    );
  }
}
