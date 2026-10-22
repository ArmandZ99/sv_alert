import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travelalerts/core/config/app_config.dart';
import 'package:travelalerts/features/notifications/domain/notification_evaluator.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/data/mock_transport_repository.dart';
import 'package:travelalerts/features/transport/data/remote_transport_repository.dart';
import 'package:travelalerts/features/transport/data/sources/normalized_arrivals_parser.dart';
import 'package:travelalerts/features/transport/data/sources/provider_config.dart';
import 'package:travelalerts/features/transport/data/sources/source_status.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';
import 'package:travelalerts/features/transport/data/transport_repository_factory.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

/// Backend output produced by the backend's own end-to-end test from synthetic
/// fixtures (backend/test/end_to_end_test.dart). Parsing it here ties the two
/// halves of the contract together.
String goldenText() =>
    File('test/fixtures/backend_output_v1.json').readAsStringSync();

void main() {
  group('backend contract (golden file)', () {
    final parsed = NormalizedArrivalsParser.parse(jsonDecode(goldenText()));
    final snapshot = parsed.snapshot;

    test('every service the backend emits is accepted', () {
      expect(parsed.rejected, isEmpty);
      expect(snapshot.services, isNotEmpty);
      expect(
        snapshot.services.map((s) => s.type).toSet(),
        TransportType.values.toSet(),
      );
    });

    test(
      'all services are real, scheduled-only and carry source link and freshness',
      () {
        expect(snapshot.isMock, isFalse);
        for (final s in snapshot.services) {
          expect(s.source.isMock, isFalse, reason: s.id);
          expect(s.dataQuality, DataQuality.scheduled, reason: s.id);
          expect(s.isScheduleOnly, isTrue, reason: s.id);
          expect(s.source.url, startsWith('https://'), reason: s.id);
          expect(s.lastUpdated.isUtc, isTrue);
          expect(s.routeStops.length, greaterThanOrEqualTo(2));
          expect(s.arrivalPoint, isNotEmpty);
        }
      },
    );

    test('timetable services are never presented as on time or delayed', () {
      for (final s in snapshot.services) {
        expect(s.delayMinutes, isNull);
        expect(
          s.statusAt(snapshot.fetchedAt),
          anyOf(ArrivalStatus.scheduled, ArrivalStatus.unknown),
        );
      }
    });

    test(
      'the alert evaluator never raises a delay alert from timetable data',
      () {
        // Evaluate at the moment of the snapshot, with the freshness window
        // widened so only the scheduled-only rule can be what stops delay alerts.
        final result = NotificationEvaluator.evaluate(
          services: snapshot.services,
          preferences: const NotificationPreferences(),
          now: snapshot.fetchedAt,
          staleAfter: const Duration(days: 2),
        );
        expect(
          result.events.where((e) => e.kind == AlertKind.significantDelay),
          isEmpty,
        );
        for (final e in result.events) {
          expect(
            e.isScheduleBased,
            isTrue,
            reason: 'reminders must say they rest on the timetable',
          );
        }
      },
    );

    test('per-source status is parsed, including the unused sources', () {
      final byId = {for (final s in snapshot.sources) s.id: s};
      expect(
        byId['ro-rail-open-timetable']!.connection,
        SourceConnection.scheduledOnly,
      );
      expect(byId['tarsin']!.connection, SourceConnection.unavailable);
      expect(byId['autogari-sosiri']!.connection, SourceConnection.unavailable);
      expect(
        byId['aerodatabox']!.connection,
        SourceConnection.awaitingCredentials,
      );
      expect(
        snapshot.sources.any((s) => s.connection == SourceConnection.connected),
        isFalse,
      );
      expect(byId['tarsin']!.message, isNotEmpty);
    });

    test(
      'arrival points include all three Suceava stations and the airport',
      () {
        final points = snapshot.services.map((s) => s.arrivalPoint).toSet();
        expect(
          points,
          containsAll([
            'Gara Suceava',
            'Gara Suceava Nord',
            'Aeroportul Suceava (SCV)',
          ]),
        );
      },
    );
  });

  group('RemoteTransportRepository', () {
    MockClient client(
      http.Response Function(http.Request) handler, {
      List<http.Request>? log,
    }) => MockClient((request) async {
      log?.add(request);
      return handler(request);
    });

    RemoteTransportRepository build(
      MockClient c, {
      String base = 'https://api.example.ro',
      List<String>? logs,
    }) => RemoteTransportRepository(
      baseUrl: Uri.parse(base),
      client: c,
      now: () => DateTime.utc(2026, 10, 21, 9),
      timeout: const Duration(milliseconds: 100),
      retryDelay: Duration.zero,
      logger: logs?.add,
    );

    test('requests the arrivals window and parses the answer', () async {
      final log = <http.Request>[];
      final repo = build(
        client(
          (_) => http.Response.bytes(utf8.encode(goldenText()), 200),
          log: log,
        ),
      );
      final snapshot = await repo.fetchUpcomingArrivals();
      expect(snapshot.services, isNotEmpty);
      final url = log.single.url;
      expect(url.toString(), startsWith('https://api.example.ro/v1/arrivals?'));
      expect(url.queryParameters['from'], '2026-10-21T08:30:00.000Z');
      expect(url.queryParameters['to'], '2026-10-22T09:00:00.000Z');
      expect(log.single.headers['accept'], 'application/json');
    });

    test('keeps a path prefix on the base URL', () {
      expect(
        build(
          client((_) => http.Response('', 200)),
          base: 'https://example.ro/alerts/',
        ).arrivalsUrl.path,
        '/alerts/v1/arrivals',
      );
      expect(
        build(
          client((_) => http.Response('', 200)),
          base: 'https://example.ro',
        ).arrivalsUrl.path,
        '/v1/arrivals',
      );
    });

    test('an HTTP error becomes a safe message', () async {
      final repo = build(
        client((_) => http.Response('stack trace secret', 500)),
      );
      await expectLater(
        repo.fetchUpcomingArrivals(),
        throwsA(
          isA<TransportFetchException>().having(
            (e) => e.message,
            'message',
            allOf(contains('500'), isNot(contains('secret'))),
          ),
        ),
      );
    });

    test('unreadable JSON and unsupported versions are rejected', () async {
      await expectLater(
        build(
          client((_) => http.Response('<html>', 200)),
        ).fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
      await expectLater(
        build(
          client((_) => http.Response('{"schemaVersion":99}', 200)),
        ).fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
    });

    test('network failure and timeout are reported without detail', () async {
      await expectLater(
        build(
          MockClient(
            (_) async => throw http.ClientException('socket: 10.0.0.5'),
          ),
        ).fetchUpcomingArrivals(),
        throwsA(
          isA<TransportFetchException>().having(
            (e) => e.message,
            'message',
            isNot(contains('10.0.0.5')),
          ),
        ),
      );
      await expectLater(
        build(
          MockClient((_) async {
            await Completer<void>().future;
            return http.Response('', 200);
          }),
        ).fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
    });
  });

  group('retries and logging', () {
    RemoteTransportRepository build(
      MockClient c, {
      List<String>? logs,
      int maxAttempts = 3,
    }) => RemoteTransportRepository(
      baseUrl: Uri.parse('https://api.example.ro'),
      client: c,
      now: () => DateTime.utc(2026, 10, 21, 9),
      timeout: const Duration(milliseconds: 50),
      retryDelay: Duration.zero,
      maxAttempts: maxAttempts,
      logger: logs?.add,
    );

    test(
      'a 503 while the service wakes up is retried, then succeeds',
      () async {
        var calls = 0;
        final logs = <String>[];
        final repo = build(
          MockClient((_) async {
            calls++;
            return calls < 3
                ? http.Response('starting', 503)
                : http.Response.bytes(utf8.encode(goldenText()), 200);
          }),
          logs: logs,
        );
        final snapshot = await repo.fetchUpcomingArrivals();
        expect(calls, 3);
        expect(snapshot.services, isNotEmpty);
        expect(logs.where((l) => l.contains('HTTP 503')), hasLength(2));
      },
    );

    test('a timeout is retried a bounded number of times', () async {
      var calls = 0;
      final repo = build(
        MockClient((_) async {
          calls++;
          await Completer<void>().future;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        repo.fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
      expect(calls, 3);
    });

    test('a connection error is retried', () async {
      var calls = 0;
      final repo = build(
        MockClient((_) async {
          calls++;
          throw http.ClientException('refused');
        }),
        maxAttempts: 2,
      );
      await expectLater(
        repo.fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
      expect(calls, 2);
    });

    test('errors that asking again cannot fix are not retried', () async {
      for (final response in [
        http.Response('nope', 404),
        http.Response('boom', 500),
        http.Response('<html>', 200),
        http.Response('{"schemaVersion":99}', 200),
        http.Response('[]', 200),
      ]) {
        var calls = 0;
        final logs = <String>[];
        final repo = build(
          MockClient((_) async {
            calls++;
            return response;
          }),
          logs: logs,
        );
        await expectLater(
          repo.fetchUpcomingArrivals(),
          throwsA(isA<TransportFetchException>()),
        );
        expect(calls, 1, reason: '${response.statusCode} ${response.body}');
        expect(logs, isNotEmpty);
      }
    });

    test('logs name the failure without leaking the response body', () async {
      final logs = <String>[];
      final repo = build(
        MockClient((_) async => http.Response('secret-token', 200)),
        logs: logs,
      );
      await expectLater(
        repo.fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
      expect(logs.any((l) => l.contains('invalid JSON')), isTrue);
      expect(logs.join(), isNot(contains('secret-token')));
    });
  });

  group('deployed backend response (Render, 2026-10-22)', () {
    // Captured from the live service: all sources reported "unavailable" there,
    // so there are no services. The app must still accept it as real data.
    final parsed = NormalizedArrivalsParser.parse(
      jsonDecode(
        File('test/fixtures/deployed_render_v1.json').readAsStringSync(),
      ),
    );

    test('is accepted by the parser and is not demo data', () {
      expect(parsed.rejected, isEmpty);
      expect(parsed.snapshot.isMock, isFalse);
      expect(parsed.snapshot.services, isEmpty);
      expect(parsed.snapshot.sources, hasLength(7));
    });

    test('keeps each source status and message from the server', () {
      final byId = {for (final s in parsed.snapshot.sources) s.id: s};
      expect(
        byId['ro-rail-open-timetable']!.connection,
        SourceConnection.unavailable,
      );
      expect(byId['ro-rail-open-timetable']!.message, contains('robots.txt'));
      expect(
        byId['aerodatabox']!.connection,
        SourceConnection.awaitingCredentials,
      );
    });
  });

  group('request window and diagnostics', () {
    RemoteTransportRepository build(
      MockClient c,
      List<String> logs, {
      Duration lookBehind = const Duration(minutes: 30),
      Duration lookAhead = const Duration(hours: 24),
    }) => RemoteTransportRepository(
      baseUrl: Uri.parse('https://api.example.ro'),
      client: c,
      now: () => DateTime.utc(2026, 10, 22, 14, 42, 23),
      lookBehind: lookBehind,
      lookAhead: lookAhead,
      logger: logs.add,
    );

    Map<String, Object?> golden() =>
        (jsonDecode(goldenText()) as Map).cast<String, Object?>();

    MockClient answering(Object body) => MockClient(
      (_) async => http.Response.bytes(utf8.encode(jsonEncode(body)), 200),
    );

    test('from and to are current UTC instants with an explicit offset', () {
      final url = build(answering(golden()), []).arrivalsUrl;
      final from = url.queryParameters['from']!;
      final to = url.queryParameters['to']!;
      expect(from, '2026-10-22T14:12:23.000Z');
      expect(to, '2026-10-23T14:42:23.000Z');
      for (final value in [from, to]) {
        expect(value, endsWith('Z'));
        expect(DateTime.parse(value).isUtc, isTrue);
      }
      expect(
        DateTime.parse(to).difference(DateTime.parse(from)),
        const Duration(hours: 24, minutes: 30),
      );
    });

    test('the window can be 6 h back and 48 h ahead', () {
      final url = build(
        answering(golden()),
        [],
        lookBehind: const Duration(hours: 6),
        lookAhead: const Duration(hours: 48),
      ).arrivalsUrl;
      expect(url.queryParameters['from'], '2026-10-22T08:42:23.000Z');
      expect(url.queryParameters['to'], '2026-10-24T14:42:23.000Z');
    });

    test('the query is encoded and round-trips, with no bare plus sign', () {
      final url = build(answering(golden()), []).arrivalsUrl;
      expect(url.query, contains('from=2026-10-22T14%3A12%3A23.000Z'));
      expect(url.query, isNot(contains('+')));
      expect(Uri.parse(url.toString()).queryParameters, url.queryParameters);
      // An offset such as +02:00 would be encoded, never sent as a space.
      expect(
        Uri(queryParameters: {'from': '2026-10-22T16:12:23+02:00'}).query,
        'from=2026-10-22T16%3A12%3A23%2B02%3A00',
      );
    });

    test(
      'the request carries both parameters and logs them with the zone',
      () async {
        final logs = <String>[];
        final seen = <Uri>[];
        final repo = build(
          MockClient((request) async {
            seen.add(request.url);
            return http.Response.bytes(utf8.encode(goldenText()), 200);
          }),
          logs,
        );
        await repo.fetchUpcomingArrivals();
        expect(seen.single.queryParameters.keys, containsAll(['from', 'to']));
        final get = logs.firstWhere((l) => l.contains('GET '));
        expect(get, contains('from=2026-10-22T14:12:23.000Z'));
        expect(get, contains('to=2026-10-23T14:42:23.000Z'));
        expect(get, contains('UTC'));
        expect(logs.any((l) => l.startsWith('[api] HTTP 200')), isTrue);
      },
    );

    test('a non-empty response logs raw and parsed counts', () async {
      final logs = <String>[];
      final snapshot = await build(
        answering(golden()),
        logs,
      ).fetchUpcomingArrivals();
      final n = snapshot.services.length;
      expect(n, greaterThan(0));
      expect(logs, contains('[api] records: $n raw, $n parsed, 0 rejected'));
      expect(logs, contains('[api] ok: $n services'));
    });

    test('records the parser rejects are counted and named', () async {
      final body = golden();
      body['services'] = [
        ...(body['services'] as List),
        {'id': 'broken'},
      ];
      final logs = <String>[];
      final snapshot = await build(
        answering(body),
        logs,
      ).fetchUpcomingArrivals();
      final parsed = snapshot.services.length;
      expect(
        logs,
        contains(
          '[api] records: ${parsed + 1} raw, $parsed parsed, 1 rejected',
        ),
      );
      expect(logs.any((l) => l.startsWith('[api] rejected services[')), isTrue);
    });

    test('zero arrivals because every source failed is told apart', () async {
      final body = golden();
      body['services'] = <Object>[];
      body['sources'] = [
        for (final s in (body['sources'] as List))
          {
            ...(s as Map).cast<String, Object?>(),
            'status': 'unavailable',
            'message': 'Conținutul sursei nu a putut fi interpretat.',
            'serviceCount': 0,
          },
      ];
      final logs = <String>[];
      final snapshot = await build(
        answering(body),
        logs,
      ).fetchUpcomingArrivals();
      expect(snapshot.services, isEmpty);
      expect(snapshot.isMock, isFalse);
      expect(logs, contains('[api] records: 0 raw, 0 parsed, 0 rejected'));
      expect(logs.where((l) => l.startsWith('[api] source ')), isNotEmpty);
      expect(
        logs.any((l) => l.contains('ok but empty: the server has no usable')),
        isTrue,
      );
    });

    test(
      'zero arrivals with working sources is a plain empty window',
      () async {
        final body = golden();
        body['services'] = <Object>[];
        final logs = <String>[];
        await build(answering(body), logs).fetchUpcomingArrivals();
        expect(
          logs.any((l) => l.contains('sources are working, no arrivals')),
          isTrue,
        );
        expect(logs.any((l) => l.contains('no usable source')), isFalse);
      },
    );

    test('an incompatible response is logged as such, not as empty', () async {
      final logs = <String>[];
      await expectLater(
        build(answering({'schemaVersion': 2}), logs).fetchUpcomingArrivals(),
        throwsA(isA<TransportFetchException>()),
      );
      expect(logs.any((l) => l.contains('incompatible response')), isTrue);
      expect(logs.any((l) => l.contains('ok')), isFalse);
    });
  });

  group('AppConfig', () {
    test('a normal run uses the central default URL', () {
      expect(AppConfig.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(
        AppConfig.defaultApiBaseUrl,
        'https://suceava-travel-alerts-api.onrender.com',
      );
      expect(ProviderConfig.environmentKey, 'TRAVEL_ALERTS_API_BASE_URL');
      final config = ProviderConfig.fromEnvironment();
      expect(config.isValid, isTrue);
      expect(config.config.apiBaseUrl, Uri.parse(AppConfig.defaultApiBaseUrl));
    });

    test('an override is accepted; empty turns the backend off', () {
      expect(
        ProviderConfig.validate('http://127.0.0.1:8080').config.apiBaseUrl,
        Uri.parse('http://127.0.0.1:8080'),
      );
      final off = ProviderConfig.validate('');
      expect(off.isValid, isTrue);
      expect(off.config.hasBackend, isFalse);
    });

    test('requests use the central URL and no other host', () async {
      final seen = <Uri>[];
      final repo = createTransportRepository(
        ProviderConfig.fromEnvironment().config,
        client: MockClient((request) async {
          seen.add(request.url);
          return http.Response.bytes(utf8.encode(goldenText()), 200);
        }),
      );
      await repo.fetchUpcomingArrivals();
      expect(seen.single.origin, AppConfig.defaultApiBaseUrl);
      expect(seen.single.path, '/v1/arrivals');
    });
  });

  group('createTransportRepository', () {
    test('without a backend URL it is demo data only', () {
      expect(
        createTransportRepository(const ProviderConfig()),
        isA<MockTransportRepository>(),
      );
    });

    test('with a valid backend URL it uses the backend alone, no demo', () {
      expect(
        createTransportRepository(
          ProviderConfig.validate('https://api.example.ro').config,
        ),
        isA<RemoteTransportRepository>(),
      );
    });

    test('an invalid URL is not used at all', () {
      final config = ProviderConfig.validate(
        'https://api.example.ro?key=SECRET',
      ).config;
      expect(createTransportRepository(config), isA<MockTransportRepository>());
    });
  });
}
