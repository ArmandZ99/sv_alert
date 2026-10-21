import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/dashboard/domain/demand_overview.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

import '../support.dart';

void main() {
  test('no arrivals gives low demand and empty buckets', () {
    final overview = DemandOverview.compute([], testNow);
    expect(overview.level, DemandLevel.low);
    expect(overview.arrivalsInWindow, 0);
    expect(overview.buckets.map((b) => b.count), [0, 0, 0, 0]);
    expect(overview.isSampleData, isFalse);
  });

  test('cancelled, arrived and past services are not counted', () {
    final overview = DemandOverview.compute([
      makeService(id: 'a', scheduled: 10, estimated: 10, cancelled: true),
      makeService(id: 'b', scheduled: -10, actual: -8),
      makeService(id: 'c', scheduled: -3),
      makeService(id: 'd', scheduled: 10, estimated: 10),
    ], testNow);
    expect(overview.arrivalsInWindow, 1);
  });

  test('uses the estimate rather than the schedule for placement', () {
    final overview = DemandOverview.compute([
      makeService(scheduled: 10, estimated: 70),
    ], testNow);
    expect(overview.buckets.map((b) => b.count), [0, 0, 1, 0]);
    expect(overview.arrivalsNextHour, 0);
  });

  test('level thresholds are based on arrivals in the next hour', () {
    List<int> offsets(int n) => [for (var i = 0; i < n; i++) 5 + i];
    DemandLevel level(int n) => DemandOverview.compute([
      for (final o in offsets(n))
        makeService(id: 's$o', scheduled: o, estimated: o),
    ], testNow).level;

    expect(level(1), DemandLevel.low);
    expect(level(2), DemandLevel.moderate);
    expect(level(3), DemandLevel.moderate);
    expect(level(4), DemandLevel.high);
  });

  test(
    'arrivals after the two hour window are excluded; boundary is included',
    () {
      final overview = DemandOverview.compute([
        makeService(id: 'in', scheduled: 120, estimated: 120),
        makeService(id: 'out', scheduled: 121, estimated: 121),
      ], testNow);
      expect(overview.arrivalsInWindow, 1);
      expect(overview.buckets.last.count, 1);
    },
  );

  test('per-hub counts and next arrival', () {
    final overview = DemandOverview.compute([
      makeService(id: 't1', scheduled: 20, estimated: 20),
      makeService(id: 't2', scheduled: 50, estimated: 50),
      makeService(
        id: 'f1',
        type: TransportType.flight,
        scheduled: 90,
        estimated: 90,
      ),
    ], testNow);
    final railway = overview.hubs.firstWhere((h) => h.hub == DemandHub.railway);
    final airport = overview.hubs.firstWhere((h) => h.hub == DemandHub.airport);
    final coach = overview.hubs.firstWhere(
      (h) => h.hub == DemandHub.coachStation,
    );
    expect(railway.arrivalsNextHour, 2);
    expect(railway.nextArrival, minutesFrom(20));
    expect(airport.arrivalsNextHour, 0);
    expect(airport.nextArrival, minutesFrom(90));
    expect(coach.nextArrival, isNull);
  });

  test('flags schedule-only arrivals and sample data', () {
    final overview = DemandOverview.compute([
      makeService(id: 'a', scheduled: 20, mock: true),
      makeService(id: 'b', scheduled: 25, estimated: 25, mock: true),
    ], testNow);
    expect(overview.scheduleOnlyCount, 1);
    expect(overview.isSampleData, isTrue);
  });
}
