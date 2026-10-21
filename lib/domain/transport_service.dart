import 'arrival_status.dart';
import 'transport_type.dart';

/// Where a service's data came from.
class SourceInfo {
  const SourceInfo({required this.name, this.url, this.isMock = false});

  final String name;

  /// Link to the original source, when one exists.
  final String? url;

  /// True for generated demonstration data that must never be presented as live.
  final bool isMock;
}

/// A single arrival in Suceava, normalized across flights, trains and coaches.
class TransportService {
  const TransportService({
    required this.id,
    required this.type,
    required this.source,
    required this.serviceNumber,
    required this.routeStops,
    required this.arrivalPoint,
    required this.serviceDate,
    required this.scheduledArrival,
    required this.dataQuality,
    required this.lastUpdated,
    this.operatorName,
    this.estimatedArrival,
    this.actualArrival,
    this.isCancelled = false,
    this.sourceTimestamp,
  }) : assert(
         routeStops.length >= 2,
         'A route needs an origin and a destination',
       );

  /// Stable internal id (must differ across service dates).
  final String id;
  final TransportType type;
  final SourceInfo source;

  /// Flight number, train number, or the coach line name.
  final String serviceNumber;
  final String? operatorName;

  /// Full route from origin to final destination, Suceava included.
  final List<String> routeStops;

  /// Station, terminal or stop in Suceava where the service arrives.
  final String arrivalPoint;

  /// Calendar date of the service (date-only), so identical numbers on
  /// different days are not conflated.
  final DateTime serviceDate;
  final DateTime scheduledArrival;
  final DateTime? estimatedArrival;
  final DateTime? actualArrival;
  final bool isCancelled;
  final DataQuality dataQuality;

  /// When the app last fetched this service.
  final DateTime lastUpdated;

  /// Timestamp reported by the source itself, when available.
  final DateTime? sourceTimestamp;

  String get origin => routeStops.first;
  String get destination => routeStops.last;

  /// Best known arrival time: actual, then estimated, then scheduled.
  DateTime get effectiveArrival =>
      actualArrival ?? estimatedArrival ?? scheduledArrival;

  /// True when only the timetable is known (no estimate, no actual time).
  bool get isScheduleOnly => estimatedArrival == null && actualArrival == null;

  /// Delay versus the timetable, or null when no estimate is available.
  int? get delayMinutes {
    final reference = actualArrival ?? estimatedArrival;
    if (reference == null) return null;
    return reference.difference(scheduledArrival).inMinutes;
  }

  /// Whole minutes until [effectiveArrival], rounded up. Negative once past.
  int minutesUntil(DateTime now) =>
      (effectiveArrival.difference(now).inSeconds / 60).ceil();

  /// Status derived only from known facts. Schedule-only services never claim
  /// "on time" or "arriving soon", and an estimate that has passed without a
  /// confirmed arrival is reported as unknown.
  ArrivalStatus statusAt(DateTime now) {
    if (isCancelled) return ArrivalStatus.cancelled;
    if (actualArrival != null) return ArrivalStatus.arrived;
    if (estimatedArrival == null) return ArrivalStatus.unknown;
    if (!estimatedArrival!.isAfter(now)) return ArrivalStatus.unknown;
    final delay = delayMinutes ?? 0;
    if (delay >= StatusRules.delayedFromMinutes) return ArrivalStatus.delayed;
    if (minutesUntil(now) <= StatusRules.arrivingSoonWithinMinutes) {
      return ArrivalStatus.arrivingSoon;
    }
    return ArrivalStatus.onTime;
  }
}
