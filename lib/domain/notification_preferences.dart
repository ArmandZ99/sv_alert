import 'transport_type.dart';

/// Hours in which notifications should be silenced. May span midnight.
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.startMinutes = 22 * 60,
    this.endMinutes = 7 * 60,
  });

  final bool enabled;

  /// Minutes since midnight.
  final int startMinutes;
  final int endMinutes;

  bool contains(DateTime time) {
    if (!enabled || startMinutes == endMinutes) return false;
    final minute = time.hour * 60 + time.minute;
    if (startMinutes < endMinutes) {
      return minute >= startMinutes && minute < endMinutes;
    }
    return minute >= startMinutes || minute < endMinutes;
  }

  QuietHours copyWith({bool? enabled, int? startMinutes, int? endMinutes}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );
}

/// User notification settings. Defaults live here and nowhere else.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.followedTypes = const {
      TransportType.flight,
      TransportType.train,
      TransportType.coach,
    },
    this.reminderMinutes = defaultReminderMinutes,
    this.delayThresholdMinutes = defaultDelayThresholdMinutes,
    this.quietHours = const QuietHours(),
    this.followedServiceIds = const {},
  });

  static const List<int> defaultReminderMinutes = [30, 15, 5];
  static const int defaultDelayThresholdMinutes = 15;

  /// Reminder thresholds offered in the UI.
  static const List<int> reminderOptions = [60, 30, 15, 10, 5];
  static const int minDelayThreshold = 5;
  static const int maxDelayThreshold = 90;

  final bool enabled;
  final Set<TransportType> followedTypes;

  /// Minutes before arrival at which to remind, sorted descending.
  final List<int> reminderMinutes;
  final int delayThresholdMinutes;
  final QuietHours quietHours;

  /// Specific services the user chose to follow (empty = follow by type).
  final Set<String> followedServiceIds;

  bool isFollowingService(String id) => followedServiceIds.contains(id);

  NotificationPreferences copyWith({
    bool? enabled,
    Set<TransportType>? followedTypes,
    List<int>? reminderMinutes,
    int? delayThresholdMinutes,
    QuietHours? quietHours,
    Set<String>? followedServiceIds,
  }) => NotificationPreferences(
    enabled: enabled ?? this.enabled,
    followedTypes: followedTypes ?? this.followedTypes,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    delayThresholdMinutes: delayThresholdMinutes ?? this.delayThresholdMinutes,
    quietHours: quietHours ?? this.quietHours,
    followedServiceIds: followedServiceIds ?? this.followedServiceIds,
  );
}
