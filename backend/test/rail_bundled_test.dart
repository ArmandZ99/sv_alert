import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 10, 22, 12);

/// A fetcher that records every request; the bundled path must make none.
PoliteFetcher offline(List<Uri> requests) => PoliteFetcher(
      userAgent: 'test',
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response('', 500);
      }),
      sleep: (_) async {},
    );

RailDataset dataset(String? bundledPath) => RailDataset(
      url: Uri.parse('https://data.example.org/rail.xml'),
      operatorName: 'Operator Test',
      pageUrl: 'https://data.example.org/dataset',
      bundledPath: bundledPath,
    );

void main() {
  late Directory dir;
  final xml = File('test/fixtures/rail_excerpt.xml').readAsBytesSync();

  setUp(() => dir = Directory.systemTemp.createTempSync('rail_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a bundled gzip file is used without any network request', () async {
    final path = '${dir.path}/rail.xml.gz';
    File(path).writeAsBytesSync(gzip.encode(xml));
    final requests = <Uri>[];
    final load = await RailTimetableAdapter(datasets: [dataset(path)])
        .load(offline(requests), now);
    expect(requests, isEmpty);
    expect(load.patterns, isNotEmpty);
    expect(load.connection, SourceConnection.scheduledOnly);
    expect(load.message, contains('incluse în serviciu'));
    expect(load.message, contains('03.12.2025'));
    expect(load.fetchedAt, now);
    expect(load.validTo, DateTime.utc(2026, 12, 12));
  });

  test('a plain .xml file works too', () async {
    final path = '${dir.path}/rail.xml';
    File(path).writeAsBytesSync(xml);
    final load = await RailTimetableAdapter(datasets: [dataset(path)])
        .load(offline([]), now);
    expect(load.patterns, isNotEmpty);
  });

  test('without the file the dataset is downloaded as before', () async {
    final requests = <Uri>[];
    final fetcher = PoliteFetcher(
      userAgent: 'test',
      client: MockClient((r) async {
        requests.add(r.url);
        return r.url.path == '/robots.txt'
            ? http.Response('', 404)
            : http.Response.bytes(xml, 200);
      }),
      sleep: (_) async {},
    );
    final load = await RailTimetableAdapter(
      datasets: [dataset('${dir.path}/missing.xml.gz')],
    ).load(fetcher, now);
    expect(requests.map((u) => u.path), contains('/rail.xml'));
    expect(load.patterns, isNotEmpty);
    expect(load.message, isNot(contains('incluse în serviciu')));
  });

  test('a corrupt bundled file is reported, not replaced by a download',
      () async {
    final path = '${dir.path}/rail.xml.gz';
    File(path).writeAsBytesSync(utf8.encode('not gzip'));
    final requests = <Uri>[];
    await expectLater(
      RailTimetableAdapter(datasets: [dataset(path)])
          .load(offline(requests), now),
      throwsA(isA<FetchException>()),
    );
    expect(requests, isEmpty);
  });

  test('an expired bundled timetable is unavailable and yields no trains',
      () async {
    final path = '${dir.path}/rail.xml.gz';
    File(path).writeAsBytesSync(gzip.encode(xml));
    final load = await RailTimetableAdapter(datasets: [dataset(path)])
        .load(offline([]), DateTime.utc(2027, 1, 5, 12));
    expect(load.connection, SourceConnection.unavailable);
    expect(load.patterns, isEmpty);
    expect(load.message, contains('expirat'));
  });

  group('the files shipped in data/rail', () {
    test('are the official files, valid for the current year, with Suceava',
        () async {
      final adapter = RailTimetableAdapter(
        datasets: railDatasetsFor(defaultRailDataDir),
      );
      final requests = <Uri>[];
      final load = await adapter.load(offline(requests), now);
      expect(requests, isEmpty, reason: 'no robots.txt, no download');
      expect(load.connection, SourceConnection.scheduledOnly);
      expect(load.validFrom, DateTime.utc(2025, 12, 14));
      expect(load.validTo, DateTime.utc(2026, 12, 12));
      expect(load.patterns.length, greaterThan(50));
      final points = load.patterns.map((p) => p.arrivalPoint).toSet();
      expect(points, contains('Gara Suceava'));
      final operators = load.patterns.map((p) => p.operatorName).toSet();
      // The Interregional file is read too, but none of its trains call at a
      // Suceava station (checked in the file), so only CFR contributes.
      expect(operators, {'CFR Călători'});
      final services = expandPatterns(
        source: adapter.descriptor,
        patterns: load.patterns,
        from: DateTime.utc(2026, 10, 22),
        to: DateTime.utc(2026, 10, 24),
        fetchedAt: now,
      );
      expect(services, isNotEmpty);
      expect(
        services.every((s) => s.dataQuality == DataQuality.scheduled),
        isTrue,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('configuration', () {
    BackendConfig config(Map<String, String> extra) =>
        BackendConfig.fromEnvironment(
            {'TRAVEL_ALERTS_CONTACT': 'a@b.c', ...extra});

    test('both datasets default to the shipped files', () {
      expect(
        config({}).railDatasets.map((d) => d.bundledPath),
        ['data/rail/sntfc.xml.gz', 'data/rail/interregional.xml.gz'],
      );
      expect(BackendConfig(contact: 'x').railDatasets.first.bundledPath,
          'data/rail/sntfc.xml.gz');
    });

    test('RAIL_DATA_DIR moves them; a URL override turns one off', () {
      final c = config({
        'RAIL_DATA_DIR': '/srv/rail',
        'RAIL_SNTFC_URL': 'https://example.org/x.xml',
      });
      expect(c.railDatasets[0].bundledPath, isNull);
      expect(c.railDatasets[0].url.toString(), 'https://example.org/x.xml');
      expect(c.railDatasets[1].bundledPath, '/srv/rail/interregional.xml.gz');
    });
  });
}
