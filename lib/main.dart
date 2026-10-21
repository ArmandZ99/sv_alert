import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/settings/data/preferences_store.dart';
import 'features/settings/domain/notification_preferences.dart';

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

  runApp(SuceavaPulseApp(preferencesStore: store, initialPreferences: initial));
}
