enum ArrivalStatus {
  /// Only a timetable time is known: no live estimate either way.
  scheduled,
  onTime,
  delayed,
  arrivingSoon,
  arrived,
  cancelled,
  unknown,
}

/// How trustworthy the times of a service are.
enum DataQuality { scheduled, estimated, live, unknown }

/// Display-level thresholds. These are not the user's notification thresholds
/// (see `NotificationPreferences`).
abstract final class StatusRules {
  /// A delay of at least this many minutes is shown as "delayed".
  static const int delayedFromMinutes = 5;

  /// An estimated arrival within this many minutes is shown as "arriving soon".
  static const int arrivingSoonWithinMinutes = 15;
}
