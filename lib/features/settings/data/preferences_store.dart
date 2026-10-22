import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notification_preferences.dart';

/// Local persistence for notification preferences.
abstract interface class PreferencesStore {
  /// Never throws: missing or corrupt data yields defaults.
  Future<NotificationPreferences> load();

  Future<void> save(NotificationPreferences preferences);
}

/// Stores all preferences as one JSON string in `shared_preferences`.
class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this._prefs);

  static const String storageKey = 'notification_preferences_v1';

  final SharedPreferences _prefs;

  static Future<SharedPreferencesStore> create() async =>
      SharedPreferencesStore(await SharedPreferences.getInstance());

  @override
  Future<NotificationPreferences> load() async {
    try {
      final raw = _prefs.getString(storageKey);
      if (raw == null) return const NotificationPreferences();
      return NotificationPreferences.fromMap(jsonDecode(raw));
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  @override
  Future<void> save(NotificationPreferences preferences) async {
    await _prefs.setString(storageKey, jsonEncode(preferences.toMap()));
  }
}
