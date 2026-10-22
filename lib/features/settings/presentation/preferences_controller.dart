import 'package:flutter/foundation.dart';

import '../data/preferences_store.dart';
import '../domain/notification_preferences.dart';
import '../../transport/domain/transport_type.dart';

/// Notification preferences, saved through an optional [PreferencesStore].
/// Not connected to any notification delivery: changing them has no effect
/// outside the app yet.
class PreferencesController extends ChangeNotifier {
  PreferencesController({
    NotificationPreferences initial = const NotificationPreferences(),
    this.store,
  }) : _value = initial;

  final PreferencesStore? store;
  NotificationPreferences _value;

  NotificationPreferences get value => _value;

  void _set(NotificationPreferences next) {
    _value = next;
    notifyListeners();
    _persist(next);
  }

  Future<void> _persist(NotificationPreferences preferences) async {
    try {
      await store?.save(preferences);
    } catch (_) {
      // Settings stay usable in memory if storage fails.
    }
  }

  void setEnabled(bool enabled) => _set(_value.copyWith(enabled: enabled));

  void setArrivalAlertsEnabled(bool enabled) =>
      _set(_value.copyWith(arrivalAlertsEnabled: enabled));

  void setDelayAlertsEnabled(bool enabled) =>
      _set(_value.copyWith(delayAlertsEnabled: enabled));

  void setTypeFollowed(TransportType type, bool followed) {
    final types = {..._value.followedTypes};
    followed ? types.add(type) : types.remove(type);
    _set(_value.copyWith(followedTypes: types));
  }

  void toggleReminder(int minutes) {
    final set = {..._value.reminderMinutes};
    if (!set.remove(minutes)) set.add(minutes);
    final sorted = set.toList()..sort((a, b) => b.compareTo(a));
    _set(_value.copyWith(reminderMinutes: sorted));
  }

  void setDelayThreshold(int minutes) => _set(
    _value.copyWith(
      delayThresholdMinutes: minutes.clamp(
        NotificationPreferences.minDelayThreshold,
        NotificationPreferences.maxDelayThreshold,
      ),
    ),
  );

  void setQuietHours(QuietHours quietHours) =>
      _set(_value.copyWith(quietHours: quietHours));

  void toggleFollowedService(String id) {
    final ids = {..._value.followedServiceIds};
    if (!ids.remove(id)) ids.add(id);
    _set(_value.copyWith(followedServiceIds: ids));
  }
}
