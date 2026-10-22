import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

import 'airport_support.dart';

/// Full path with the real adapters: a fake network serves the fixture files at
/// the real URLs, so fetching, robots handling, parsing, expansion and JSON
/// output are all exercised together.
final fixedNow = DateTime.utc(2026, 10, 21, 9);
final railUrl = Uri.parse('https://data.example.org/rail.xml');
const winterPdfUrl =
    'https://aeroportsuceava.ro/images/example/SOSIRI_IARNA.pdf';

String fixture(String name) => fixtureText(name);

class FakeNetwork {
  FakeNetwork({this.failing = const {}, this.overrides = const {}});

  final Set<String> failing;

  /// URL fragment to body, replacing the fixture for matching URLs.
  final Map<String, String> overrides;
  final List<Uri> requested = [];

  late final MockClient client = MockClient((request) async {
    requested.add(request.url);
    final url = request.url.toString();
    if (request.url.path == '/robots.txt') return http.Response('', 404);
    if (failing.any(url.contains)) return http.Response('boom', 500);
    for (final entry in overrides.entries) {
      if (url.contains(entry.key)) return http.Response(entry.value, 200);
    }
    if (url == winterPdfUrl) {
      return http.Response.bytes(utf8.encode('%PDF-1.7 winter fixture'), 200);
    }
    final body = switch (url) {
      'https://aeroportsuceava.ro/ro/2016-01-29-10-35-08' =>
        fixture('airport_page.html'),
      'https://www.tasasuceava.ro/trasee/' => fixture('tasa_routes.html'),
      'https://www.aeroportsuceava.ro/ro/info-pasageri/transfer-aeroport' =>
        fixture('airport_transfer.html'),
      'https://data.example.org/rail.xml' => fixture('rail_excerpt.xml'),
      _ => null,
    };
    return body == null
        ? http.Response('not found', 404)
        : http.Response.bytes(utf8.encode(body), 200);
  });
}

TransportPipeline build(FakeNetwork network) {
  final config = BackendConfig(
    contact: 'me@example.org',
    pdfExtractor: FixtureExtractor(),
    railDatasets: [
      RailDataset(
          url: railUrl,
          operatorName: 'CFR Călători',
          pageUrl: 'https://example.org/dataset'),
    ],
  );
  return TransportPipeline(
    adapters: config.buildAdapters(),
    fetcher: PoliteFetcher(
      userAgent: config.userAgent,
      client: network.client,
      now: () => fixedNow,
      sleep: (_) async {},
    ),
    now: () => fixedNow,
  );
}

void main() {
  final from = DateTime.utc(2026, 10, 21);
  final to = DateTime.utc(2026, 10, 22);

  test('all sources load and produce services for every transport type',
      () async {
    final pipeline = build(FakeNetwork());
    await pipeline.ensureFresh();
    final snapshot = pipeline.arrivals(from: from, to: to);

    expect({for (final s in snapshot.services) s.type},
        TransportKind.values.toSet());
    final bySource = {for (final s in snapshot.sources) s.id: s};
    for (final id in [
      AirportTimetableAdapter.sourceId,
      AirportTransferAdapter.sourceId,
      TasaAdapter.sourceId,
      RailTimetableAdapter.sourceId,
    ]) {
      expect(bySource[id]!.connection, SourceConnection.scheduledOnly,
          reason: id);
      expect(bySource[id]!.serviceCount, greaterThan(0), reason: id);
    }
    expect(bySource['tarsin']!.connection, SourceConnection.unavailable);
    expect(
        bySource['autogari-sosiri']!.connection, SourceConnection.unavailable);
    expect(bySource['aerodatabox']!.connection,
        SourceConnection.awaitingCredentials);
    expect(
        snapshot.sources.any((s) => s.connection == SourceConnection.connected),
        isFalse);
  });

  test(
      'only the permitted pages are requested, each once, plus robots.txt per host',
      () async {
    final network = FakeNetwork();
    final pipeline = build(network);
    await pipeline.ensureFresh();
    await pipeline.ensureFresh();
    final pages = [
      for (final u in network.requested)
        if (u.path != '/robots.txt') u.toString()
    ];
    expect(
        pages,
        unorderedEquals([
          'https://aeroportsuceava.ro/ro/2016-01-29-10-35-08',
          winterPdfUrl,
          'https://www.aeroportsuceava.ro/ro/info-pasageri/transfer-aeroport',
          'https://www.tasasuceava.ro/trasee/',
          'https://data.example.org/rail.xml',
        ]));
    expect(pages.any((p) => p.contains('autogari') || p.contains('tarsin')),
        isFalse);
    // Not the summer PDF (that season is already in the page), not the
    // departures PDFs, not a PDF on another host.
    expect(
        pages.any((p) => p.contains('VARA') || p.contains('PLECARI')), isFalse);
    expect(pages.any((p) => p.contains('other.example.org')), isFalse);
  });

  test('when one source fails the rest still serve data', () async {
    final pipeline = build(FakeNetwork(failing: {'tasasuceava'}));
    await pipeline.ensureFresh();
    final snapshot = pipeline.arrivals(from: from, to: to);
    final tasa =
        snapshot.sources.firstWhere((s) => s.id == TasaAdapter.sourceId);
    expect(tasa.connection, SourceConnection.unavailable);
    expect(snapshot.services.where((s) => s.sourceId == TasaAdapter.sourceId),
        isEmpty);
    expect(snapshot.services.where((s) => s.type == TransportKind.train),
        isNotEmpty);
    expect(snapshot.services.where((s) => s.type == TransportKind.flight),
        isNotEmpty);
  });

  test(
      'a changed airport page is dropped and flagged, other sources unaffected',
      () async {
    final pipeline = build(
      FakeNetwork(
        overrides: {
          'aeroportsuceava.ro/ro/2016': '<html><body>Pagina noua</body></html>',
        },
      ),
    );
    await pipeline.ensureFresh();
    final snapshot = pipeline.arrivals(from: from, to: to);
    final airport = snapshot.sources
        .firstWhere((s) => s.id == AirportTimetableAdapter.sourceId);
    expect(airport.connection, SourceConnection.unavailable);
    expect(airport.message, contains('nu a putut fi interpretat'));
    // The status says what the server actually received.
    expect(airport.message, contains('Primit: '));
    expect(airport.message, contains('HTTP 200'));
    expect(
      snapshot.services
          .where((s) => s.sourceId == AirportTimetableAdapter.sourceId),
      isEmpty,
    );
    expect(snapshot.services.where((s) => s.type == TransportKind.train),
        isNotEmpty);
  });

  group('seasons', () {
    TransportPipeline at(DateTime now, {FakeNetwork? network}) =>
        TransportPipeline(
          adapters: [
            AirportTimetableAdapter(pdfExtractor: FixtureExtractor()),
          ],
          fetcher: PoliteFetcher(
            userAgent: 'x',
            client: (network ?? FakeNetwork()).client,
            now: () => now,
            sleep: (_) async {},
          ),
          now: () => now,
        );

    test(
        'after the summer period ends the winter PDF keeps the source available',
        () async {
      final now = DateTime.utc(2026, 10, 30, 9);
      final pipeline = at(now);
      await pipeline.ensureFresh();
      final snapshot = pipeline.arrivals(
        from: DateTime.utc(2026, 10, 30),
        to: DateTime.utc(2026, 11, 6),
      );
      expect(
          snapshot.sources.single.connection, SourceConnection.scheduledOnly);
      expect(snapshot.sources.single.message,
          contains('25.10.2026-27.03.2027 (PDF)'));
      expect(snapshot.services, isNotEmpty);
      expect(
        snapshot.services.every((s) => s.dataQuality == DataQuality.scheduled),
        isTrue,
      );
    });

    test('the source is unavailable only when no published season covers today',
        () async {
      final pipeline = at(DateTime.utc(2027, 4, 2, 9));
      await pipeline.ensureFresh();
      final source = pipeline
          .arrivals(
            from: DateTime.utc(2027, 4, 2),
            to: DateTime.utc(2027, 4, 3),
          )
          .sources
          .single;
      expect(source.connection, SourceConnection.unavailable);
      expect(source.message, contains('Niciun orar publicat nu acoperă'));
    });
  });

  group('HTTP handler', () {
    late Handler handler;
    setUp(() async {
      final pipeline = build(FakeNetwork());
      handler = buildHandler(pipeline, now: () => fixedNow);
    });

    Future<(int, Map<String, dynamic>)> get(String path) async {
      final response =
          await handler(Request('GET', Uri.parse('http://localhost/$path')));
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, dynamic>
      );
    }

    test('/v1/arrivals returns the v1 contract', () async {
      final (status, body) = await get(
          'v1/arrivals?from=2026-10-21T00:00:00Z&to=2026-10-22T00:00:00Z');
      expect(status, 200);
      expect(body['schemaVersion'], 1);
      expect(body['services'], isNotEmpty);
      expect((body['sources'] as List).length, 7);
      for (final s in body['services'] as List) {
        expect(s['dataQuality'], 'scheduled');
        expect(s['estimatedArrival'], isNull);
        expect(s['lastUpdated'], isNotNull);
        expect((s['source'] as Map)['url'], startsWith('https://'));
      }
    });

    test('/v1/sources returns only status', () async {
      final (status, body) = await get('v1/sources');
      expect(status, 200);
      expect(body.keys, ['sources']);
    });

    test('defaults to a window from 30 minutes ago to 24 hours ahead',
        () async {
      final (_, body) = await get('v1/arrivals');
      final window = body['window'] as Map;
      expect(window['from'], '2026-10-21T08:30:00.000Z');
      expect(window['to'], '2026-10-22T09:00:00.000Z');
    });

    test('rejects bad windows with 400', () async {
      for (final bad in [
        'v1/arrivals?from=yesterday',
        'v1/arrivals?from=2026-10-21T10:00:00&to=2026-10-21T12:00:00', // no offset
        'v1/arrivals?from=2026-10-22T00:00:00Z&to=2026-10-21T00:00:00Z',
        'v1/arrivals?from=2026-10-01T00:00:00Z&to=2026-10-21T00:00:00Z', // over 72 h
      ]) {
        expect((await get(bad)).$1, 400, reason: bad);
      }
    });

    test('health, unknown paths and non-GET methods', () async {
      expect((await get('healthz')).$1, 200);
      expect((await get('nope')).$1, 404);
      final post = await handler(
          Request('POST', Uri.parse('http://localhost/v1/arrivals')));
      expect(post.statusCode, 405);
    });
  });

  test('golden: the served JSON matches the file the app tests parse',
      () async {
    final pipeline = build(FakeNetwork());
    await pipeline.ensureFresh();
    final json = const JsonEncoder.withIndent('  ')
        .convert(pipeline.arrivals(from: from, to: to).toJson());
    final golden = File('../test/fixtures/backend_output_v1.json');
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync('$json\n');
    }
    expect(golden.readAsStringSync().trim(), json.trim(),
        reason:
            'run with UPDATE_GOLDEN=1 to regenerate, then re-run the app tests');
  });
}
