import 'transport_service.dart';
import 'transport_type.dart';

enum DemandHub { railway, airport, coachStation }

enum DemandLevel { low, moderate, high }

extension DemandHubOfType on TransportType {
  DemandHub get hub => switch (this) {
    TransportType.train => DemandHub.railway,
    TransportType.flight => DemandHub.airport,
    TransportType.coach => DemandHub.coachStation,
  };
}

class DemandBucket {
  const DemandBucket({
    required this.fromMinute,
    required this.toMinute,
    required this.count,
  });

  final int fromMinute;
  final int toMinute;
  final int count;
}

class HubDemand {
  const HubDemand({
    required this.hub,
    required this.arrivalsNextHour,
    this.nextArrival,
  });

  final DemandHub hub;
  final int arrivalsNextHour;
  final DateTime? nextArrival;
}

/// Transparent, count-based heuristic of potential demand near transport hubs.
///
/// It only counts upcoming, non-cancelled arrivals. It does NOT estimate
/// passengers and says nothing about real ride requests on any platform.
///
/// Level is based on arrivals in the next 60 minutes:
/// `< moderateFrom` low, `< highFrom` moderate, otherwise high.
class DemandOverview {
  const DemandOverview({
    required this.level,
    required this.arrivalsNextHour,
    required this.arrivalsInWindow,
    required this.scheduleOnlyCount,
    required this.buckets,
    required this.hubs,
    required this.isSampleData,
  });

  static const int windowMinutes = 120;
  static const int bucketMinutes = 30;
  static const int moderateFrom = 2;
  static const int highFrom = 4;

  final DemandLevel level;
  final int arrivalsNextHour;
  final int arrivalsInWindow;

  /// Counted arrivals that only have a timetable time (no estimate).
  final int scheduleOnlyCount;
  final List<DemandBucket> buckets;
  final List<HubDemand> hubs;

  /// True when any counted service is mock data.
  final bool isSampleData;

  factory DemandOverview.compute(
    Iterable<TransportService> services,
    DateTime now,
  ) {
    final counted = <(TransportService, int)>[];
    for (final service in services) {
      if (service.isCancelled || service.actualArrival != null) continue;
      final minutes = service.minutesUntil(now);
      if (minutes < 0 || minutes > windowMinutes) continue;
      counted.add((service, minutes));
    }

    final bucketCount = windowMinutes ~/ bucketMinutes;
    final counts = List<int>.filled(bucketCount, 0);
    for (final (_, minutes) in counted) {
      counts[(minutes ~/ bucketMinutes).clamp(0, bucketCount - 1)]++;
    }
    final buckets = [
      for (var i = 0; i < bucketCount; i++)
        DemandBucket(
          fromMinute: i * bucketMinutes,
          toMinute: (i + 1) * bucketMinutes,
          count: counts[i],
        ),
    ];

    final nextHour = counted.where((entry) => entry.$2 <= 60).toList();
    final hubs = [
      for (final hub in DemandHub.values)
        () {
          final own = counted
              .where((entry) => entry.$1.type.hub == hub)
              .toList();
          final ownHour = own.where((entry) => entry.$2 <= 60).length;
          DateTime? next;
          for (final entry in own) {
            final time = entry.$1.effectiveArrival;
            if (next == null || time.isBefore(next)) next = time;
          }
          return HubDemand(
            hub: hub,
            arrivalsNextHour: ownHour,
            nextArrival: next,
          );
        }(),
    ];

    final level = nextHour.length >= highFrom
        ? DemandLevel.high
        : nextHour.length >= moderateFrom
        ? DemandLevel.moderate
        : DemandLevel.low;

    return DemandOverview(
      level: level,
      arrivalsNextHour: nextHour.length,
      arrivalsInWindow: counted.length,
      scheduleOnlyCount: counted
          .where((e) => e.$1.estimatedArrival == null)
          .length,
      buckets: buckets,
      hubs: hubs,
      isSampleData: counted.any((e) => e.$1.source.isMock),
    );
  }
}
