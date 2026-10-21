import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/core/time/bucharest_time.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';

/// An instant given as Bucharest wall-clock time on 2026-10-21 (summer time).
DateTime at(int hour, int minute, [int day = 21]) =>
    BucharestTime.fromWallClock(2026, 10, day, hour, minute);

void main() {
  const overnight = QuietHours(
    enabled: true,
    startMinutes: 22 * 60,
    endMinutes: 7 * 60,
  );
  const daytime = QuietHours(
    enabled: true,
    startMinutes: 13 * 60,
    endMinutes: 15 * 60,
  );

  test('disabled quiet hours never match, whatever the times', () {
    const off = QuietHours(startMinutes: 0, endMinutes: 23 * 60);
    expect(off.contains(at(12, 0)), isFalse);
    expect(off.contains(at(3, 0)), isFalse);
  });

  group('same-day period 13:00-15:00', () {
    test('start is inclusive, end is exclusive', () {
      expect(daytime.contains(at(12, 59)), isFalse);
      expect(daytime.contains(at(13, 0)), isTrue);
      expect(daytime.contains(at(14, 59)), isTrue);
      expect(daytime.contains(at(15, 0)), isFalse);
    });
  });

  group('overnight period 22:00-07:00', () {
    test('covers both sides of midnight', () {
      expect(overnight.contains(at(21, 59)), isFalse);
      expect(overnight.contains(at(22, 0)), isTrue);
      expect(overnight.contains(at(23, 59)), isTrue);
      expect(overnight.contains(at(0, 0, 22)), isTrue);
      expect(overnight.contains(at(3, 0, 22)), isTrue);
      expect(overnight.contains(at(6, 59, 22)), isTrue);
    });

    test('ends exactly at 07:00 and stays off during the day', () {
      expect(overnight.contains(at(7, 0, 22)), isFalse);
      expect(overnight.contains(at(12, 0)), isFalse);
      expect(overnight.contains(at(21, 59)), isFalse);
    });
  });

  group('start equals end', () {
    test('is an empty period: never quiet', () {
      const equal = QuietHours(
        enabled: true,
        startMinutes: 8 * 60,
        endMinutes: 8 * 60,
      );
      for (final h in [0, 7, 8, 9, 12, 23]) {
        expect(equal.contains(at(h, 0)), isFalse, reason: '$h:00');
      }
    });
  });

  group('judged in Bucharest time, not UTC or the device zone', () {
    test(
      'the same UTC hour is quiet or not depending on summer/winter time',
      () {
        // 19:30 UTC is 21:30 in winter (not quiet) but 22:30 in summer (quiet).
        expect(overnight.contains(DateTime.utc(2026, 1, 15, 19, 30)), isFalse);
        expect(overnight.contains(DateTime.utc(2026, 7, 15, 19, 30)), isTrue);
      },
    );

    test('a local DateTime and its UTC twin agree', () {
      final utc = DateTime.utc(2026, 7, 15, 19, 30);
      expect(overnight.contains(utc.toLocal()), overnight.contains(utc));
    });

    test('spring-forward night: 22:00-07:00 still ends at wall-clock 07:00', () {
      // 2026-03-29: 07:00 EEST is 04:00 UTC.
      expect(
        overnight.contains(DateTime.utc(2026, 3, 29, 3, 59)),
        isTrue,
      ); // 06:59
      expect(
        overnight.contains(DateTime.utc(2026, 3, 29, 4, 0)),
        isFalse,
      ); // 07:00
      // The skipped hour itself (01:00 UTC = 04:00 local) is inside the period.
      expect(overnight.contains(DateTime.utc(2026, 3, 29, 1, 0)), isTrue);
    });

    test('fall-back night: both 03:30s are quiet; 07:00 ends it', () {
      expect(
        overnight.contains(DateTime.utc(2026, 10, 25, 0, 30)),
        isTrue,
      ); // 03:30 EEST
      expect(
        overnight.contains(DateTime.utc(2026, 10, 25, 1, 30)),
        isTrue,
      ); // 03:30 EET
      expect(
        overnight.contains(DateTime.utc(2026, 10, 25, 4, 59)),
        isTrue,
      ); // 06:59 EET
      expect(
        overnight.contains(DateTime.utc(2026, 10, 25, 5, 0)),
        isFalse,
      ); // 07:00 EET
    });
  });
}
