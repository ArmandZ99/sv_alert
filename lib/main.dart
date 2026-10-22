import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/settings/data/preferences_store.dart';
import 'features/settings/domain/notification_preferences.dart';
import 'features/transport/data/sources/provider_config.dart';
import 'features/transport/data/transport_repository_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved settings before the first frame. If storage is unavailable the
  // app still starts, with defaults and in-memory settings.
  PreferencesStore? store;
  var initial = const NotificationPreferences();
  try {
    store = await SharedPreferencesStore.create();
    initial = await store.load();
  } catch (_) {
    store = null;
  }

  // Real data comes from the ingestion backend, whose URL is given at build
  // time (--dart-define=TRAVEL_ALERTS_API_BASE_URL=https://...). Without a
  // valid URL the app runs on explicit demo data.
  final validation = ProviderConfig.fromEnvironment();
  if (!validation.isValid) {
    for (final error in validation.errors) {
      debugPrint('Backend configuration ignored: $error');
    }
  }

  runApp(
    SuceavaPulseApp(
      repository: createTransportRepository(validation.config),
      preferencesStore: store,
      initialPreferences: initial,
    ),
  );
}
