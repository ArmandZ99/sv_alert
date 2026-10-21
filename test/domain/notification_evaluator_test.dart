import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';
import 'package:travelalerts/features/notifications/domain/notification_evaluator.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

import '../support.dart';

EvaluationResult run(
  List services, {
  NotificationPreferences prefs = const NotificationPreferences(),
  DateTime? now,
  Set<String> handled = const {},
  Duration staleAfter = NotificationEvaluator.defaultStaleAfter,
}) => NotificationEvaluator.evaluate(
  services: services.cast(),
  preferences: prefs,
  now: now ?? testNow,
  alreadyHandled: handled,
  staleAfter: staleAfter,
);

void main() {
  group('arrival reminders', () {
    test('no event while above every threshold', () {
      final result = run([makeService(scheduled: 45, estimated: 45)]);
      expect(result.events, isEmpty);
      expect(result.keysToRecord, isEmpty);
    });

    test('fires when a threshold is reached, exactly at the boundary', () {
      final result = run([makeService(scheduled: 30, estimated: 30)]);
      expect(result.events, hasLength(1));
      final event = result.events.single;
      expect(event.kind, AlertKind.arrivalReminder);
      expect(event.thresholdMinutes, 30);
      expect(event.minutesUntil, 30);
      expect(event.isScheduleBased, isFalse);
    });

    test('first seen late: only the tightest crossed threshold fires', () {
      final result = run([makeService(scheduled: 12, estimated: 12)]);
      expect(result.events.map((e) => e.thresholdMinutes), [15]);
      // Looser thresholds are recorded so they never fire later.
      expect(
        result.keysToRecord,
        containsAll(['s1|arrivalReminder|15', 's1|arrivalReminder|30']),
      );
    });

    test('successive thresholds fire one at a time as time passes', () {
      final service = makeService(scheduled: 40, estimated: 40);
      var handled = <String>{};

      var result = run(
        [service],
        now: minutesFrom(10),
        handled: handled,
        staleAfter: const Duration(hours: 1),
      ); // 30 left
      expect(result.events.map((e) => e.thresholdMinutes), [30]);
      handled = {...handled, ...result.keysToRecord};

      result = run(
        [service],
        now: minutesFrom(20),
        handled: handled,
        staleAfter: const Duration(hours: 1),
      ); // 20 left
      expect(result.events, isEmpty);

      result = run(
        [service],
        now: minutesFrom(26),
        handled: handled,
        staleAfter: const Duration(hours: 1),
      ); // 14 left
      expect(result.events.map((e) => e.thresholdMinutes), [15]);
      handled = {...handled, ...result.keysToRecord};

      result = run(
        [service],
        now: minutesFrom(36),
        handled: handled,
        staleAfter: const Duration(hours: 1),
      ); // 4 left
      expect(result.events.map((e) => e.thresholdMinutes), [5]);
    });

    test('uses the estimate, not the schedule, to decide', () {
      final result = run([makeService(scheduled: 10, estimated: 60)]);
      expect(
        result.events.where((e) => e.kind == AlertKind.arrivalReminder),
        isEmpty,
      );
    });

    test(
      'schedule-only services still remind but are flagged schedule-based',
      () {
        final result = run([
          makeService(scheduled: 10, quality: DataQuality.scheduled),
        ]);
        expect(result.events, hasLength(1));
        expect(result.events.single.isScheduleBased, isTrue);
      },
    );

    test('custom thresholds are honoured', () {
      const prefs = NotificationPreferences(reminderMinutes: [10]);
      expect(
        run([makeService(scheduled: 15, estimated: 15)], prefs: prefs).events,
        isEmpty,
      );
      expect(
        run([
          makeService(scheduled: 10, estimated: 10),
        ], prefs: prefs).events.single.thresholdMinutes,
        10,
      );
    });
  });

  group('delay alerts', () {
    test('fires when the delay first meets the threshold', () {
      final result = run([makeService(scheduled: 60, estimated: 75)]);
      final delay = result.events.where(
        (e) => e.kind == AlertKind.significantDelay,
      );
      expect(delay, hasLength(1));
      expect(delay.single.delayMinutes, 15);
      expect(delay.single.thresholdMinutes, 15);
    });

    test('does not fire below the threshold', () {
      expect(run([makeService(scheduled: 60, estimated: 74)]).events, isEmpty);
    });

    test('respects a custom threshold', () {
      const prefs = NotificationPreferences(delayThresholdMinutes: 30);
      expect(
        run([makeService(scheduled: 60, estimated: 80)], prefs: prefs).events,
        isEmpty,
      );
      expect(
        run([makeService(scheduled: 60, estimated: 90)], prefs: prefs).events,
        hasLength(1),
      );
    });

    test('a timetable alone never produces a delay alert', () {
      final service = makeService(
        scheduled: 60,
        quality: DataQuality.scheduled,
      );
      expect(run([service]).events, isEmpty);
    });

    test('an estimate on schedule-quality data is not trusted for delay', () {
      final service = makeService(
        scheduled: 60,
        estimated: 90,
        quality: DataQuality.scheduled,
      );
      expect(run([service]).events, isEmpty);
    });

    test('live data counts', () {
      final service = makeService(
        scheduled: 60,
        estimated: 80,
        quality: DataQuality.live,
      );
      expect(run([service]).events, hasLength(1));
    });

    test('does not re-alert when the estimate keeps changing', () {
      final first = run([makeService(scheduled: 60, estimated: 80)]);
      final worse = run([
        makeService(scheduled: 60, estimated: 100),
      ], handled: first.keysToRecord);
      expect(worse.events, isEmpty);
    });
  });

  group('duplicate suppression', () {
    test('handled keys are not emitted again', () {
      final service = makeService(scheduled: 10, estimated: 25);
      final first = run([service]);
      expect(first.events, hasLength(2)); // 15-min reminder (est.)... and delay
      final second = run([service], handled: first.keysToRecord);
      expect(second.events, isEmpty);
    });

    test('same number on a different service date is a different event', () {
      final today = makeService(
        id: 'ir1831-20261021',
        scheduled: 10,
        estimated: 10,
      );
      final tomorrow = makeService(
        id: 'ir1831-20261022',
        scheduled: 10,
        estimated: 10,
      );
      final first = run([today]);
      final second = run([today, tomorrow], handled: first.keysToRecord);
      expect(second.events.map((e) => e.service.id), ['ir1831-20261022']);
    });

    test('keys are stable and unique per service, kind and threshold', () {
      final result = run([makeService(scheduled: 10, estimated: 30)]);
      expect(result.events.map((e) => e.key), [
        's1|arrivalReminder|30',
        's1|significantDelay|15',
      ]);
    });
  });

  group('preferences', () {
    final soon = makeService(scheduled: 10, estimated: 30);

    test('global switch off disables everything', () {
      expect(
        run([
          soon,
        ], prefs: const NotificationPreferences(enabled: false)).events,
        isEmpty,
      );
    });

    test('arrival alerts off keeps delay alerts', () {
      final result = run([
        soon,
      ], prefs: const NotificationPreferences(arrivalAlertsEnabled: false));
      expect(result.events.map((e) => e.kind), [AlertKind.significantDelay]);
    });

    test('delay alerts off keeps arrival reminders', () {
      final result = run([
        soon,
      ], prefs: const NotificationPreferences(delayAlertsEnabled: false));
      expect(result.events.map((e) => e.kind), [AlertKind.arrivalReminder]);
    });

    test('disabled transport types are ignored', () {
      final prefs = const NotificationPreferences().copyWith(
        followedTypes: {TransportType.flight, TransportType.coach},
      );
      expect(
        run([makeService(scheduled: 10, estimated: 10)], prefs: prefs).events,
        isEmpty,
      );
      final flight = makeService(
        type: TransportType.flight,
        scheduled: 10,
        estimated: 10,
      );
      expect(run([flight], prefs: prefs).events, isNotEmpty);
    });

    test('when specific services are followed, only those alert', () {
      final other = makeService(id: 'other', scheduled: 10, estimated: 10);
      final prefs = const NotificationPreferences().copyWith(
        followedServiceIds: {'s1'},
      );
      final result = run([
        makeService(scheduled: 10, estimated: 10),
        other,
      ], prefs: prefs);
      expect(result.events.map((e) => e.service.id).toSet(), {'s1'});
    });
  });

  group('missing, stale and finished services', () {
    test('stale data is ignored', () {
      final service = makeService(scheduled: 10, estimated: 30);
      final result = run([
        service,
      ], now: testNow.add(const Duration(minutes: 11)));
      expect(result.events, isEmpty);
    });

    test('data right at the stale limit is still used', () {
      final service = makeService(scheduled: 20, estimated: 40);
      final result = run([
        service,
      ], now: testNow.add(const Duration(minutes: 10)));
      expect(result.events, isNotEmpty);
    });

    test('cancelled, arrived and already-passed services are ignored', () {
      expect(
        run([
          makeService(scheduled: 10, estimated: 10, cancelled: true),
        ]).events,
        isEmpty,
      );
      expect(run([makeService(scheduled: -5, actual: -4)]).events, isEmpty);
      expect(run([makeService(scheduled: -3, estimated: -1)]).events, isEmpty);
    });

    test('empty input gives an empty result', () {
      expect(run([]).events, isEmpty);
    });
  });
}
