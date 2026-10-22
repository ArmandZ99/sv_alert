import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travelalerts/app/app.dart';
import 'package:travelalerts/core/l10n/strings.dart';
import 'package:travelalerts/features/arrivals/presentation/arrivals_controller.dart';
import 'package:travelalerts/features/transport/data/remote_transport_repository.dart';
import 'package:travelalerts/features/transport/data/sources/source_status.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';

import '../support.dart';

/// A repository whose answer the test controls, to model a slow server.
class PendingRepository implements TransportRepository {
  final List<Completer<TransportSnapshot>> requests = [];

  @override
  Future<TransportSnapshot> fetchUpcomingArrivals() {
    final c = Completer<TransportSnapshot>();
    requests.add(c);
    return c.future;
  }
}

TransportSnapshot realSnapshot() => TransportSnapshot(
  services: [
    makeService(
      id: 'r1',
      number: 'IR 1655',
      scheduled: 40,
      quality: DataQuality.scheduled,
      sourceName: 'Orar tren - date deschise (data.gov.ro)',
    ),
  ],
  fetchedAt: testNow,
  isMock: false,
);

Future<void> pumpApp(WidgetTester tester, TransportRepository repo) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SuceavaPulseApp(repository: repo, clock: () => testNow),
  );
  await tester.pump();
}

/// A real [RemoteTransportRepository] over a fake network, with no real waiting.
RemoteTransportRepository remote(
  MockClient client, {
  Duration timeout = const Duration(seconds: 5),
}) => RemoteTransportRepository(
  baseUrl: Uri.parse('https://api.example.ro'),
  client: client,
  now: () => testNow,
  timeout: const Duration(seconds: 5),
  retryDelay: const Duration(seconds: 1),
  logger: (_) {},
);

final loading = find.text(Strings.loading);
final slowText = find.text(Strings.loadingSlow);

void main() {
  group('cold start loading state', () {
    testWidgets('a pending request shows the loading message only', (
      tester,
    ) async {
      final repo = PendingRepository();
      await pumpApp(tester, repo);
      expect(loading, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(slowText, findsNothing);
      expect(repo.requests, hasLength(1));
    });

    testWidgets(
      'after about 9 s the screen explains a possible server wake-up',
      (tester) async {
        final repo = PendingRepository();
        await pumpApp(tester, repo);

        await tester.pump(const Duration(seconds: 8));
        expect(slowText, findsNothing);

        await tester.pump(const Duration(seconds: 2));
        expect(slowText, findsOneWidget);
        expect(loading, findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(Strings.loadingSlowNote), findsOneWidget);
        // Possible cause, not a diagnosis; no progress figure or countdown.
        expect(Strings.loadingSlow, contains('poate fi'));
        expect(find.textContaining('%'), findsNothing);
        expect(repo.requests, hasLength(1), reason: 'no extra request');
      },
    );

    testWidgets(
      'a success after the delay removes the messages and shows data',
      (tester) async {
        final repo = PendingRepository();
        await pumpApp(tester, repo);
        await tester.pump(const Duration(seconds: 20));
        expect(slowText, findsOneWidget);

        repo.requests.single.complete(realSnapshot());
        await tester.pumpAndSettle();

        expect(loading, findsNothing);
        expect(slowText, findsNothing);
        expect(find.text(Strings.loadingSlowNote), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Orar programat, nu timp real'), findsOneWidget);
        expect(find.text('Date demonstrative (mock)'), findsNothing);
      },
    );

    testWidgets('a fast success never shows the slow message', (tester) async {
      final repo = PendingRepository();
      await pumpApp(tester, repo);
      await tester.pump(const Duration(seconds: 2));
      repo.requests.single.complete(realSnapshot());
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(slowText, findsNothing);
      expect(loading, findsNothing);
    });
  });

  group('failures', () {
    testWidgets(
      'HTTP errors end in a Romanian error with Retry, never demo data',
      (tester) async {
        var calls = 0;
        await pumpApp(
          tester,
          remote(
            MockClient((_) async {
              calls++;
              return http.Response('boom', 500);
            }),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 1, reason: '500 is not retried');
        expect(find.text(Strings.errorTitle), findsOneWidget);
        expect(find.textContaining('500'), findsOneWidget);
        expect(find.text(Strings.retry), findsOneWidget);
        expect(loading, findsNothing);
        expect(find.text('Date demonstrative (mock)'), findsNothing);
        expect(find.text('DATE DEMO'), findsNothing);
      },
    );

    testWidgets('a 503 is retried a bounded number of times, then errors', (
      tester,
    ) async {
      var calls = 0;
      await pumpApp(
        tester,
        remote(
          MockClient((_) async {
            calls++;
            return http.Response('starting', 503);
          }),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(calls, 2);
      expect(find.text(Strings.errorTitle), findsOneWidget);
      expect(find.text(Strings.retry), findsOneWidget);
    });

    testWidgets('timeouts are retried, then reach the error state', (
      tester,
    ) async {
      var calls = 0;
      await pumpApp(
        tester,
        remote(
          MockClient((_) {
            calls++;
            return Completer<http.Response>().future;
          }),
          timeout: const Duration(seconds: 12),
        ),
      );
      // The slow message appears while the attempts are pending.
      await tester.pump(const Duration(seconds: 10));
      expect(slowText, findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(calls, 2);
      expect(slowText, findsNothing);
      expect(find.text(Strings.errorTitle), findsOneWidget);
      expect(find.textContaining('nu a răspuns la timp'), findsOneWidget);
    });

    testWidgets('invalid JSON and HTML pages do not crash the UI', (
      tester,
    ) async {
      for (final body in ['<html>Render is starting</html>', '{"x":', '[]']) {
        await pumpApp(
          tester,
          remote(MockClient((_) async => http.Response(body, 200))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: body);
        expect(find.text(Strings.errorTitle), findsOneWidget, reason: body);
        expect(find.text(Strings.retry), findsOneWidget, reason: body);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Retry sends one new request and then shows the data', (
      tester,
    ) async {
      var calls = 0;
      await pumpApp(
        tester,
        remote(
          MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response('boom', 500)
                : http.Response.bytes(utf8.encode(_golden), 200);
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(Strings.retry), findsOneWidget);

      await tester.tap(find.text(Strings.retry));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(Strings.errorTitle), findsNothing);
      expect(find.text('Date demonstrative (mock)'), findsNothing);
      expect(find.text('Orar programat, nu timp real'), findsOneWidget);
    });
  });

  group('empty answers', () {
    TransportSnapshot empty(SourceConnection connection) => TransportSnapshot(
      services: const [],
      fetchedAt: testNow,
      isMock: false,
      sources: [
        SourceStatusInfo(
          id: 'a',
          name: 'A',
          connection: connection,
          message: 'm',
        ),
      ],
    );

    testWidgets('no usable source says there is no data, not no arrivals', (
      tester,
    ) async {
      final repo = PendingRepository();
      await pumpApp(tester, repo);
      repo.requests.single.complete(empty(SourceConnection.unavailable));
      await tester.pumpAndSettle();
      expect(find.text(Strings.noSourcesTitle), findsOneWidget);
      expect(find.text(Strings.emptyTitle), findsNothing);
      expect(find.text('DATE DEMO'), findsNothing);
      expect(find.text('Date demonstrative (mock)'), findsNothing);
    });

    testWidgets('working sources with nothing in the window is a plain empty', (
      tester,
    ) async {
      final repo = PendingRepository();
      await pumpApp(tester, repo);
      repo.requests.single.complete(empty(SourceConnection.scheduledOnly));
      await tester.pumpAndSettle();
      expect(find.text(Strings.emptyTitle), findsOneWidget);
      expect(find.text(Strings.noSourcesTitle), findsNothing);
    });
  });

  group('request lifecycle', () {
    test('overlapping refreshes share one request', () async {
      final repo = PendingRepository();
      final controller = ArrivalsController(
        repository: repo,
        clock: () => testNow,
      );
      final first = controller.refresh();
      final second = controller.refresh();
      final third = controller.refresh();
      expect(repo.requests, hasLength(1));

      repo.requests.single.complete(realSnapshot());
      await Future.wait([first, second, third]);
      expect(controller.status, LoadStatus.ready);
      expect(controller.isSlowLoad, isFalse);

      // A new refresh is allowed once the previous one has finished.
      final next = controller.refresh();
      expect(repo.requests, hasLength(2));
      repo.requests.last.complete(realSnapshot());
      await next;
      controller.dispose();
    });

    test('every request ends: the slow flag clears on error too', () async {
      final repo = PendingRepository();
      final controller = ArrivalsController(
        repository: repo,
        clock: () => testNow,
        slowAfter: const Duration(milliseconds: 10),
      );
      final run = controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.isSlowLoad, isTrue);

      repo.requests.single.completeError(const TransportFetchException('x'));
      await run;
      expect(controller.status, LoadStatus.error);
      expect(controller.isSlowLoad, isFalse);
      controller.dispose();
    });
  });
}

final String _golden = File(
  'test/fixtures/backend_output_v1.json',
).readAsStringSync();
