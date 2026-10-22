import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../features/transport/data/mock_transport_repository.dart';
import '../features/settings/data/preferences_store.dart';
import '../features/transport/data/transport_repository.dart';
import '../features/settings/domain/notification_preferences.dart';
import '../core/l10n/strings.dart';
import 'app_shell.dart';
import '../features/arrivals/presentation/arrivals_controller.dart';
import '../features/settings/presentation/preferences_controller.dart';
import '../core/theme/app_theme.dart';

class SuceavaPulseApp extends StatefulWidget {
  /// Defaults to the mock repository and in-memory preferences. Pass a
  /// different [repository], [clock] or [preferencesStore] to change the data
  /// source, or in tests.
  const SuceavaPulseApp({
    this.repository,
    this.clock = systemClock,
    this.preferencesStore,
    this.initialPreferences = const NotificationPreferences(),
    super.key,
  });

  final TransportRepository? repository;
  final Clock clock;
  final PreferencesStore? preferencesStore;

  /// Preferences already loaded from [preferencesStore] at startup.
  final NotificationPreferences initialPreferences;

  @override
  State<SuceavaPulseApp> createState() => _SuceavaPulseAppState();
}

class _SuceavaPulseAppState extends State<SuceavaPulseApp> {
  late final ArrivalsController _arrivals = ArrivalsController(
    repository:
        widget.repository ?? MockTransportRepository(clock: widget.clock),
    clock: widget.clock,
  );
  late final PreferencesController _preferences = PreferencesController(
    initial: widget.initialPreferences,
    store: widget.preferencesStore,
  );

  @override
  void initState() {
    super.initState();
    _arrivals.refresh();
  }

  @override
  void dispose() {
    _arrivals.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: Strings.appName,
      theme: buildAppTheme(),
      home: AppShell(arrivals: _arrivals, preferences: _preferences),
    );
  }
}
