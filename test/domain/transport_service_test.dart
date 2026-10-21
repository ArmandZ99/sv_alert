import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';

import '../support.dart';

void main() {
  group('delay and effective arrival', () {
    test('delay is estimate minus schedule, null without an estimate', () {
      expect(makeService(scheduled: 30, estimated: 70).delayMinutes, 40);
      expect(makeService(scheduled: 30).delayMinutes, isNull);
    });

    test('effective arrival prefers actual, then estimate, then schedule', () {
      expect(makeService(scheduled: 30).effectiveArrival, minutesFrom(30));
      expect(
        makeService(scheduled: 30, estimated: 40).effectiveArrival,
        minutesFrom(40),
      );
      expect(
        makeService(scheduled: 30, estimated: 40, actual: 38).effectiveArrival,
        minutesFrom(38),
      );
    });

    test('minutesUntil rounds up and goes negative once past', () {
      final service = makeService(scheduled: 10, estimated: 10);
      expect(
        service.minutesUntil(testNow.add(const Duration(seconds: 30))),
        10,
      );
      expect(service.minutesUntil(minutesFrom(12)), -2);
    });

    test('route exposes origin and destination', () {
      final service = makeService(stops: ['A', 'B', 'C']);
      expect(service.origin, 'A');
      expect(service.destination, 'C');
    });
  });

  group('statusAt', () {
    test('cancelled wins over everything', () {
      expect(
        makeService(estimated: 30, cancelled: true).statusAt(testNow),
        ArrivalStatus.cancelled,
      );
    });

    test('actual arrival means arrived', () {
      expect(
        makeService(scheduled: -10, actual: -8).statusAt(testNow),
        ArrivalStatus.arrived,
      );
    });

    test('schedule-only services are unknown, never on time', () {
      final service = makeService(scheduled: 5, quality: DataQuality.scheduled);
      expect(service.isScheduleOnly, isTrue);
      expect(service.statusAt(testNow), ArrivalStatus.unknown);
    });

    test(
      'estimate in the past without confirmation is unknown, not arrived',
      () {
        expect(
          makeService(scheduled: -5, estimated: -3).statusAt(testNow),
          ArrivalStatus.unknown,
        );
      },
    );

    test('delay at the display threshold is delayed, just under is not', () {
      expect(
        makeService(scheduled: 60, estimated: 65).statusAt(testNow),
        ArrivalStatus.delayed,
      );
      expect(
        makeService(scheduled: 60, estimated: 64).statusAt(testNow),
        ArrivalStatus.onTime,
      );
    });

    test('estimate within 15 minutes is arriving soon', () {
      expect(
        makeService(scheduled: 15, estimated: 15).statusAt(testNow),
        ArrivalStatus.arrivingSoon,
      );
      expect(
        makeService(scheduled: 16, estimated: 16).statusAt(testNow),
        ArrivalStatus.onTime,
      );
    });

    test('a delayed service stays delayed even when close', () {
      expect(
        makeService(scheduled: 2, estimated: 12).statusAt(testNow),
        ArrivalStatus.delayed,
      );
    });
  });
}
