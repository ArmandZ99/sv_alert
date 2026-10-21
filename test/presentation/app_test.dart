import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travelalerts/features/settings/data/preferences_store.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/app/app.dart';
import 'package:travelalerts/features/transport/data/mock_transport_repository.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';

import '../support.dart';

TransportRepository mockRepo() =>
    MockTransportRepository(clock: () => testNow, latency: Duration.zero);

Future<void> pumpApp(
  WidgetTester tester, {
  TransportRepository? repository,
  bool settle = true,
  double height = 12000,
  PreferencesStore? store,
  NotificationPreferences initialPreferences = const NotificationPreferences(),
}) async {
  // Tall logical viewport (360 x 4000) so lazy lists build most of their items
  // while still exercising a small-phone width.
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SuceavaPulseApp(
      repository: repository ?? mockRepo(),
      clock: () => testNow,
      preferencesStore: store,
      initialPreferences: initialPreferences,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder filterChip(String label) => find.byWidgetPredicate(
  (w) => w is FilterChip && (w.label as Text).data!.startsWith(label),
);

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('dashboard', () {
    testWidgets(
      'shows loading first, then mock banner, demand overview and arrivals',
      (tester) async {
        await pumpApp(tester, settle: false);
        expect(find.text('Se încarcă sosirile…'), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.text('Se încarcă sosirile…'), findsNothing);
        expect(find.text('Date demonstrative (mock)'), findsOneWidget);
        expect(find.text('Actualizat chiar acum'), findsOneWidget);
        expect(find.text('POTENȚIAL DE CERERE'), findsOneWidget);
        expect(find.text('EXEMPLU'), findsOneWidget);
        expect(
          find.textContaining('Nu reprezintă comenzi Bolt reale'),
          findsOneWidget,
        );
        expect(find.text('Sosiri următoare'), findsOneWidget);
        // Soonest upcoming service first; arrived and expired ones are hidden.
        expect(find.text('IR 1831'), findsOneWidget);
        expect(find.text('RO 212'), findsNothing);
      },
    );

    testWidgets(
      'cards show scheduled vs estimated time and labelled sample delay',
      (tester) async {
        await pumpApp(tester);
        await openTab(tester, 'Sosiri');
        expect(find.text('Programat'), findsWidgets);
        expect(find.text('Estimat'), findsWidgets);
        expect(find.text('W4 1234'), findsOneWidget);
        expect(find.text('Întârziat +40 min · exemplu'), findsOneWidget);
        expect(find.text('Gara Suceava'), findsWidgets);
        expect(find.text('Aeroportul Suceava (SCV)'), findsWidgets);
        expect(find.text('Anulat'), findsOneWidget);
        expect(find.text('Estimare indisponibilă'), findsWidgets);
        expect(find.text('Doar orar programat'), findsWidgets);
        expect(find.text('DATE DEMO'), findsWidgets);
      },
    );

    testWidgets('error state offers retry and recovers', (tester) async {
      final repo = FakeRepository([
        const TransportFetchException('Verifică conexiunea.', isOffline: true),
        TransportSnapshot(
          services: [
            makeService(number: 'R 9999', scheduled: 20, estimated: 20),
          ],
          fetchedAt: testNow,
          isMock: true,
        ),
      ]);
      await pumpApp(tester, repository: repo);
      expect(find.text('Fără conexiune la internet'), findsOneWidget);
      expect(find.text('Verifică conexiunea.'), findsOneWidget);

      await tester.tap(find.text('Reîncearcă'));
      await tester.pumpAndSettle();
      expect(find.text('Fără conexiune la internet'), findsNothing);
      expect(find.text('R 9999'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await pumpApp(
        tester,
        repository: FakeRepository([
          TransportSnapshot(
            services: const [],
            fetchedAt: testNow,
            isMock: true,
          ),
        ]),
      );
      expect(find.text('Nicio sosire în perioada următoare'), findsOneWidget);
    });

    testWidgets('stale data is flagged with its age', (tester) async {
      final old = testNow.subtract(const Duration(minutes: 30));
      await pumpApp(
        tester,
        repository: FakeRepository([
          TransportSnapshot(
            services: [makeService(scheduled: 20, estimated: 20)],
            fetchedAt: old,
            isMock: false,
          ),
        ]),
      );
      expect(find.text('Actualizat acum 30 min'), findsOneWidget);
      expect(find.text('Datele par vechi'), findsOneWidget);
      // Not mock: no demo banner.
      expect(find.text('Date demonstrative (mock)'), findsNothing);
    });

    testWidgets(
      'failed refresh keeps showing the previous data with a warning',
      (tester) async {
        final repo = FakeRepository([
          TransportSnapshot(
            services: [
              makeService(number: 'R 9999', scheduled: 20, estimated: 20),
            ],
            fetchedAt: testNow,
            isMock: false,
          ),
          const TransportFetchException('Sursa nu răspunde.'),
        ]);
        await pumpApp(tester, repository: repo, height: 2400);
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        expect(repo.calls, 2);
        expect(find.textContaining('Sursa nu răspunde.'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('R 9999'), 200);
        expect(find.text('R 9999'), findsOneWidget);
      },
    );

    testWidgets('pull to refresh reloads data', (tester) async {
      final repo = FakeRepository([
        TransportSnapshot(
          services: [makeService(scheduled: 20, estimated: 20)],
          fetchedAt: testNow,
          isMock: true,
        ),
      ]);
      await pumpApp(tester, repository: repo, height: 2400);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(repo.calls, 2);
    });
  });

  group('arrivals page', () {
    testWidgets('filters by transport type', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');
      expect(find.text('Sosiri în Suceava'), findsOneWidget);
      expect(find.text('W4 1234'), findsOneWidget);
      expect(find.text('IR 1831'), findsOneWidget);

      await tester.tap(filterChip('Avioane'));
      await tester.pumpAndSettle();
      expect(find.text('W4 1234'), findsOneWidget);
      expect(find.text('RO 214'), findsOneWidget);
      expect(find.text('IR 1831'), findsNothing);
      expect(find.text('Linia Botoșani – Suceava'), findsNothing);

      await tester.tap(filterChip('Autocare'));
      await tester.pumpAndSettle();
      expect(find.text('Linia Botoșani – Suceava'), findsOneWidget);
      expect(find.text('W4 1234'), findsNothing);

      await tester.tap(filterChip('Trenuri'));
      await tester.pumpAndSettle();
      expect(find.text('IR 1831'), findsOneWidget);
      expect(find.text('R 5608'), findsOneWidget);
    });

    testWidgets('search by service number ignores spaces and diacritics', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');

      await tester.enterText(find.byType(TextField), 'ir1831');
      await tester.pumpAndSettle();
      expect(find.text('IR 1831'), findsOneWidget);
      expect(find.text('W4 1234'), findsNothing);

      await tester.enterText(find.byType(TextField), 'botosani');
      await tester.pumpAndSettle();
      expect(find.text('Linia Botoșani – Suceava'), findsOneWidget);
    });

    testWidgets('no match shows an empty result with a way to clear filters', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nicio cursă nu corespunde filtrelor'), findsOneWidget);

      await tester.tap(find.text('Șterge filtrele'));
      await tester.pumpAndSettle();
      expect(find.text('Nicio cursă nu corespunde filtrelor'), findsNothing);
      expect(find.text('IR 1831'), findsOneWidget);
    });
  });

  group('service details', () {
    testWidgets('shows route, times, source and mock labelling', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');
      await tester.tap(find.text('W4 1234'));
      await tester.pumpAndSettle();

      expect(find.text('TRASEU'), findsOneWidget);
      expect(find.text('Londra Luton (LTN)'), findsOneWidget);
      expect(find.text('Aeroportul Suceava (SCV)'), findsWidgets);
      expect(find.text('+40 min (exemplu)'), findsOneWidget);
      expect(
        find.text('Date demonstrative (mock) — nu sunt date reale'),
        findsOneWidget,
      );
      expect(
        find.text('Indisponibil'),
        findsWidgets,
      ); // source link / source time
      expect(
        find.text('Indisponibil în datele demonstrative.'),
        findsOneWidget,
      );
    });

    testWidgets('a schedule-only service says the estimate is unavailable', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');
      await tester.tap(find.text('Linia Botoșani – Suceava'));
      await tester.pumpAndSettle();

      expect(find.text('Stare necunoscută'), findsWidgets);
      expect(find.text('Estimare indisponibilă'), findsWidgets);
    });

    testWidgets('can follow a service', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Sosiri');
      await tester.tap(find.text('IR 1831'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('settings', () {
    testWidgets('says push notifications are not active and edits reminders', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Setări');

      expect(
        find.text('Notificările push nu sunt active încă'),
        findsOneWidget,
      );
      final chip = find.widgetWithText(FilterChip, '10 min');
      expect(tester.widget<FilterChip>(chip).selected, isFalse);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '15 min'))
            .selected,
        isTrue,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
    });

    testWidgets('master switch disables the dependent controls', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Setări');

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Notificări active'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '10 min'))
            .onSelected,
        isNull,
      );
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });

    testWidgets('alert categories switch their own controls', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Setări');
      final chip = find.widgetWithText(FilterChip, '10 min');

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Alerte înainte de sosire'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).onSelected, isNull);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Alerte de întârziere'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });

    testWidgets('settings are saved and restored after a restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferencesStore.create();
      await pumpApp(
        tester,
        store: store,
        initialPreferences: await store.load(),
      );
      await openTab(tester, 'Setări');

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Alerte de întârziere'),
      );
      await tester.tap(find.widgetWithText(FilterChip, '10 min'));
      await tester.pumpAndSettle();

      // Restart: a fresh app tree that loads what was saved.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        store: store,
        initialPreferences: await store.load(),
      );
      await openTab(tester, 'Setări');

      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Alerte de întârziere'),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '10 min'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Alerte înainte de sosire'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('quiet hours reveal their time rows', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Setări');

      expect(find.text('De la'), findsNothing);
      await tester.tap(
        find.widgetWithText(
          SwitchListTile,
          'Fără notificări în intervalul ales',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('De la'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
    });

    testWidgets('states the app is independent', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Setări');
      await tester.scrollUntilVisible(
        find.textContaining('Aplicație comunitară independentă'),
        200,
      );
      expect(find.textContaining('Bolt'), findsOneWidget);
    });
  });
}
