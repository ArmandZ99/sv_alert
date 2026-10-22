import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

import 'airport_support.dart';

const header = '''
ORARUL ZBORURILOR REGULATE DE PE AEROPORTUL EXEMPLU PENTRU PERIOADA 25 OCTOMBRIE 2026 – 27 MARTIE 2027
SOSIRI
ZIUA NR. ZBOR COMPANIA AERONAVA DE LA LA
ORA DE
PLECARE**
ORA DE
SOSIRE**
OBSERVAȚII
''';

String pdf(List<String> rows) => '$header${rows.join('\n')}\n';

Map<String, SchedulePattern> byKey(ParsedAirportTimetable t) => {
      for (final p in t.patterns)
        '${p.serviceNumber}|${p.routeStops.first}|${p.calendar.single.from.toIso8601String().substring(0, 10)}|'
            '${p.calendar.single.to.toIso8601String().substring(0, 10)}': p,
    };

void main() {
  final parsed = AirportPdfTimetableParser.parse(
      fixtureText('airport_winter_arrivals.txt'));

  test('the period comes from the title', () {
    expect(parsed.validFrom, DateTime.utc(2026, 10, 25));
    expect(parsed.validTo, DateTime.utc(2027, 3, 27));
  });

  test(
      'accepted rows keep number, airline, origin, arrival point and a scheduled time',
      () {
    final p = parsed.patterns.firstWhere((p) => p.serviceNumber == 'XX 100');
    expect(p.operatorName, 'Example Air');
    expect(p.routeStops, ['Alpha City (AAA)', 'Aeroportul Suceava (SCV)']);
    expect(p.arrivalPoint, 'Aeroportul Suceava (SCV)');
    expect(p.arrivalMinutes, 8 * 60 + 50);
  });

  test('both spellings of Tuesday and every weekday map to the right day', () {
    final xx100 =
        parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 100');
    expect(
      xx100.calendar.single.weekdays,
      {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.sunday},
    );
  });

  test('"(+1)" arrivals fall on the next day and merge across weekdays', () {
    final xx102 =
        parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 102');
    expect(xx102.arrivalMinutes, 1440 + 95);
    // Friday is rejected (see below), so only these four days remain.
    expect(
      xx102.calendar.single.weekdays,
      {DateTime.monday, DateTime.tuesday, DateTime.thursday, DateTime.sunday},
    );
  });

  test('a row without an aircraft code is read correctly', () {
    final p = parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 120');
    expect(p.operatorName, 'Sample Lines');
    expect(p.routeStops.first, 'Delta (DDD)');
  });

  test('"Operează până pe" and "Începând din" narrow the dates, inclusively',
      () {
    final until =
        parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 110');
    expect(until.calendar.single.from, DateTime.utc(2026, 10, 25));
    expect(until.calendar.single.to, DateTime.utc(2026, 12, 14));
    final from =
        parsed.patterns.singleWhere((p) => p.serviceNumber == 'XX 120');
    expect(from.calendar.single.from, DateTime.utc(2026, 12, 21));
    expect(from.calendar.single.to, DateTime.utc(2027, 3, 27));
  });

  test(
      'a page break that repeats the header does not create rows or break the table',
      () {
    final numbers = parsed.patterns.map((p) => p.serviceNumber).toSet();
    expect(numbers, {'XX 100', 'XX 102', 'XX 110', 'XX 120'});
    expect(parsed.patterns.any((p) => p.serviceNumber == 'SOSIRI'), isFalse);
  });

  test('rows that cannot be trusted are rejected, each with its reason', () {
    expect(parsed.rejected, hasLength(4));
    final all = parsed.rejected.join('\n');
    // Transposed times in the source: 5 h 10 from a 3 h 20 route and 1 h 10 from a 5 h 10 route.
    expect(all, contains('XX 102 din Beta Town (BBB) (vineri)'));
    expect(all, contains('XX 200 din Alpha City (AAA) (vineri)'));
    expect(all, contains('posibilă eroare în sursă'));
    // An observation we do not understand.
    expect(all, contains('observație necunoscută «Zbor suspendat temporar»'));
    // From-date after until-date.
    expect(all, contains('XX 140'));
    expect(all, contains('intervalul de date este gol'));
    final numbers = parsed.patterns.map((p) => p.serviceNumber);
    expect(numbers, isNot(contains('XX 200')));
    expect(numbers, isNot(contains('XX 130')));
    expect(numbers, isNot(contains('XX 140')));
  });

  group('plausibility check', () {
    test('catches transposed times but leaves consistent rows alone', () {
      final text = pdf([
        'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Marți XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Joi XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:35 08:50',
        'Vineri XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 21:50 23:00',
      ]);
      final r = AirportPdfTimetableParser.parse(text);
      expect(r.rejected, hasLength(1));
      expect(
          r.patterns.map((p) => p.arrivalMinutes), everyElement(8 * 60 + 50));
    });

    test('small differences within the tolerance are accepted', () {
      final text = pdf([
        'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Marți XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Joi XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 09:05',
      ]);
      expect(AirportPdfTimetableParser.parse(text).rejected, isEmpty);
    });

    test('origins with fewer than three rows cannot be judged and are kept',
        () {
      final text = pdf([
        'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Marți XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 21:50 23:00',
      ]);
      final r = AirportPdfTimetableParser.parse(text);
      expect(r.rejected, isEmpty);
      expect(r.patterns, hasLength(2));
    });
  });

  group('dates outside the period or impossible', () {
    test('dated observations are clamped to the title period, never widened',
        () {
      final text = pdf([
        'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Începând din 01.01.2026',
        'Marți XX 101 EXAMPLE AIR A32Q Beta (BBB) Suceava (SCV) 05:30 08:50',
        'Operează până pe 01.01.2030',
      ]);
      final r = AirportPdfTimetableParser.parse(text);
      for (final p in r.patterns) {
        expect(p.calendar.single.from, DateTime.utc(2026, 10, 25));
        expect(p.calendar.single.to, DateTime.utc(2027, 3, 27));
      }
    });

    test('an impossible date is not guessed', () {
      final text = pdf([
        'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
        'Operează până pe 31.02.2027',
      ]);
      final r = AirportPdfTimetableParser.parse(text);
      expect(r.patterns, isEmpty);
      expect(r.rejected.single, contains('observație necunoscută'));
    });
  });

  group('wrong or changed documents are refused', () {
    test('a departures table', () {
      final text = pdf([
        'PLECĂRI',
        'Luni XX 1 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50'
      ]);
      expect(
          () => AirportPdfTimetableParser.parse(text), throwsFormatException);
    });

    test('no period in the title', () {
      expect(
        () => AirportPdfTimetableParser.parse(
            'SOSIRI\nZIUA NR. ZBOR\nLuni XX 100 A Alpha Suceava (SCV) 05:30 08:50'),
        throwsFormatException,
      );
    });

    test('no column header', () {
      expect(
        () => AirportPdfTimetableParser.parse(
          'ORARUL PENTRU PERIOADA 25 OCTOMBRIE 2026 – 27 MARTIE 2027\nSOSIRI\n',
        ),
        throwsFormatException,
      );
    });

    test('no flight rows', () {
      expect(() => AirportPdfTimetableParser.parse(pdf([])),
          throwsFormatException);
    });

    test('empty text', () {
      expect(() => AirportPdfTimetableParser.parse(''), throwsFormatException);
    });
  });

  test('unreadable rows are reported, not dropped silently', () {
    final text = pdf([
      'Luni XX 100 EXAMPLE AIR A32Q Alpha (AAA) Suceava (SCV) 05:30 08:50',
      'Marți XX Suceava (SCV) 05:30 08:50',
    ]);
    final r = AirportPdfTimetableParser.parse(text);
    expect(r.patterns, hasLength(1));
    expect(r.rejected.single, contains('rând necitibil'));
  });

  test('periodIn reads the period named in link text', () {
    final p = AirportPdfTimetableParser.periodIn(
      'ORARUL ... PENTRU PERIOADA 25 OCTOMBRIE 2026 – 27 MARTIE 2027 - SOSIRI',
    );
    expect(p, (DateTime.utc(2026, 10, 25), DateTime.utc(2027, 3, 27)));
    expect(AirportPdfTimetableParser.periodIn('Cod de conduita'), isNull);
  });

  test('keys are unique across the accepted patterns', () {
    expect(byKey(parsed).length, parsed.patterns.length);
  });
}
