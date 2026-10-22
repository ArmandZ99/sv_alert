import '../time/bucharest_time.dart';

enum TransportKind { flight, train, coach }

enum DataQuality { scheduled, estimated, live, unknown }

/// State of one source, as reported to the app.
enum SourceConnection {
  /// Live data is flowing from the source.
  connected,

  /// Real, but timetable-only: never a live estimate or delay.
  scheduledOnly,

  /// Not usable now (blocked, expired, failing, or not permitted).
  unavailable,

  /// Needs an account or key that has not been provided.
  awaitingCredentials,
}

/// One arrival in Suceava in the contract served to the app (schema v1).
class NormalizedService {
  const NormalizedService({
    required this.id,
    required this.type,
    required this.sourceId,
    required this.sourceName,
    required this.sourceUrl,
    required this.serviceNumber,
    required this.routeStops,
    required this.arrivalPoint,
    required this.serviceDate,
    required this.scheduledArrival,
    required this.lastUpdated,
    this.operatorName,
    this.dataQuality = DataQuality.scheduled,
    this.sourceTimestamp,
  });

  final String id;
  final TransportKind type;
  final String sourceId;
  final String sourceName;
  final String sourceUrl;
  final String serviceNumber;
  final String? operatorName;
  final List<String> routeStops;
  final String arrivalPoint;

  /// Bucharest calendar date the service operates on (UTC-midnight value).
  final DateTime serviceDate;

  /// Absolute instant (UTC).
  final DateTime scheduledArrival;

  /// When the backend last fetched the underlying source (freshness).
  final DateTime lastUpdated;

  /// Timestamp the source itself publishes (for example a dataset export
  /// date), when it has one.
  final DateTime? sourceTimestamp;
  final DataQuality dataQuality;

  /// Scheduled-only services carry no estimated or actual arrival at all.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'source': {'name': sourceName, 'url': sourceUrl, 'isMock': false},
        'serviceNumber': serviceNumber,
        'operatorName': operatorName,
        'routeStops': routeStops,
        'arrivalPoint': arrivalPoint,
        'serviceDate': _date(serviceDate),
        'scheduledArrival': scheduledArrival.toUtc().toIso8601String(),
        'estimatedArrival': null,
        'actualArrival': null,
        'isCancelled': false,
        'dataQuality': dataQuality.name,
        'lastUpdated': lastUpdated.toUtc().toIso8601String(),
        'sourceTimestamp': sourceTimestamp?.toUtc().toIso8601String(),
      };
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What the app is told about each source.
class SourceStatus {
  const SourceStatus({
    required this.id,
    required this.name,
    required this.types,
    required this.url,
    required this.connection,
    required this.message,
    this.fetchedAt,
    this.validFrom,
    this.validTo,
    this.serviceCount = 0,
  });

  final String id;
  final String name;
  final List<TransportKind> types;
  final String url;
  final SourceConnection connection;

  /// Human-readable detail: caveats, or why the source is unavailable. Never
  /// contains secrets.
  final String message;
  final DateTime? fetchedAt;

  /// Period the source says its data is valid for, when it says so.
  final DateTime? validFrom;
  final DateTime? validTo;

  /// Services produced in the response window.
  final int serviceCount;

  SourceStatus copyWith({
    SourceConnection? connection,
    String? message,
    int? serviceCount,
    DateTime? fetchedAt,
  }) =>
      SourceStatus(
        id: id,
        name: name,
        types: types,
        url: url,
        connection: connection ?? this.connection,
        message: message ?? this.message,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        validFrom: validFrom,
        validTo: validTo,
        serviceCount: serviceCount ?? this.serviceCount,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'types': [for (final t in types) t.name],
        'url': url,
        'status': switch (connection) {
          SourceConnection.connected => 'connected',
          SourceConnection.scheduledOnly => 'scheduledOnly',
          SourceConnection.unavailable => 'unavailable',
          SourceConnection.awaitingCredentials => 'awaitingCredentials',
        },
        'message': message,
        'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
        'validFrom': validFrom == null ? null : _date(validFrom!),
        'validTo': validTo == null ? null : _date(validTo!),
        'serviceCount': serviceCount,
      };
}

/// A day range (inclusive, as UTC-midnight dates) and the weekdays a service
/// runs within it (`DateTime.monday`..`DateTime.sunday`; null means daily).
class CalendarEntry {
  const CalendarEntry({required this.from, required this.to, this.weekdays});

  final DateTime from;
  final DateTime to;
  final Set<int>? weekdays;

  bool covers(DateTime serviceDate) {
    if (serviceDate.isBefore(from) || serviceDate.isAfter(to)) return false;
    return weekdays == null || weekdays!.contains(serviceDate.weekday);
  }
}

/// A recurring scheduled arrival in Suceava, before it is expanded into dated
/// services.
class SchedulePattern {
  const SchedulePattern({
    required this.serviceNumber,
    required this.routeStops,
    required this.arrivalPoint,
    required this.arrivalMinutes,
    required this.calendar,
    this.operatorName,
    this.sourceUrl,
  });

  final String serviceNumber;
  final String? operatorName;
  final List<String> routeStops;
  final String arrivalPoint;

  /// Minutes after Bucharest midnight of the service date; 1440 or more means
  /// the arrival falls on a later day.
  final int arrivalMinutes;
  final List<CalendarEntry> calendar;

  /// Overrides the source's page URL for this pattern.
  final String? sourceUrl;
}

/// Static facts about a source.
class SourceDescriptor {
  const SourceDescriptor({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
  });

  final String id;
  final String name;
  final TransportKind kind;
  final String url;
}

/// Expands recurring patterns into dated services inside `[from, to]`.
List<NormalizedService> expandPatterns({
  required SourceDescriptor source,
  required List<SchedulePattern> patterns,
  required DateTime from,
  required DateTime to,
  required DateTime fetchedAt,
  DateTime? sourceTimestamp,
}) {
  final result = <NormalizedService>[];
  // The same service must never appear twice (overlapping patterns).
  final seen = <String>{};
  // Service dates start up to 3 days before the window because a long journey
  // can arrive days after its operating day began.
  final firstDay = BucharestTime.serviceDateOf(
    from,
  ).subtract(const Duration(days: 3));
  final lastDay = BucharestTime.serviceDateOf(to);

  for (var day = firstDay;
      !day.isAfter(lastDay);
      day = DateTime.utc(day.year, day.month, day.day + 1)) {
    for (final pattern in patterns) {
      if (!pattern.calendar.any((c) => c.covers(day))) continue;
      final dayOffset = pattern.arrivalMinutes ~/ 1440;
      final minuteOfDay = pattern.arrivalMinutes % 1440;
      final arrival = BucharestTime.fromWallClock(
        day.year,
        day.month,
        day.day + dayOffset,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );
      if (arrival.isBefore(from) || arrival.isAfter(to)) continue;
      final id = _serviceId(source, pattern, day, minuteOfDay);
      if (!seen.add(id)) continue;
      result.add(
        NormalizedService(
          id: id,
          type: source.kind,
          sourceId: source.id,
          sourceName: source.name,
          sourceUrl: pattern.sourceUrl ?? source.url,
          serviceNumber: pattern.serviceNumber,
          operatorName: pattern.operatorName,
          routeStops: pattern.routeStops,
          arrivalPoint: pattern.arrivalPoint,
          serviceDate: day,
          scheduledArrival: arrival,
          lastUpdated: fetchedAt,
          sourceTimestamp: sourceTimestamp,
        ),
      );
    }
  }
  result.sort((a, b) => a.scheduledArrival.compareTo(b.scheduledArrival));
  return result;
}

String _serviceId(
  SourceDescriptor source,
  SchedulePattern pattern,
  DateTime day,
  int minuteOfDay,
) {
  String slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final hhmm = '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}'
      '${(minuteOfDay % 60).toString().padLeft(2, '0')}';
  return '${source.id}:${slug(pattern.serviceNumber)}:${_date(day)}:'
      '${slug(pattern.arrivalPoint)}:$hhmm';
}
