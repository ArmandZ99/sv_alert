import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/core/time/bucharest_time.dart';
import 'package:travelalerts/features/notifications/domain/notification_evaluator.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/domain/transport_service.dart';

import '../support.dart';

DateTime at(int h, int m, [int day = 21]) =>
    BucharestTime.fromWallClock(2026, 10, day, h, m);

NotificationPreferences quietPrefs({
  int start = 11 * 60,
  int end = 12 * 60 + 15,
  bool enabled = true,
}) => NotificationPreferences(
  quietHours: QuietHours(
    enabled: enabled,
    startMinutes: start,
    endMinutes: end,
  ),
);

EvaluationResult run(
  List<TransportService> services,
  NotificationPreferences prefs,
  DateTime now, {
  Set<String> handled = const {},
}) => NotificationEvaluator.evaluate(
  services: services,
  preferences: prefs,
  now: now,
  alreadyHandled: handled,
  staleAfter: const Duration(hours: 2),
);

// Services are built at `base` (their fetch time) and arrive at offsets from it.
TransportService service(
  DateTime base, {
  required int scheduled,
  int? estimated,
  String id = 's1',
}) =>
    makeService(base: base, id: id, scheduled: scheduled, estimated: estimated);

void main() {
  group('arrival reminders during quiet hours are suppressed', () {
    test('no event, but the key is recorded so it never fires later', () {
      final now = at(12, 10); // inside 11:00-12:15
      final s = service(now, scheduled: 30, estimated: 30); // 30 min left
      final result = run([s], quietPrefs(), now);

      expect(result.events, isEmpty);
      expect(result.suppressedByQuietHours.map((e) => e.thresholdMinutes), [
        30,
      ]);
      expect(result.keysToRecord, contains('s1|2026-10-21|arrivalReminder|30'));
    });

    test(
      'after quiet hours the suppressed threshold does not fire; the next one does',
      () {
        final start = at(12, 10);
        final s = service(start, scheduled: 30, estimated: 30); // arrives 12:40
        final first = run([s], quietPrefs(), start);

        // 12:20: quiet is over, 20 min left, 30-min reminder already handled.
        final later = run(
          [s],
          quietPrefs(),
          at(12, 20),
          handled: first.keysToRecord,
        );
        expect(later.events, isEmpty);

        // 12:27: 13 min left -> the 15-minute reminder fires normally.
        final tighter = run(
          [s],
          quietPrefs(),
          at(12, 27),
          handled: first.keysToRecord,
        );
        expect(tighter.events.map((e) => e.thresholdMinutes), [15]);
      },
    );

    test('outside quiet hours the same reminder is delivered', () {
      final now = at(12, 20);
      final result = run(
        [service(now, scheduled: 30, estimated: 30)],
        quietPrefs(),
        now,
      );
      expect(result.events.map((e) => e.thresholdMinutes), [30]);
      expect(result.suppressedByQuietHours, isEmpty);
    });
  });

  group('delay alerts during quiet hours are deferred', () {
    test('held back and not recorded', () {
      final now = at(12, 0);
      final s = service(now, scheduled: 60, estimated: 85); // 25 min late
      final result = run([s], quietPrefs(), now);

      expect(result.events, isEmpty);
      expect(result.deferredByQuietHours.map((e) => e.delayMinutes), [25]);
      expect(
        result.keysToRecord,
        isNot(contains('s1|2026-10-21|significantDelay|15')),
      );
    });

    test('sent on the first evaluation after quiet hours, once', () {
      final s = service(at(12, 0), scheduled: 60, estimated: 85);
      final during = run([s], quietPrefs(), at(12, 0));
      expect(during.events, isEmpty);

      final after = run(
        [s],
        quietPrefs(),
        at(12, 16),
        handled: during.keysToRecord,
      );
      expect(after.events.map((e) => e.key), [
        's1|2026-10-21|significantDelay|15',
      ]);

      final again = run(
        [s],
        quietPrefs(),
        at(12, 20),
        handled: {...during.keysToRecord, ...after.keysToRecord},
      );
      expect(again.events, isEmpty);
    });

    test(
      'a deferred delay is dropped if the service is cancelled meanwhile',
      () {
        final base = at(12, 0);
        final cancelled = makeService(
          base: base,
          scheduled: 60,
          estimated: 85,
          cancelled: true,
        );
        expect(run([cancelled], quietPrefs(), at(12, 16)).events, isEmpty);
      },
    );
  });

  group('quiet period edge cases', () {
    test('disabled quiet hours do not hold anything back', () {
      final now = at(12, 0);
      final result = run(
        [service(now, scheduled: 60, estimated: 85)],
        quietPrefs(enabled: false),
        now,
      );
      expect(result.events, hasLength(1));
      expect(result.deferredByQuietHours, isEmpty);
    });

    test('start equals end: not quiet, alerts are delivered', () {
      final now = at(12, 0);
      final result = run(
        [service(now, scheduled: 60, estimated: 85)],
        quietPrefs(start: 12 * 60, end: 12 * 60),
        now,
      );
      expect(result.events, hasLength(1));
    });

    test('overnight 22:00-07:00 across midnight', () {
      final prefs = quietPrefs(start: 22 * 60, end: 7 * 60);
      final lateNight = at(23, 40);
      final r1 = run(
        [service(lateNight, scheduled: 30, estimated: 30)],
        prefs,
        lateNight,
      );
      expect(r1.events, isEmpty);
      expect(r1.suppressedByQuietHours, hasLength(1));

      final afterMidnight = at(0, 30, 22);
      final r2 = run(
        [service(afterMidnight, scheduled: 30, estimated: 30)],
        prefs,
        afterMidnight,
      );
      expect(r2.events, isEmpty);

      final morning = at(7, 0, 22);
      final r3 = run(
        [service(morning, scheduled: 30, estimated: 30)],
        prefs,
        morning,
      );
      expect(r3.events, hasLength(1)); // 07:00 is the first non-quiet minute
    });

    test(
      'boundary: alert at the exact quiet start is held, at the exact end is sent',
      () {
        final prefs = quietPrefs(start: 11 * 60, end: 12 * 60);
        final atStart = at(11, 0);
        expect(
          run(
            [service(atStart, scheduled: 30, estimated: 30)],
            prefs,
            atStart,
          ).events,
          isEmpty,
        );
        final atEnd = at(12, 0);
        expect(
          run(
            [service(atEnd, scheduled: 30, estimated: 30)],
            prefs,
            atEnd,
          ).events,
          hasLength(1),
        );
      },
    );
  });
}
