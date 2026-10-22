import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

import 'airport_support.dart';

/// 09:00 UTC is 12:00 in Bucharest before the clock change and 11:00 after it.
DateTime day(int month, int d, [int hour = 9]) =>
    DateTime.utc(2026, month, d, hour);

String summary(NormalizedService s) =>
    '${s.serviceNumber} ${s.serviceDate.toIso8601String().substring(0, 10)} '
    '${s.scheduledArrival.toIso8601String().substring(0, 16)}Z';

void main() {
  group('what the page really contains', () {
    test(
        'only the summer season is in HTML tables; winter appears only as PDF links',
        () {
      final body = fixtureText('airport_page.html');
      final tables = AirportTimetableAdapter.parse(body);
      expect(tables.validFrom, DateTime.utc(2026, 3, 29));
      expect(tables.validTo, DateTime.utc(2026, 10, 24));
      // The winter period is named in the page, but only as link text.
      expect(body, contains('PERIOADA 25 OCTOMBRIE 2026'));
    });

    test('the table period ignores the other seasons named in PDF links', () {
      // The winter tables page also links both PDFs; its own heading wins.
      final tables = AirportTimetableAdapter.parse(
          fixtureText('airport_page_winter_tables.html'));
      expect(tables.validFrom, DateTime.utc(2026, 10, 25));
      expect(tables.validTo, DateTime.utc(2027, 3, 27));
    });

    test('only same-host https PDF links to arrivals are discovered', () {
      final docs = AirportTimetableAdapter.discoverArrivalDocuments(
        fixtureText('airport_page.html'),
        pageUrl,
      );
      expect([
        for (final d in docs) d.url.path
      ], [
        '/images/example/SOSIRI_VARA.pdf',
        '/images/example/SOSIRI_IARNA.pdf',
      ]);
      expect(docs.first.validTo, DateTime.utc(2026, 10, 24));
      expect(docs.last.validFrom, DateTime.utc(2026, 10, 25));
      // Not departures, not another host, not an unrelated PDF.
      expect(docs.any((d) => d.url.path.contains('PLECARI')), isFalse);
      expect(docs.any((d) => d.url.host != 'aeroportsuceava.ro'), isFalse);
    });
  });

  group('the October 24 / 25 season boundary', () {
    final from = day(10, 24, 0);
    final to = day(10, 27, 0);
    late List<NormalizedService> services;
    late AirportRig rig;
    late AdapterLoad load;

    setUp(() async {
      rig = AirportRig();
      load = await rig.load(day(10, 21));
      services = rig.services(load, from, to);
    });

    test(
        'summer and winter services are both produced, each only inside its own season',
        () {
      expect(services.map(summary), [
        'XX 106 2026-10-24 2026-10-24T22:35Z', // summer Saturday, arrives 01:35 local on the 25th
        'XX 100 2026-10-25 2026-10-25T06:50Z', // winter Sunday 08:50 (UTC+2: the clocks changed at 04:00)
        'XX 102 2026-10-25 2026-10-25T23:35Z', // winter Sunday, (+1): 01:35 local on the 26th
        'XX 100 2026-10-26 2026-10-26T06:50Z', // winter Monday
        'XX 110 2026-10-26 2026-10-26T11:40Z',
        'XX 102 2026-10-26 2026-10-26T23:35Z', // winter Monday, (+1)
      ]);
    });

    test(
        'the summer Sunday timetable does not leak into the first winter Sunday',
        () {
      final sunday = services
          .where((s) => s.serviceNumber == 'XX 100' && s.serviceDate.day == 25);
      expect(sunday, hasLength(1));
      // Summer would have been 06:00 -> 08:45 EEST = 05:45 UTC; winter is 08:50 EET = 06:50 UTC.
      expect(sunday.single.scheduledArrival, DateTime.utc(2026, 10, 25, 6, 50));
    });

    test(
        'summer-only flights stop on the 24th and winter-only flights start on the 25th',
        () {
      final all = rig.services(load, day(10, 18, 0), day(11, 3, 0));
      final summerOnly = all.where(
          (s) => s.serviceNumber == 'XX 104' || s.serviceNumber == 'XX 106');
      expect(summerOnly, isNotEmpty);
      expect(
          summerOnly
              .every((s) => !s.serviceDate.isAfter(DateTime.utc(2026, 10, 24))),
          isTrue);
      final winterOnly = all.where(
          (s) => s.serviceNumber == 'XX 110' || s.serviceNumber == 'XX 120');
      expect(winterOnly, isNotEmpty);
      expect(
          winterOnly.every(
              (s) => !s.serviceDate.isBefore(DateTime.utc(2026, 10, 25))),
          isTrue);
    });

    test('no service appears twice', () {
      final all = rig.services(load, day(10, 18, 0), day(12, 31, 0));
      expect(all.map((s) => s.id).toSet().length, all.length);
    });

    test('weekdays follow the season in force: summer Saturday, winter Sunday',
        () {
      final dates = {
        for (final s in services)
          s.serviceDate.day: DateTime.utc(2026, 10, s.serviceDate.day).weekday
      };
      expect(dates,
          {24: DateTime.saturday, 25: DateTime.sunday, 26: DateTime.monday});
    });

    test('the status stays scheduled-only and names both seasons', () {
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.message, contains('29.03.2026-24.10.2026 (pagina)'));
      expect(load.message, contains('25.10.2026-27.03.2027 (PDF)'));
      expect(load.validFrom, DateTime.utc(2026, 3, 29));
      expect(load.validTo, DateTime.utc(2027, 3, 27));
    });
  });

  group('once the summer period has ended', () {
    test(
        'the source is NOT reported unavailable while a valid winter timetable can be used',
        () async {
      final rig = AirportRig();
      final load = await rig.load(day(10, 26));
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.message, isNot(contains('(pagina)')),
          reason: 'the expired season is not offered');
      expect(load.message, contains('25.10.2026-27.03.2027 (PDF)'));
      final services = rig.services(load, day(10, 26, 0), day(10, 28, 0));
      expect(services, isNotEmpty);
      expect(services.map((s) => s.serviceNumber).toSet(),
          isNot(contains('XX 104')));
    });

    test('winter weekdays: Monday services on Mondays only', () async {
      final rig = AirportRig();
      final load = await rig.load(day(10, 26));
      final all = rig.services(load, day(10, 26, 0), day(11, 3, 0));
      final xx110 = all.where((s) => s.serviceNumber == 'XX 110');
      expect(
          xx110.map((s) => s.serviceDate.weekday).toSet(), {DateTime.monday});
      expect(xx110.map((s) => '${s.serviceDate.month}-${s.serviceDate.day}'),
          ['10-26', '11-2']);
    });

    test(
        'date-limited winter rows start and stop on their stated dates, inclusively',
        () async {
      final rig = AirportRig();
      final now = day(12, 1);
      final load = await rig.load(now);
      final all = rig.services(load, day(12, 6, 0), DateTime.utc(2027, 1, 5));
      final until = all
          .where((s) => s.serviceNumber == 'XX 110')
          .map((s) => s.serviceDate.day);
      // "Operează până pe 14.12.2026": Mondays 7 and 14 December, not the 21st or 28th.
      expect(until.toList(), [7, 14]);
      final from = all
          .where((s) => s.serviceNumber == 'XX 120')
          .map((s) => '${s.serviceDate.month}-${s.serviceDate.day}')
          .toList();
      // "Începând din 21.12.2026": Mondays from 21 December on.
      expect(from, ['12-21', '12-28', '1-4']);
    });

    test(
        'overnight (+1) winter arrivals land on the next calendar day with correct UTC',
        () async {
      final rig = AirportRig();
      final load = await rig.load(day(11, 2));
      final all = rig.services(load, day(11, 2, 0), day(11, 4, 0));
      final overnight = all.where((s) => s.serviceNumber == 'XX 102').toList();
      // Monday 2 Nov 20:25 -> 01:35 (+1) on Tuesday 3 Nov, UTC+2: 23:35 UTC on the 2nd.
      expect(overnight.map(summary),
          contains('XX 102 2026-11-02 2026-11-02T23:35Z'));
      expect(overnight.first.scheduledArrival.toUtc().isUtc, isTrue);
    });
  });

  group('failing seasons do not take the whole source down', () {
    test(
        'with the winter PDF unreadable, the valid summer timetable is still served',
        () async {
      final rig = AirportRig(extractor: MissingToolExtractor());
      final load = await rig.load(day(10, 21));
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.patterns, isNotEmpty);
      expect(load.message, contains('nu a putut fi citit'));
      expect(load.message, contains('pdftotext'));
    });

    test(
        'with the winter PDF unavailable and the summer over, it is unavailable, with the reason',
        () async {
      final rig = AirportRig(extractor: MissingToolExtractor());
      final load = await rig.load(day(10, 26));
      expect(load.connection, SourceConnection.unavailable);
      expect(load.patterns, isEmpty);
      expect(load.message, contains('Niciun orar publicat nu acoperă'));
      expect(load.message, contains('pdftotext'));
    });

    test('a PDF the server refuses or does not have is reported, not fatal',
        () async {
      for (final status in [404, 500]) {
        final load = await AirportRig(pdfStatus: status).load(day(10, 21));
        expect(load.connection, SourceConnection.scheduledOnly,
            reason: 'HTTP $status');
        expect(load.message, contains('nu a putut fi preluat'));
      }
    });

    test('a PDF with an unexpected structure is ignored and flagged', () async {
      final rig = AirportRig(
          extractor: FixtureExtractor(text: 'something else entirely'));
      final load = await rig.load(day(10, 21));
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.message, contains('structura nu este cea așteptată'));
      expect(
          load.patterns
              .every((p) => p.calendar.single.to == DateTime.utc(2026, 10, 24)),
          isTrue);
    });

    test('a PDF whose own period differs from its link is not used', () async {
      final text = fixtureText('airport_winter_arrivals.txt')
          .replaceAll('27 MARTIE 2027', '27 FEBRUARIE 2027');
      final rig = AirportRig(extractor: FixtureExtractor(text: text));
      final load = await rig.load(day(10, 26));
      expect(load.connection, SourceConnection.unavailable);
      expect(load.message, contains('nu corespunde legăturii'));
    });

    test('rows rejected inside the PDF are reported in the status and not used',
        () async {
      final load = await AirportRig().load(day(10, 21));
      expect(
          load.message,
          contains(
              '4 rânduri din PDF-ul 25.10.2026-27.03.2027 au fost respinse'));
      expect(load.message, contains('posibilă eroare în sursă'));
    });
  });

  group('no duplicates when the page itself switches to winter tables', () {
    test(
        'the PDF for a period already in the tables is not fetched, nor is the ended summer one',
        () async {
      final rig =
          AirportRig(page: fixtureText('airport_page_winter_tables.html'));
      final load = await rig.load(day(10, 26));
      expect(rig.fetchedPaths, ['/ro/2016-01-29-10-35-08'],
          reason: 'only the page; no PDF request');
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.message, contains('25.10.2026-27.03.2027 (pagina)'));
      expect(load.message, isNot(contains('(PDF)')));

      final all = rig.services(load, day(10, 25, 0), day(11, 9, 0));
      expect(all.map((s) => s.id).toSet().length, all.length);
      // XX 100 Sunday 25 Oct and Monday 26 Oct, from the tables only.
      expect(
          all
              .where((s) => s.serviceNumber == 'XX 100')
              .map((s) => s.serviceDate.day)
              .take(2),
          [25, 26]);
    });
  });

  group('fetching', () {
    test('a later season is not fetched until it is within the prefetch window',
        () async {
      final rig = AirportRig();
      final load = await rig.load(day(8, 1)); // winter starts in 85 days
      expect(rig.fetchedPaths, ['/ro/2016-01-29-10-35-08']);
      expect(load.message, isNot(contains('(PDF)')));
    });

    test(
        'exactly the winter arrivals PDF is fetched in the days before the boundary',
        () async {
      final rig = AirportRig();
      await rig.load(day(10, 21));
      expect(rig.fetchedPaths, ['/ro/2016-01-29-10-35-08', winterPdfPath]);
    });

    test('after the last published season ends, nothing covers today',
        () async {
      final rig = AirportRig();
      final load = await rig.load(DateTime.utc(2027, 4, 2, 9));
      expect(load.connection, SourceConnection.unavailable);
      expect(load.message, contains('27.03.2027'));
    });
  });

  test(
      'every produced service is scheduled data: no estimate, no live classification',
      () async {
    final rig = AirportRig();
    final load = await rig.load(day(10, 21));
    for (final s in rig.services(load, day(10, 21, 0), day(11, 30, 0))) {
      final json = s.toJson();
      expect(json['dataQuality'], 'scheduled');
      expect(json['estimatedArrival'], isNull);
      expect(json['actualArrival'], isNull);
    }
  });
}
