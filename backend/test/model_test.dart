import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

const source = SourceDescriptor(
  id: 'src',
  name: 'Source',
  kind: TransportKind.train,
  url: 'https://example.org',
);

final fetchedAt = DateTime.utc(2026, 10, 21, 9);

SchedulePattern pattern({
  String number = 'T 1',
  int minutes = 600, // 10:00
  Set<int>? weekdays,
  DateTime? from,
  DateTime? to,
}) =>
    SchedulePattern(
      serviceNumber: number,
      routeStops: const ['A', 'Suceava'],
      arrivalPoint: 'Gara Suceava',
      arrivalMinutes: minutes,
      calendar: [
        CalendarEntry(
          from: from ?? DateTime.utc(2026, 1, 1),
          to: to ?? DateTime.utc(2026, 12, 31),
          weekdays: weekdays,
        ),
      ],
    );

List<NormalizedService> expand(
  List<SchedulePattern> patterns,
  DateTime from,
  DateTime to,
) =>
    expandPatterns(
      source: source,
      patterns: patterns,
      from: from,
      to: to,
      fetchedAt: fetchedAt,
    );

void main() {
  test('a daily pattern yields one service per day in the window', () {
    final r = expand(
        [pattern()], DateTime.utc(2026, 10, 19), DateTime.utc(2026, 10, 22));
    expect(r.map((s) => s.serviceDate.day), [19, 20, 21]);
    // 10:00 in Bucharest (EEST, +3) is 07:00 UTC.
    expect(r.first.scheduledArrival, DateTime.utc(2026, 10, 19, 7));
  });

  test('weekday filter uses the service date', () {
    // Monday = 1. 2026-10-19 is a Monday.
    final r = expand(
      [
        pattern(weekdays: {DateTime.monday, DateTime.friday})
      ],
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 26),
    );
    expect(r.map((s) => s.serviceDate.day), [19, 23]);
  });

  test('the calendar range limits the services produced', () {
    final r = expand(
      [
        pattern(
            from: DateTime.utc(2026, 10, 20), to: DateTime.utc(2026, 10, 21))
      ],
      DateTime.utc(2026, 10, 18),
      DateTime.utc(2026, 10, 25),
    );
    expect(r.map((s) => s.serviceDate.day), [20, 21]);
  });

  test('an arrival on the next day keeps the operating day as service date',
      () {
    final r = expand(
      [pattern(minutes: 1440 + 95)], // 01:35 next day
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 21),
    );
    final first = r.first;
    expect(first.serviceDate, DateTime.utc(2026, 10, 19));
    // 01:35 on Oct 20 in Bucharest = 22:35 UTC on Oct 19.
    expect(first.scheduledArrival, DateTime.utc(2026, 10, 19, 22, 35));
  });

  test('a long journey is found even when it began days before the window', () {
    final r = expand(
      [pattern(minutes: 2 * 1440 + 60)],
      DateTime.utc(2026, 10, 21),
      DateTime.utc(2026, 10, 22),
    );
    // Operating day 20 arrives on the 22nd (01:00 local); day 19 would arrive
    // on the 21st at 01:00 local, which is before this window starts.
    expect(r.map((s) => s.serviceDate.day), [20]);
  });

  test('the window is inclusive at both ends', () {
    final at = DateTime.utc(2026, 10, 21, 7);
    final r = expand([pattern()], at, at);
    expect(r, hasLength(1));
    expect(
        expand([pattern()], at.add(const Duration(seconds: 1)),
            at.add(const Duration(hours: 1))),
        isEmpty);
  });

  group('daylight saving', () {
    test('a time that does not exist on the spring change day moves forward',
        () {
      // 2026-03-29, 03:30 does not exist; it is read as 04:30 EEST (01:30 UTC).
      final r = expand(
        [pattern(minutes: 3 * 60 + 30)],
        DateTime.utc(2026, 3, 29),
        DateTime.utc(2026, 3, 30),
      );
      expect(r.first.scheduledArrival, DateTime.utc(2026, 3, 29, 1, 30));
    });

    test(
        'an ambiguous time on the autumn change day takes the first occurrence',
        () {
      final r = expand(
        [pattern(minutes: 3 * 60 + 30)],
        DateTime.utc(2026, 10, 25),
        DateTime.utc(2026, 10, 26),
      );
      expect(r.first.scheduledArrival, DateTime.utc(2026, 10, 25, 0, 30));
    });

    test('the same clock time is 07:00 UTC in summer and 08:00 UTC in winter',
        () {
      final summer = expand(
          [pattern()], DateTime.utc(2026, 7, 1), DateTime.utc(2026, 7, 2));
      final winter = expand(
          [pattern()], DateTime.utc(2026, 1, 15), DateTime.utc(2026, 1, 16));
      expect(summer.first.scheduledArrival.hour, 7);
      expect(winter.first.scheduledArrival.hour, 8);
    });
  });

  test('ids are stable, unique per day and time, and carry no spaces', () {
    final r = expand(
      [pattern(number: 'IR 1831'), pattern(number: 'IR 1831', minutes: 700)],
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 21),
    );
    expect(r.map((s) => s.id).toSet(), hasLength(r.length));
    expect(r.first.id, 'src:ir-1831:2026-10-19:gara-suceava:1000');
    expect(r.first.id, isNot(contains(' ')));
  });

  test('output is sorted by arrival and records freshness', () {
    final r = expand(
      [pattern(minutes: 900), pattern(number: 'T 2', minutes: 300)],
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 20),
    );
    expect(r.map((s) => s.serviceNumber), ['T 2', 'T 1']);
    expect(r.every((s) => s.lastUpdated == fetchedAt), isTrue);
  });

  test('scheduled services carry no estimate, actual time or cancellation', () {
    final json = expand(
            [pattern()], DateTime.utc(2026, 10, 19), DateTime.utc(2026, 10, 20))
        .first
        .toJson();
    expect(json['dataQuality'], 'scheduled');
    expect(json['estimatedArrival'], isNull);
    expect(json['actualArrival'], isNull);
    expect(json['isCancelled'], false);
    expect((json['source'] as Map)['isMock'], false);
    expect(json['scheduledArrival'], endsWith('Z'));
  });
}
