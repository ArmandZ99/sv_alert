import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';
import 'package:travelalerts/features/settings/presentation/preferences_controller.dart';

void main() {
  test('defaults match the specification', () {
    const prefs = NotificationPreferences();
    expect(prefs.enabled, isTrue);
    expect(prefs.arrivalAlertsEnabled, isTrue);
    expect(prefs.delayAlertsEnabled, isTrue);
    expect(prefs.reminderMinutes, [30, 15, 5]);
    expect(prefs.delayThresholdMinutes, 15);
    expect(prefs.followedTypes, TransportType.values.toSet());
    expect(prefs.quietHours.enabled, isFalse);
  });

  group('PreferencesController', () {
    test('toggling reminders keeps them sorted descending', () {
      final controller = PreferencesController();
      controller.toggleReminder(10);
      expect(controller.value.reminderMinutes, [30, 15, 10, 5]);
      controller.toggleReminder(30);
      expect(controller.value.reminderMinutes, [15, 10, 5]);
    });

    test('delay threshold is clamped to the allowed range', () {
      final controller = PreferencesController();
      controller.setDelayThreshold(1);
      expect(
        controller.value.delayThresholdMinutes,
        NotificationPreferences.minDelayThreshold,
      );
      controller.setDelayThreshold(500);
      expect(
        controller.value.delayThresholdMinutes,
        NotificationPreferences.maxDelayThreshold,
      );
    });

    test('type and service following toggles', () {
      final controller = PreferencesController();
      controller.setTypeFollowed(TransportType.coach, false);
      expect(
        controller.value.followedTypes.contains(TransportType.coach),
        isFalse,
      );
      controller.toggleFollowedService('abc');
      expect(controller.value.isFollowingService('abc'), isTrue);
      controller.toggleFollowedService('abc');
      expect(controller.value.isFollowingService('abc'), isFalse);
    });
  });
}
