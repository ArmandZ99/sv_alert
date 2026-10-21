import '../../../core/time/bucharest_time.dart';
import '../../transport/domain/transport_type.dart';

/// Hours in which notifications should be silenced, in Europe/Bucharest wall
/// clock time. May span midnight (for example 22:00-07:00).
///
/// * The start is inclusive and the end is exclusive.
/// * If start is after end the period crosses midnight.
/// * If start equals end the period is empty: nothing is ever quiet. (It is
///   not read as "all day"; to silence everything, turn notifications off.)
/// * Disabled quiet hours never match.
///
/// Membership is decided on the Bucharest wall clock, so on daylight-saving
/// change days the period still runs from the clock's start to its end, which
/// makes it one hour shorter or longer in real time.
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

  /// Whether the absolute [instant] falls inside the quiet period.
  bool contains(DateTime instant) {
    if (!enabled || startMinutes == endMinutes) return false;
    final minute = BucharestTime.minuteOfDay(instant);
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
    this.arrivalAlertsEnabled = true,
    this.delayAlertsEnabled = true,
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

  /// Global switch for all alerts.
  final bool enabled;
  final bool arrivalAlertsEnabled;
  final bool delayAlertsEnabled;
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
    bool? arrivalAlertsEnabled,
    bool? delayAlertsEnabled,
    Set<TransportType>? followedTypes,
    List<int>? reminderMinutes,
    int? delayThresholdMinutes,
    QuietHours? quietHours,
    Set<String>? followedServiceIds,
  }) => NotificationPreferences(
    enabled: enabled ?? this.enabled,
    arrivalAlertsEnabled: arrivalAlertsEnabled ?? this.arrivalAlertsEnabled,
    delayAlertsEnabled: delayAlertsEnabled ?? this.delayAlertsEnabled,
    followedTypes: followedTypes ?? this.followedTypes,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    delayThresholdMinutes: delayThresholdMinutes ?? this.delayThresholdMinutes,
    quietHours: quietHours ?? this.quietHours,
    followedServiceIds: followedServiceIds ?? this.followedServiceIds,
  );

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'arrivalAlertsEnabled': arrivalAlertsEnabled,
    'delayAlertsEnabled': delayAlertsEnabled,
    'followedTypes': [for (final t in followedTypes) t.name],
    'reminderMinutes': reminderMinutes,
    'delayThresholdMinutes': delayThresholdMinutes,
    'quietHours': {
      'enabled': quietHours.enabled,
      'startMinutes': quietHours.startMinutes,
      'endMinutes': quietHours.endMinutes,
    },
    'followedServiceIds': followedServiceIds.toList()..sort(),
  };

  /// Rebuilds preferences from stored data. Every field is validated on its
  /// own: anything missing, of the wrong type or out of range falls back to
  /// its default instead of failing.
  factory NotificationPreferences.fromMap(Object? raw) {
    const defaults = NotificationPreferences();
    if (raw is! Map) return defaults;

    bool readBool(String key, bool fallback) {
      final value = raw[key];
      return value is bool ? value : fallback;
    }

    Set<TransportType> readTypes() {
      final value = raw['followedTypes'];
      if (value is! List) return defaults.followedTypes;
      final byName = TransportType.values.asNameMap();
      return {
        for (final name in value)
          if (name is String && byName[name] != null) byName[name]!,
      };
    }

    List<int> readReminders() {
      final value = raw['reminderMinutes'];
      if (value is! List) return defaults.reminderMinutes;
      final minutes = {
        for (final m in value)
          if (m is int && m >= 1 && m <= 360) m,
      };
      return minutes.toList()..sort((a, b) => b.compareTo(a));
    }

    int readDelay() {
      final value = raw['delayThresholdMinutes'];
      if (value is int &&
          value >= minDelayThreshold &&
          value <= maxDelayThreshold) {
        return value;
      }
      return defaults.delayThresholdMinutes;
    }

    QuietHours readQuiet() {
      final value = raw['quietHours'];
      if (value is! Map) return defaults.quietHours;
      int minuteOf(String key, int fallback) {
        final m = value[key];
        return m is int && m >= 0 && m < 24 * 60 ? m : fallback;
      }

      final quiet = defaults.quietHours;
      return QuietHours(
        enabled: value['enabled'] is bool
            ? value['enabled'] as bool
            : quiet.enabled,
        startMinutes: minuteOf('startMinutes', quiet.startMinutes),
        endMinutes: minuteOf('endMinutes', quiet.endMinutes),
      );
    }

    Set<String> readServices() {
      final value = raw['followedServiceIds'];
      if (value is! List) return defaults.followedServiceIds;
      return {
        for (final id in value)
          if (id is String) id,
      };
    }

    return NotificationPreferences(
      enabled: readBool('enabled', defaults.enabled),
      arrivalAlertsEnabled: readBool(
        'arrivalAlertsEnabled',
        defaults.arrivalAlertsEnabled,
      ),
      delayAlertsEnabled: readBool(
        'delayAlertsEnabled',
        defaults.delayAlertsEnabled,
      ),
      followedTypes: readTypes(),
      reminderMinutes: readReminders(),
      delayThresholdMinutes: readDelay(),
      quietHours: readQuiet(),
      followedServiceIds: readServices(),
    );
  }
}
