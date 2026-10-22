// Same logic as the app's lib/core/time/bucharest_time.dart, kept in step by
// hand: the app package needs Flutter, this one is plain Dart.

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// All business-rule time handling for Suceava goes through here, so rules
/// never depend on the phone's configured time zone.
///
/// Conventions:
/// * Every timestamp in the domain is an absolute instant. Prefer UTC values;
///   a local `DateTime` is accepted and means the same instant.
/// * Durations ("minutes until arrival") are differences of instants. Never do
///   wall-clock arithmetic across a daylight-saving change.
/// * Wall-clock questions (quiet hours, "what service date is it", display)
///   are answered in `Europe/Bucharest` via [of], [minuteOfDay] and
///   [serviceDateOf].
/// * Wall-clock times from a source ("18:40" in Romania) become instants with
///   [fromWallClock].
/// * A "service date" is a calendar date stored as a UTC-midnight `DateTime`;
///   only its year, month and day are meaningful.
abstract final class BucharestTime {
  static const String zoneName = 'Europe/Bucharest';

  static bool _initialized = false;
  static late final tz.Location _location;

  static tz.Location get location {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _location = tz.getLocation(zoneName);
      _initialized = true;
    }
    return _location;
  }

  /// The instant expressed in Bucharest wall-clock time.
  static tz.TZDateTime of(DateTime instant) =>
      tz.TZDateTime.from(instant, location);

  /// Minutes since local midnight in Bucharest (0..1439).
  static int minuteOfDay(DateTime instant) {
    final local = of(instant);
    return local.hour * 60 + local.minute;
  }

  /// Bucharest calendar date of the instant, as a UTC-midnight `DateTime`.
  static DateTime serviceDateOf(DateTime instant) {
    final local = of(instant);
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// Offset of Bucharest from UTC at the given instant (+2h winter, +3h summer).
  static Duration offsetAt(DateTime instant) => of(instant).timeZoneOffset;

  /// Converts a Bucharest wall-clock time to an absolute UTC instant.
  ///
  /// Daylight-saving edge cases are resolved deterministically:
  /// * Time that occurs twice (autumn, 03:00-03:59 on the last Sunday of
  ///   October): the first occurrence (summer time) is used.
  /// * Time that does not exist (spring, 03:00-03:59 on the last Sunday of
  ///   March): it is read with the pre-change offset, so it lands one hour
  ///   later on the wall clock (03:30 becomes 04:30).
  static DateTime fromWallClock(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
  ]) {
    final naive = DateTime.utc(year, month, day, hour, minute);
    const day1 = Duration(days: 1);
    final before = offsetAt(naive.subtract(day1));
    final after = offsetAt(naive.add(day1));

    final candidates = <DateTime>[];
    for (final offset in {before, after}) {
      final instant = naive.subtract(offset);
      if (offsetAt(instant) == offset) candidates.add(instant);
    }
    if (candidates.isEmpty) return naive.subtract(before); // spring-forward gap
    candidates.sort();
    return candidates.first; // earliest if ambiguous
  }
}
