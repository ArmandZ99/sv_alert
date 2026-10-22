import 'dart:io';

import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

final weekFrom = DateTime.utc(2026, 10, 19);
final weekTo = DateTime.utc(2026, 10, 26);

List<NormalizedService> expand(
  SourceDescriptor d,
  List<SchedulePattern> patterns, {
  DateTime? from,
  DateTime? to,
}) =>
    expandPatterns(
      source: d,
      patterns: patterns,
      from: from ?? weekFrom,
      to: to ?? weekTo,
      fetchedAt: DateTime.utc(2026, 10, 21, 9),
    );

void main() {
  group('airport timetable', () {
    final parsed = AirportTimetableAdapter.parse(fixture('airport_page.html'));

    test('reads the validity period from the page heading', () {
      expect(parsed.validFrom, DateTime.utc(2026, 3, 29));
      expect(parsed.validTo, DateTime.utc(2026, 10, 24));
    });

    test('keeps arrivals only and skips unreadable rows', () {
      final numbers = parsed.patterns.map((p) => p.serviceNumber).toSet();
      expect(numbers, {'XX 100', 'XX 102', 'XX 104', 'XX 106'});
      expect(numbers, isNot(contains('XX 999')), reason: 'departure-like row');
      expect(numbers, isNot(contains('XX 777')), reason: 'unreadable time');
    });

    test('merges the same flight across weekdays into one pattern', () {
      final xx100 =
          parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 100');
      expect(
        xx100.calendar.single.weekdays,
        {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.sunday
        },
      );
    });

    test('carries airline, full route and the arrival airport', () {
      final p = parsed.patterns.firstWhere((p) => p.serviceNumber == 'XX 100');
      expect(p.operatorName, 'Example Air');
      expect(p.routeStops, ['Alpha City (AAA)', 'Aeroportul Suceava (SCV)']);
      expect(p.arrivalPoint, 'Aeroportul Suceava (SCV)');
      expect(p.arrivalMinutes, 8 * 60 + 45);
    });

    test('"(+1)" arrivals fall on the following calendar day', () {
      final p = parsed.patterns.firstWhere((p) => p.serviceNumber == 'XX 102');
      expect(p.arrivalMinutes, 1440 + 95);
    });

    test('expansion respects weekdays and never goes past the validity end',
        () {
      final services =
          expand(AirportTimetableAdapter().descriptor, parsed.patterns);
      final xx100 = services.where((s) => s.serviceNumber == 'XX 100');
      // Mon 19, Tue 20, Wed 21 only: Sunday 25 is after the period ends (24 Oct).
      expect(xx100.map((s) => s.serviceDate.day), [19, 20, 21]);
      expect(
          services
              .where((s) => s.serviceNumber == 'XX 104')
              .single
              .serviceDate
              .day,
          22);
      expect(services.every((s) => s.dataQuality == DataQuality.scheduled),
          isTrue);
    });

    test('a page without a validity heading is rejected, not guessed', () {
      final broken =
          fixture('airport_page.html').replaceAll('PENTRU PERIOADA', 'PENTRU');
      expect(
          () => AirportTimetableAdapter.parse(broken), throwsFormatException);
    });

    test('a page without arrival tables is rejected', () {
      expect(
        () => AirportTimetableAdapter.parse(
            '<html><body>PENTRU PERIOADA 29 MARTIE 2026 - 24 OCTOMBRIE 2026</body></html>'),
        throwsFormatException,
      );
    });
  });

  group('TASA', () {
    final patterns = TasaAdapter.parse(fixture('tasa_routes.html'));

    test('cards ending in Suceava give one arrival per published time', () {
      final fromCard = patterns
          .where((p) => p.serviceNumber == 'TASA Orașul A – Suceava')
          .toList();
      expect(
          fromCard.map((p) => p.arrivalMinutes), [17 * 60 + 45, 23 * 60 + 30]);
      expect(fromCard.first.routeStops, ['Orașul A', 'Suceava']);
      expect(fromCard.first.arrivalPoint, 'Autogara Nouă TASA, Suceava');
      expect(fromCard.first.operatorName, TasaAdapter.operatorName);
    });

    test('departures from Suceava and unrelated routes are not arrivals', () {
      expect(patterns.where((p) => p.routeStops.first == 'Suceava'), isEmpty);
      expect(patterns.any((p) => p.routeStops.contains('Orașul B')), isFalse);
    });

    test(
        'a pass-through stop table gives the arrival with the real stop and full route',
        () {
      final p = patterns
          .singleWhere((p) => p.serviceNumber == 'TASA Orasul D – Orasul E');
      expect(p.routeStops, ['Orasul D', 'Suceava', 'Orasul F', 'Orasul E']);
      expect(p.arrivalMinutes, 6 * 60 + 50);
      expect(p.arrivalPoint, 'Autogara Noua TASA, Suceava');
    });

    test('a page with no routes is rejected', () {
      expect(() => TasaAdapter.parse('<html><body>nothing</body></html>'),
          throwsFormatException);
    });
  });

  group('airport transfer', () {
    final patterns =
        AirportTransferAdapter.parse(fixture('airport_transfer.html'));

    test('legs ending in Suceava and Salcea become arrivals; other legs do not',
        () {
      final summary = {
        for (final p in patterns)
          '${p.serviceNumber}|${p.arrivalPoint}': p.arrivalMinutes,
      };
      expect(summary, {
        'Transfer Cernăuți – Suceava – Aeroport (Ruta 1)|Autogara Suceava':
            7 * 60 + 50,
        'Transfer Cernăuți – Suceava – Aeroport (Ruta 1)|Aeroportul Suceava (Salcea)':
            8 * 60 + 30,
        'Transfer Cernăuți – Suceava – Aeroport (Ruta 2)|Autogara Suceava':
            16 * 60 + 50,
        'Transfer Cernăuți – Suceava – Aeroport (Ruta 2)|Aeroportul Suceava (Salcea)':
            17 * 60 + 30,
        'Transfer Aeroport – Suceava – Cernăuți (Ruta 1)|Autogara Suceava':
            12 * 60 + 30,
      });
    });

    test('each arrival carries the table\'s full route', () {
      final p = patterns.firstWhere((p) => p.arrivalMinutes == 7 * 60 + 50);
      expect(p.routeStops, ['Town A', 'Border', 'Suceava', 'Salcea']);
      final back =
          patterns.singleWhere((p) => p.arrivalMinutes == 12 * 60 + 30);
      expect(back.routeStops, ['Salcea', 'Suceava', 'Border', 'Town A']);
    });

    test('operators are named without claiming which one runs each trip', () {
      expect(patterns.first.operatorName, contains('NICOLMIT'));
      expect(patterns.first.operatorName, contains('nu este precizat'));
    });

    test('a page without route tables is rejected', () {
      expect(
          () => AirportTransferAdapter.parse(
              '<html><body><table><tr><td>x</td></tr></table></body></html>'),
          throwsFormatException);
    });
  });

  group('rail timetable', () {
    late ParsedRailTimetable parsed;
    setUpAll(() async {
      parsed = await RailTimetableAdapter.parse(
        fixture('rail_excerpt.xml'),
        operatorName: 'CFR Călători',
        sourceUrl: 'https://example.org/dataset',
      );
    });

    test('reads the validity and export dates from the file header', () {
      expect(parsed.validFrom, DateTime.utc(2025, 12, 14));
      expect(parsed.validTo, DateTime.utc(2026, 12, 12));
      expect(parsed.exportDate, DateTime.utc(2025, 12, 3));
      expect(parsed.trainsSeen, 7);
    });

    test(
        'only real passenger stops count: not N, not T; C, A and the final stop do',
        () {
      final stops = {
        for (final p in parsed.patterns) '${p.serviceNumber}|${p.arrivalPoint}'
      };
      expect(stops, {
        'IR 9001|Gara Suceava',
        'IR 9001|Gara Suceava Nord',
        'R 9002|Gara Suceava Vest',
        'IR 9005|Gara Suceava',
        'IR-N 9006|Gara Suceava',
      });
    });

    test(
        'the route lists the origin, commercial stops and destination with tidy names',
        () {
      final p = parsed.patterns.firstWhere((p) => p.serviceNumber == 'IR 9001');
      expect(p.routeStops,
          ['Alpha Nord', 'Midway', 'Beta', 'Suceava', 'Suceava Nord']);
      expect(p.sourceUrl, 'https://example.org/dataset');
      expect(p.operatorName, 'CFR Călători');
    });

    test(
        'calendars: unknown entry types and entries without weekday bits are skipped and counted',
        () {
      expect(parsed.skippedCalendars, 2);
      expect(parsed.patterns.any((p) => p.serviceNumber == 'R 9007'), isFalse);
    });

    test('weekday bits map Monday..Sunday: 352 means Saturday and Sunday', () {
      final p = parsed.patterns.firstWhere((p) => p.serviceNumber == 'R 9002');
      expect(p.calendar.single.weekdays, {DateTime.saturday, DateTime.sunday});
    });

    test('expansion: daily train every day, weekend train only on the weekend',
        () {
      final services = expand(
          RailTimetableAdapter(datasets: const []).descriptor, parsed.patterns);
      expect(
          services.where((s) =>
              s.serviceNumber == 'IR 9001' && s.arrivalPoint == 'Gara Suceava'),
          hasLength(7));
      final weekend =
          services.where((s) => s.serviceNumber == 'R 9002').toList();
      expect(weekend.map((s) => s.serviceDate.day), [24, 25]);
      // 08:30 local: 05:30 UTC on Sat 24 (summer time), 06:30 UTC on Sun 25
      // (winter time began that morning).
      expect(weekend.map((s) => s.scheduledArrival.hour), [5, 6]);
    });

    test('an arrival past midnight lands on the next day, service date stays',
        () {
      final services = expand(
          RailTimetableAdapter(datasets: const []).descriptor, parsed.patterns,
          from: DateTime.utc(2026, 10, 21), to: DateTime.utc(2026, 10, 22));
      final late =
          services.where((s) => s.serviceNumber == 'IR-N 9006').toList();
      // 87000 s = 24:10: 00:10 on the day after the operating day. The 21st's
      // train arrives at 00:10 EEST on the 22nd = 21:10 UTC on the 21st.
      expect(
          late.map((s) => (
                s.serviceDate.day,
                s.scheduledArrival.hour,
                s.scheduledArrival.minute
              )),
          [(21, 21, 10)]);
    });

    test('services are scheduled-only: no estimate, no delay, no live flag',
        () {
      final services = expand(
          RailTimetableAdapter(datasets: const []).descriptor, parsed.patterns);
      for (final s in services) {
        final json = s.toJson();
        expect(json['dataQuality'], 'scheduled');
        expect(json['estimatedArrival'], isNull);
      }
    });

    test('a file without a header or trains is rejected', () async {
      await expectLater(
        RailTimetableAdapter.parse('<XmlIf/>',
            operatorName: 'x', sourceUrl: 'y'),
        throwsFormatException,
      );
      await expectLater(
        RailTimetableAdapter.parse(
          '<XmlIf><Mt DataExport="20251203" MtValabilDeLa="20251214" MtValabilPinaLa="20261212"><Trenuri/></Mt></XmlIf>',
          operatorName: 'x',
          sourceUrl: 'y',
        ),
        throwsFormatException,
      );
    });
  });
}
