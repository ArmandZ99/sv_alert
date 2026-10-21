import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/alert_history_store.dart';

/// Keeps the handled-alert history as one JSON object (`key -> ISO-8601 UTC`)
/// in `shared_preferences`.
class SharedPreferencesAlertHistoryStore implements AlertHistoryStore {
  SharedPreferencesAlertHistoryStore(this._prefs);

  static const String storageKey = 'handled_alerts_v1';

  final SharedPreferences _prefs;

  static Future<SharedPreferencesAlertHistoryStore> create() async =>
      SharedPreferencesAlertHistoryStore(await SharedPreferences.getInstance());

  @override
  Future<Map<String, DateTime>> load() async {
    try {
      final raw = _prefs.getString(storageKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, DateTime>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! String) return;
        final parsed = DateTime.tryParse(value);
        if (parsed != null) result[key] = parsed.toUtc();
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, DateTime> handled) async {
    final encoded = {
      for (final entry in handled.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    };
    await _prefs.setString(storageKey, jsonEncode(encoded));
  }
}
