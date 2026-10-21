import 'package:flutter/material.dart';

import 'core/clock.dart';
import 'data/mock_transport_repository.dart';
import 'data/transport_repository.dart';
import 'presentation/l10n/strings.dart';
import 'presentation/pages/app_shell.dart';
import 'presentation/state/arrivals_controller.dart';
import 'presentation/state/preferences_controller.dart';
import 'presentation/theme/app_theme.dart';

class SuceavaPulseApp extends StatefulWidget {
  /// Defaults to the mock repository. Pass a different [repository] (and
  /// [clock]) to run against another source or in tests.
  const SuceavaPulseApp({this.repository, this.clock = systemClock, super.key});

  final TransportRepository? repository;
  final Clock clock;

  @override
  State<SuceavaPulseApp> createState() => _SuceavaPulseAppState();
}

class _SuceavaPulseAppState extends State<SuceavaPulseApp> {
  late final ArrivalsController _arrivals = ArrivalsController(
    repository:
        widget.repository ?? MockTransportRepository(clock: widget.clock),
    clock: widget.clock,
  );
  final PreferencesController _preferences = PreferencesController();

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
