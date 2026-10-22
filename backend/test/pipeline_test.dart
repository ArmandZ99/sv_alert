import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 21, 9);

/// Adapter driven by a script: each load consumes one outcome (an
/// [AdapterLoad] or an exception to throw).
class FakeAdapter extends SourceAdapter {
  FakeAdapter(String id, TransportKind kind, this.script)
      : descriptor = SourceDescriptor(
          id: id,
          name: 'Fake $id',
          kind: kind,
          url: 'https://example.org/$id',
        );

  @override
  final SourceDescriptor descriptor;
  final List<Object> script;
  int loads = 0;

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async {
    final next = script[loads < script.length ? loads : script.length - 1];
    loads++;
    if (next is AdapterLoad) return next;
    throw next;
  }
}

AdapterLoad goodLoad({
  String number = 'T 1',
  int minutes = 12 * 60, // 12:00 Bucharest
  DateTime? fetchedAt,
  SourceConnection connection = SourceConnection.scheduledOnly,
  String message = 'timetable',
}) =>
    AdapterLoad(
      connection: connection,
      message: message,
      fetchedAt: fetchedAt ?? t0,
      patterns: [
        SchedulePattern(
          serviceNumber: number,
          routeStops: const ['A', 'Suceava'],
          arrivalPoint: 'Gara Suceava',
          arrivalMinutes: minutes,
          calendar: [everyDay()],
        ),
      ],
    );

class Env {
  Env(this.adapters, {Duration refreshEvery = const Duration(hours: 6)}) {
    fetcher = PoliteFetcher(
      userAgent: 'test',
      client: MockClient((_) async => http.Response('', 500)),
    );
    pipeline = TransportPipeline(
      adapters: adapters,
      fetcher: fetcher,
      now: () => clock,
      refreshEvery: refreshEvery,
    );
  }

  DateTime clock = t0;
  final List<SourceAdapter> adapters;
  late final PoliteFetcher fetcher;
  late final TransportPipeline pipeline;

  PipelineSnapshot snapshot() => pipeline.arrivals(
        from: DateTime.utc(2026, 10, 21),
        to: DateTime.utc(2026, 10, 22),
      );

  SourceStatus status(String id) =>
      snapshot().sources.firstWhere((s) => s.id == id);
}

void main() {
  test('services from several sources are merged and sorted by arrival',
      () async {
    final env = Env([
      FakeAdapter('a', TransportKind.train,
          [goodLoad(number: 'T late', minutes: 18 * 60)]),
      FakeAdapter('b', TransportKind.coach,
          [goodLoad(number: 'C early', minutes: 8 * 60)]),
    ]);
    await env.pipeline.ensureFresh();
    expect(env.snapshot().services.map((s) => s.serviceNumber),
        ['C early', 'T late']);
    expect(env.snapshot().services.map((s) => s.type),
        [TransportKind.coach, TransportKind.train]);
  });

  test('one failing source does not affect the others', () async {
    final env = Env([
      FakeAdapter('ok', TransportKind.train, [goodLoad()]),
      FakeAdapter('down', TransportKind.flight,
          [const FetchException('Sursa nu a răspuns la timp.')]),
    ]);
    await env.pipeline.ensureFresh();
    expect(env.snapshot().services, hasLength(1));
    expect(env.status('ok').connection, SourceConnection.scheduledOnly);
    final down = env.status('down');
    expect(down.connection, SourceConnection.unavailable);
    expect(down.message, contains('nu a răspuns'));
  });

  test('a blocked source is reported unavailable and retried only much later',
      () async {
    final blocked = FakeAdapter('blocked', TransportKind.coach, [
      const FetchException('Sursa refuză accesul automat.', blocked: true),
      goodLoad(),
    ]);
    final env = Env([blocked]);
    await env.pipeline.ensureFresh();
    expect(env.status('blocked').connection, SourceConnection.unavailable);

    env.clock = t0.add(const Duration(hours: 2));
    await env.pipeline.ensureFresh();
    expect(blocked.loads, 1, reason: 'not retried within the block back-off');

    env.clock = t0.add(const Duration(hours: 7));
    await env.pipeline.ensureFresh();
    expect(blocked.loads, 2);
    expect(env.status('blocked').connection, SourceConnection.scheduledOnly);
  });

  test('an ordinary failure is retried after the shorter delay', () async {
    final flaky = FakeAdapter('flaky', TransportKind.train, [
      const FetchException('HTTP 500'),
      goodLoad(),
    ]);
    final env = Env([flaky]);
    await env.pipeline.ensureFresh();
    env.clock = t0.add(const Duration(minutes: 10));
    await env.pipeline.ensureFresh();
    expect(flaky.loads, 1);
    env.clock = t0.add(const Duration(minutes: 31));
    await env.pipeline.ensureFresh();
    expect(flaky.loads, 2);
    expect(env.snapshot().services, isNotEmpty);
  });

  test('sources are not reloaded before the refresh interval', () async {
    final a = FakeAdapter('a', TransportKind.train, [goodLoad()]);
    final env = Env([a]);
    await env.pipeline.ensureFresh();
    env.clock = t0.add(const Duration(hours: 5));
    await env.pipeline.ensureFresh();
    expect(a.loads, 1);
    env.clock = t0.add(const Duration(hours: 6, minutes: 1));
    await env.pipeline.ensureFresh();
    expect(a.loads, 2);
  });

  test(
      'after an earlier success, a failed refresh keeps the old timetable and says so',
      () async {
    final a = FakeAdapter('a', TransportKind.train, [
      goodLoad(),
      const FetchException('Nu s-a putut contacta sursa.'),
    ]);
    final env = Env([a]);
    await env.pipeline.ensureFresh();
    env.clock = t0.add(const Duration(hours: 7));
    await env.pipeline.ensureFresh();

    expect(env.snapshot().services, hasLength(1),
        reason: 'last good timetable still served');
    final s = env.status('a');
    expect(s.connection, SourceConnection.scheduledOnly);
    expect(s.message, contains('Ultima reîmprospătare a eșuat'));
    expect(s.message, contains('Nu s-a putut contacta sursa.'));
  });

  test(
      'a page whose structure changed is not trusted, even if an older parse exists',
      () async {
    final a = FakeAdapter('a', TransportKind.flight, [
      goodLoad(),
      const FormatException('Tabelele de sosiri nu au fost găsite.'),
    ]);
    final env = Env([a]);
    await env.pipeline.ensureFresh();
    expect(env.snapshot().services, hasLength(1));

    env.clock = t0.add(const Duration(hours: 7));
    await env.pipeline.ensureFresh();
    expect(env.snapshot().services, isEmpty);
    expect(env.status('a').connection, SourceConnection.unavailable);
    expect(env.status('a').message, contains('Structura sursei s-a schimbat'));
  });

  test(
      'an unexpected exception is reported generically, without leaking its text',
      () async {
    final env = Env([
      FakeAdapter('a', TransportKind.train, [StateError('api key sk-SECRET')])
    ]);
    await env.pipeline.ensureFresh();
    expect(env.status('a').message, isNot(contains('SECRET')));
    expect(env.status('a').connection, SourceConnection.unavailable);
  });

  test('an expired timetable reports unavailable and produces nothing',
      () async {
    final env = Env([
      FakeAdapter('a', TransportKind.flight, [
        const AdapterLoad(
          connection: SourceConnection.unavailable,
          message: 'Orarul publicat a expirat.',
        ),
      ]),
    ]);
    await env.pipeline.ensureFresh();
    expect(env.snapshot().services, isEmpty);
    expect(env.status('a').connection, SourceConnection.unavailable);
  });

  test('before the first load a source is reported as not yet loaded', () {
    final env = Env([
      FakeAdapter('a', TransportKind.train, [goodLoad()])
    ]);
    expect(env.status('a').connection, SourceConnection.unavailable);
    expect(env.status('a').message, contains('nu a fost încă încărcată'));
  });

  test('concurrent refreshes share one run', () async {
    final a = FakeAdapter('a', TransportKind.train, [goodLoad()]);
    final env = Env([a]);
    await Future.wait([env.pipeline.ensureFresh(), env.pipeline.ensureFresh()]);
    expect(a.loads, 1);
  });

  test('data freshness is the age of the oldest source used', () async {
    final env = Env([
      FakeAdapter('a', TransportKind.train,
          [goodLoad(fetchedAt: DateTime.utc(2026, 10, 21, 8))]),
      FakeAdapter('b', TransportKind.coach,
          [goodLoad(number: 'C', fetchedAt: DateTime.utc(2026, 10, 21, 6))]),
    ]);
    await env.pipeline.ensureFresh();
    expect(env.snapshot().dataFetchedAt, DateTime.utc(2026, 10, 21, 6));
    final services = env.snapshot().services;
    expect(services.map((s) => s.lastUpdated).toSet(), {
      DateTime.utc(2026, 10, 21, 8),
      DateTime.utc(2026, 10, 21, 6),
    });
  });

  test('every service records its source, link and a scheduled classification',
      () async {
    final env = Env([
      FakeAdapter('a', TransportKind.train, [goodLoad()])
    ]);
    await env.pipeline.ensureFresh();
    for (final s in env.snapshot().services) {
      expect(s.sourceName, isNotEmpty);
      expect(s.sourceUrl, startsWith('https://'));
      expect(s.dataQuality, DataQuality.scheduled);
    }
  });

  group('default adapter set', () {
    final config = BackendConfig(contact: 'me@example.org');
    final adapters = config.buildAdapters();

    test('covers flights, trains and coaches', () {
      final kinds = {for (final a in adapters) ...a.kinds};
      expect(kinds, TransportKind.values.toSet());
    });

    test('unused sources report why and make no request', () async {
      final env = Env(adapters);
      // The unused adapters never touch the network (the fetcher would answer 500).
      for (final id in ['tarsin', 'autogari-sosiri', 'aerodatabox']) {
        final a = adapters.firstWhere((a) => a.descriptor.id == id);
        final load = await a.load(env.fetcher, t0);
        expect(load.patterns, isEmpty);
        expect(load.message, isNotEmpty);
      }
      final aero = await adapters
          .firstWhere((a) => a.descriptor.id == 'aerodatabox')
          .load(env.fetcher, t0);
      expect(aero.connection, SourceConnection.awaitingCredentials);
      final autogari = await adapters
          .firstWhere((a) => a.descriptor.id == 'autogari-sosiri')
          .load(env.fetcher, t0);
      expect(autogari.message, contains('§8.1'));
      final tarsin = await adapters
          .firstWhere((a) => a.descriptor.id == 'tarsin')
          .load(env.fetcher, t0);
      expect(tarsin.connection, SourceConnection.unavailable);
    });

    test(
        'a configured AeroDataBox key is never exposed and does not enable live data',
        () async {
      final keyed = BackendConfig(
          contact: 'me@example.org', aeroDataBoxKey: 'sk-SECRET-123');
      final env = Env(keyed.buildAdapters());
      await env.pipeline.ensureFresh();
      final all = jsonEncode(env.snapshot().toJson());
      expect(all, isNot(contains('SECRET')));
      final aero =
          env.snapshot().sources.firstWhere((s) => s.id == 'aerodatabox');
      expect(aero.connection, isNot(SourceConnection.connected));
    });

    test('no scheduled source is ever labelled connected (live)', () async {
      // The unused adapters are the only ones that can run without network.
      final env =
          Env(<SourceAdapter>[...adapters.whereType<UnusedSourceAdapter>()]);
      await env.pipeline.ensureFresh();
      expect(
          env
              .snapshot()
              .sources
              .any((s) => s.connection == SourceConnection.connected),
          isFalse);
    });
  });

  group('BackendConfig', () {
    test('requires a contact for the User-Agent', () {
      expect(() => BackendConfig.fromEnvironment({}), throwsArgumentError);
      expect(
          () => BackendConfig.fromEnvironment({'TRAVEL_ALERTS_CONTACT': '  '}),
          throwsArgumentError);
    });

    test('reads port and key from the environment', () {
      final c = BackendConfig.fromEnvironment({
        'TRAVEL_ALERTS_CONTACT': 'me@example.org',
        'PORT': '9090',
        'AERODATABOX_API_KEY': ' abc ',
      });
      expect(c.port, 9090);
      expect(c.aeroDataBoxKey, 'abc');
      expect(c.userAgent, 'SuceavaTravelAlerts/0.1 (+me@example.org)');
    });

    test('listens on loopback unless told otherwise', () {
      expect(BackendConfig.fromEnvironment({'TRAVEL_ALERTS_CONTACT': 'x'}).host,
          '127.0.0.1');
      expect(
          BackendConfig.fromEnvironment(
              {'TRAVEL_ALERTS_CONTACT': 'x', 'HOST': '0.0.0.0'}).host,
          '0.0.0.0');
    });

    test('rail dataset URLs can be overridden for the yearly update', () {
      final c = BackendConfig.fromEnvironment({
        'TRAVEL_ALERTS_CONTACT': 'x',
        'RAIL_SNTFC_URL': 'https://data.gov.ro/new-sntfc.xml',
      });
      expect(c.railDatasets.first.url.toString(),
          'https://data.gov.ro/new-sntfc.xml');
      expect(c.railDatasets.last.url.toString(), contains('interregional'),
          reason: 'other file unchanged');
    });

    test('an absent or blank key means no key', () {
      expect(
          BackendConfig.fromEnvironment({'TRAVEL_ALERTS_CONTACT': 'x'})
              .aeroDataBoxKey,
          isNull);
      expect(
        BackendConfig.fromEnvironment(
                {'TRAVEL_ALERTS_CONTACT': 'x', 'AERODATABOX_API_KEY': ' '})
            .aeroDataBoxKey,
        isNull,
      );
    });
  });
}
