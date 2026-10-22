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

import '../support.dart';

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

  group('AppConfig', () {
    test('a normal run uses the central default URL', () {
      expect(AppConfig.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(
        AppConfig.defaultApiBaseUrl,
        startsWith('https://REPLACE_AFTER_RENDER_DEPLOY'),
      );
      expect(ProviderConfig.environmentKey, 'TRAVEL_ALERTS_API_BASE_URL');
    });

    test('the unreplaced placeholder is not used as a backend', () {
      final result = ProviderConfig.validate(AppConfig.defaultApiBaseUrl);
      expect(result.config.hasBackend, isFalse);
      expect(result.errors.single, contains('app_config.dart'));
      expect(
        createTransportRepository(result.config),
        isA<MockTransportRepository>(),
      );
    });

    test(
      'a real hosted URL or an override is accepted; empty turns it off',
      () {
        expect(
          ProviderConfig.validate(
            'https://suceava-travel-alerts-api.onrender.com',
          ).config.hasBackend,
          isTrue,
        );
        expect(
          ProviderConfig.validate('http://127.0.0.1:8080').config.hasBackend,
          isTrue,
        );
        final off = ProviderConfig.validate('');
        expect(off.isValid, isTrue);
        expect(off.config.hasBackend, isFalse);
      },
    );
  });

  group('FallbackTransportRepository', () {
    final demo = MockTransportRepository(
      clock: () => testNow,
      latency: Duration.zero,
    );

    test(
      'returns the real data when the backend works, with no demo mixed in',
      () async {
        final repo = FallbackTransportRepository(
          primary: RemoteTransportRepository(
            baseUrl: Uri.parse('https://api.example.ro'),
            client: MockClient(
              (_) async => http.Response.bytes(utf8.encode(goldenText()), 200),
            ),
          ),
          fallback: demo,
        );
        final snapshot = await repo.fetchUpcomingArrivals();
        expect(snapshot.isMock, isFalse);
        expect(snapshot.degradedReason, isNull);
        expect(snapshot.services.any((s) => s.source.isMock), isFalse);
      },
    );

    test(
      'falls back to labelled demo data, and says why, when the backend fails',
      () async {
        final repo = FallbackTransportRepository(
          primary: RemoteTransportRepository(
            baseUrl: Uri.parse('https://api.example.ro'),
            client: MockClient((_) async => http.Response('down', 503)),
            retryDelay: Duration.zero,
          ),
          fallback: demo,
        );
        final snapshot = await repo.fetchUpcomingArrivals();
        expect(snapshot.isMock, isTrue);
        expect(snapshot.degradedReason, FallbackTransportRepository.reason);
        expect(snapshot.services.every((s) => s.source.isMock), isTrue);
      },
    );
  });

  group('createTransportRepository', () {
    test('without a backend URL it is demo data only', () {
      expect(
        createTransportRepository(const ProviderConfig()),
        isA<MockTransportRepository>(),
      );
    });

    test('with a valid backend URL it uses the backend with demo fallback', () {
      final repo = createTransportRepository(
        ProviderConfig.validate('https://api.example.ro').config,
      );
      expect(repo, isA<FallbackTransportRepository>());
      expect(
        (repo as FallbackTransportRepository).primary,
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
