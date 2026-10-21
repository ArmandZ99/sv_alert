import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travelalerts/features/notifications/data/shared_preferences_alert_history_store.dart';
import 'package:travelalerts/features/notifications/domain/alert_engine.dart';
import 'package:travelalerts/features/notifications/domain/alert_history_store.dart';
import 'package:travelalerts/features/notifications/domain/notification_evaluator.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

import '../support.dart';

class MemoryStore implements AlertHistoryStore {
  Map<String, DateTime> data = {};
  int saves = 0;

  @override
  Future<Map<String, DateTime>> load() async => Map.of(data);

  @override
  Future<void> save(Map<String, DateTime> handled) async {
    saves++;
    data = Map.of(handled);
  }
}

class FailingStore implements AlertHistoryStore {
  @override
  Future<Map<String, DateTime>> load() async => throw StateError('unreadable');

  @override
  Future<void> save(Map<String, DateTime> handled) async =>
      throw StateError('disk full');
}

// Delayed and close: yields a 15-min reminder (est. 15 min) and a delay alert.
final soonDelayed = makeService(scheduled: 0, estimated: 15);

Future<EvaluationResult> evaluate(
  AlertEngine engine, [
  DateTime? now,
  List? services,
]) => engine.evaluate(
  services: (services ?? [soonDelayed]).cast(),
  preferences: const NotificationPreferences(),
  now: now ?? testNow,
);

void main() {
  test('the first evaluation alerts; the second is suppressed', () async {
    final engine = AlertEngine(store: MemoryStore());
    expect((await evaluate(engine)).events, hasLength(2));
    expect((await evaluate(engine)).events, isEmpty);
  });

  test('handled keys survive a restart (new engine, same store)', () async {
    final store = MemoryStore();
    final first = await evaluate(AlertEngine(store: store));
    expect(first.events, isNotEmpty);
    expect(store.data.keys.toSet(), first.keysToRecord);

    final restarted = AlertEngine(store: store);
    expect((await evaluate(restarted)).events, isEmpty);
  });

  test('persists across SharedPreferences store instances', () async {
    SharedPreferences.setMockInitialValues({});
    final firstStore = await SharedPreferencesAlertHistoryStore.create();
    final first = await evaluate(AlertEngine(store: firstStore));
    expect(first.events, hasLength(2));

    // A brand-new store object reading the same underlying storage.
    final secondStore = SharedPreferencesAlertHistoryStore(
      await SharedPreferences.getInstance(),
    );
    final loaded = await secondStore.load();
    expect(loaded.keys.toSet(), first.keysToRecord);
    expect(loaded.values.every((t) => t.isUtc), isTrue);
    expect(loaded.values.first, testNow);

    expect((await evaluate(AlertEngine(store: secondStore))).events, isEmpty);
  });

  test('a service on another date is a different event', () async {
    final store = MemoryStore();
    await evaluate(AlertEngine(store: store));

    // Same id and number one day later (service date differs).
    final tomorrowBase = testNow.add(const Duration(days: 1));
    final tomorrow = makeService(
      base: tomorrowBase,
      scheduled: 0,
      estimated: 15,
    );
    final result = await AlertEngine(store: store).evaluate(
      services: [tomorrow],
      preferences: const NotificationPreferences(),
      now: tomorrowBase,
    );
    expect(result.events, hasLength(2));
    expect(result.events.first.key, contains('2026-10-22'));
  });

  test('arrival thresholds are distinct keys', () async {
    final store = MemoryStore();
    final engine = AlertEngine(store: store);
    final service = makeService(scheduled: 30, estimated: 30);
    Future<EvaluationResult> at(int minutes) => engine.evaluate(
      services: [service],
      preferences: const NotificationPreferences(),
      now: minutesFrom(minutes),
      staleAfter: const Duration(hours: 1),
    );

    expect((await at(0)).events.map((e) => e.thresholdMinutes), [30]);
    expect((await at(16)).events.map((e) => e.thresholdMinutes), [15]);
    expect(
      store.data.keys,
      containsAll([
        's1|2026-10-21|arrivalReminder|30',
        's1|2026-10-21|arrivalReminder|15',
      ]),
    );
  });

  test(
    'the key format is stable and includes service date, kind and threshold',
    () {
      final key = AlertKeys.of(
        makeService(id: 'ir1831'),
        AlertKind.arrivalReminder,
        15,
      );
      expect(key, 'ir1831|2026-10-21|arrivalReminder|15');
    },
  );

  test(
    'transport type does not affect suppression: all three are handled',
    () async {
      final engine = AlertEngine(store: MemoryStore());
      final services = [
        for (final (i, type) in TransportType.values.indexed)
          makeService(id: 'x$i', type: type, scheduled: 10, estimated: 10),
      ];
      expect((await evaluate(engine, testNow, services)).events, hasLength(3));
      expect((await evaluate(engine, testNow, services)).events, isEmpty);
    },
  );

  group('storage errors', () {
    test(
      'unreadable history starts empty and the engine still works',
      () async {
        final engine = AlertEngine(store: FailingStore());
        expect((await evaluate(engine)).events, hasLength(2));
      },
    );

    test(
      'a failed save is flagged, yet duplicates stay suppressed this session',
      () async {
        final engine = AlertEngine(store: FailingStore());
        await evaluate(engine);
        expect(engine.lastSaveFailed, isTrue);
        expect((await evaluate(engine)).events, isEmpty);
      },
    );

    test('corrupt stored data is ignored entry by entry', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesAlertHistoryStore.storageKey:
            '{"good":"2026-10-21T09:00:00.000Z","bad":"not a date","num":5}',
      });
      final store = await SharedPreferencesAlertHistoryStore.create();
      expect((await store.load()).keys, ['good']);

      SharedPreferences.setMockInitialValues({
        SharedPreferencesAlertHistoryStore.storageKey: '{{{',
      });
      expect(
        await (await SharedPreferencesAlertHistoryStore.create()).load(),
        isEmpty,
      );

      SharedPreferences.setMockInitialValues({
        SharedPreferencesAlertHistoryStore.storageKey: '[1,2]',
      });
      expect(
        await (await SharedPreferencesAlertHistoryStore.create()).load(),
        isEmpty,
      );
    });
  });

  group('retention', () {
    test('old keys are pruned, recent ones kept', () async {
      final store = MemoryStore()
        ..data = {
          'old|2026-10-10|arrivalReminder|15': testNow.subtract(
            const Duration(days: 5),
          ),
          'recent|2026-10-20|arrivalReminder|15': testNow.subtract(
            const Duration(hours: 20),
          ),
        };
      final engine = AlertEngine(store: store);
      await evaluate(engine);
      expect(store.data.keys, contains('recent|2026-10-20|arrivalReminder|15'));
      expect(
        store.data.keys,
        isNot(contains('old|2026-10-10|arrivalReminder|15')),
      );
    });

    test('nothing is written when nothing changed', () async {
      final store = MemoryStore();
      final engine = AlertEngine(store: store);
      await evaluate(engine);
      final saves = store.saves;
      await evaluate(engine);
      expect(store.saves, saves);
    });
  });

  test('the engine only decides: it exposes events, no delivery', () async {
    final result = await evaluate(AlertEngine(store: MemoryStore()));
    expect(result.events.every((e) => e.key.isNotEmpty), isTrue);
  });
}
