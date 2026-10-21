import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/domain/notification_preferences.dart';
import 'package:travelalerts/domain/transport_type.dart';
import 'package:travelalerts/presentation/state/preferences_controller.dart';

void main() {
  test('defaults match the specification', () {
    const prefs = NotificationPreferences();
    expect(prefs.enabled, isTrue);
    expect(prefs.reminderMinutes, [30, 15, 5]);
    expect(prefs.delayThresholdMinutes, 15);
    expect(prefs.followedTypes, TransportType.values.toSet());
    expect(prefs.quietHours.enabled, isFalse);
  });

  group('QuietHours.contains', () {
    DateTime at(int h, int m) => DateTime(2026, 10, 21, h, m);

    test('disabled never matches', () {
      expect(const QuietHours().contains(at(23, 0)), isFalse);
    });

    test('overnight interval wraps past midnight', () {
      const quiet = QuietHours(
        enabled: true,
        startMinutes: 22 * 60,
        endMinutes: 7 * 60,
      );
      expect(quiet.contains(at(23, 30)), isTrue);
      expect(quiet.contains(at(3, 0)), isTrue);
      expect(quiet.contains(at(7, 0)), isFalse);
      expect(quiet.contains(at(12, 0)), isFalse);
    });

    test('same-day interval', () {
      const quiet = QuietHours(
        enabled: true,
        startMinutes: 13 * 60,
        endMinutes: 15 * 60,
      );
      expect(quiet.contains(at(14, 0)), isTrue);
      expect(quiet.contains(at(15, 0)), isFalse);
    });
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
