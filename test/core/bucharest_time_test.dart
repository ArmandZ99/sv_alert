import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/core/time/bucharest_time.dart';

// 2026 daylight-saving changes in Romania (EU rules, both at 01:00 UTC):
//   spring: Sunday 29 March, 03:00 EET (+2) -> 04:00 EEST (+3)
//   autumn: Sunday 25 October, 04:00 EEST (+3) -> 03:00 EET (+2)
void main() {
  String wall(DateTime instant) {
    final t = BucharestTime.of(instant);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  group('UTC to Bucharest', () {
    test('winter is UTC+2, summer is UTC+3', () {
      expect(wall(DateTime.utc(2026, 1, 15, 10)), '2026-01-15 12:00');
      expect(wall(DateTime.utc(2026, 7, 15, 10)), '2026-07-15 13:00');
      expect(
        BucharestTime.offsetAt(DateTime.utc(2026, 1, 15)),
        const Duration(hours: 2),
      );
      expect(
        BucharestTime.offsetAt(DateTime.utc(2026, 7, 15)),
        const Duration(hours: 3),
      );
    });

    test('spring forward: 02:59 jumps to 04:00', () {
      expect(wall(DateTime.utc(2026, 3, 29, 0, 59)), '2026-03-29 02:59');
      expect(wall(DateTime.utc(2026, 3, 29, 1, 0)), '2026-03-29 04:00');
    });

    test('fall back: the 03:xx hour happens twice', () {
      expect(wall(DateTime.utc(2026, 10, 24, 23, 59)), '2026-10-25 02:59');
      expect(
        wall(DateTime.utc(2026, 10, 25, 0, 30)),
        '2026-10-25 03:30',
      ); // summer time
      expect(wall(DateTime.utc(2026, 10, 25, 0, 59)), '2026-10-25 03:59');
      expect(
        wall(DateTime.utc(2026, 10, 25, 1, 0)),
        '2026-10-25 03:00',
      ); // winter time
      expect(
        wall(DateTime.utc(2026, 10, 25, 1, 30)),
        '2026-10-25 03:30',
      ); // again
    });

    test('a local DateTime means the same instant as its UTC twin', () {
      final utc = DateTime.utc(2026, 7, 15, 10, 30);
      expect(wall(utc.toLocal()), wall(utc));
      expect(
        BucharestTime.minuteOfDay(utc.toLocal()),
        BucharestTime.minuteOfDay(utc),
      );
    });

    test('minuteOfDay and serviceDateOf use the Bucharest day', () {
      expect(
        BucharestTime.minuteOfDay(DateTime.utc(2026, 1, 15, 10, 5)),
        12 * 60 + 5,
      );
      // 21:30 UTC is already after midnight in Bucharest.
      final late = DateTime.utc(2026, 10, 21, 21, 30);
      expect(BucharestTime.serviceDateOf(late), DateTime.utc(2026, 10, 22));
      expect(BucharestTime.minuteOfDay(late), 30);
    });
  });

  group('Bucharest wall clock to instant', () {
    test('ordinary winter and summer times', () {
      expect(
        BucharestTime.fromWallClock(2026, 1, 15, 12, 0),
        DateTime.utc(2026, 1, 15, 10),
      );
      expect(
        BucharestTime.fromWallClock(2026, 7, 15, 12, 0),
        DateTime.utc(2026, 7, 15, 9),
      );
    });

    test('times around the change round-trip when they exist once', () {
      for (final (y, mo, d, h, mi) in [
        (2026, 3, 29, 2, 59),
        (2026, 3, 29, 4, 0),
        (2026, 10, 25, 2, 59),
        (2026, 10, 25, 4, 0),
        (2026, 12, 31, 23, 59),
      ]) {
        final instant = BucharestTime.fromWallClock(y, mo, d, h, mi);
        final back = BucharestTime.of(instant);
        expect(
          [back.year, back.month, back.day, back.hour, back.minute],
          [y, mo, d, h, mi],
        );
      }
    });

    test('a time that does not exist (spring gap) moves one hour later', () {
      final instant = BucharestTime.fromWallClock(2026, 3, 29, 3, 30);
      expect(instant, DateTime.utc(2026, 3, 29, 1, 30));
      expect(wall(instant), '2026-03-29 04:30');
    });

    test(
      'a time that occurs twice (autumn) resolves to the first, summer-time occurrence',
      () {
        final instant = BucharestTime.fromWallClock(2026, 10, 25, 3, 30);
        expect(instant, DateTime.utc(2026, 10, 25, 0, 30));
      },
    );

    test('days are 23 and 25 hours long on change days', () {
      Duration day(int y, int m, int d) => BucharestTime.fromWallClock(
        y,
        m,
        d + 1,
      ).difference(BucharestTime.fromWallClock(y, m, d));
      expect(day(2026, 3, 29), const Duration(hours: 23));
      expect(day(2026, 10, 25), const Duration(hours: 25));
      expect(day(2026, 6, 10), const Duration(hours: 24));
    });

    test('2027 changes follow the last-Sunday rule too', () {
      expect(wall(DateTime.utc(2027, 3, 28, 1, 0)), '2027-03-28 04:00');
      expect(wall(DateTime.utc(2027, 10, 31, 1, 0)), '2027-10-31 03:00');
    });
  });

  test(
    'elapsed time across spring forward is real time, not wall-clock difference',
    () {
      final before = BucharestTime.fromWallClock(2026, 3, 29, 2, 45);
      final after = BucharestTime.fromWallClock(2026, 3, 29, 4, 30);
      // 02:45 -> 04:30 on the wall is 1h45m, but only 45 minutes really passed.
      expect(after.difference(before), const Duration(minutes: 45));
    },
  );
}
