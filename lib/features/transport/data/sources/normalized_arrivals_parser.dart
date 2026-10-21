import '../../domain/arrival_status.dart';
import '../../domain/transport_service.dart';
import '../../domain/transport_type.dart';
import '../transport_repository.dart';

/// Result of parsing a normalized payload: the valid services, plus a reason
/// for every service that was rejected (never silently dropped).
class ParsedArrivals {
  const ParsedArrivals({required this.snapshot, required this.rejected});

  final TransportSnapshot snapshot;
  final List<String> rejected;
}

/// Parses the JSON contract (version 1) that a backend serves to the app after
/// it has normalized provider data. Provider-specific parsing (HTML, PDF,
/// vendor JSON) never reaches the app; it belongs behind the backend.
///
/// Contract:
/// ```json
/// {
///   "schemaVersion": 1,
///   "fetchedAt": "2026-10-21T09:00:00Z",
///   "services": [{
///     "id": "...", "type": "flight|train|coach",
///     "source": {"name": "...", "url": null, "isMock": false},
///     "serviceNumber": "...", "operatorName": null,
///     "routeStops": ["origin", "...", "destination"],
///     "arrivalPoint": "...", "serviceDate": "2026-10-21",
///     "scheduledArrival": "...Z", "estimatedArrival": null,
///     "actualArrival": null, "isCancelled": false,
///     "dataQuality": "scheduled|estimated|live|unknown",
///     "lastUpdated": "...Z", "sourceTimestamp": null
///   }]
/// }
/// ```
///
/// Timestamp and honesty rules, enforced here:
/// * Every timestamp carries an explicit offset (`Z` or `+02:00`). A naive
///   "2026-10-21T18:40:00" is rejected because its zone is unknown.
/// * An estimated or actual time is only accepted when `dataQuality` is
///   `estimated` or `live`. A scheduled time can never be passed off as a
///   live estimate.
/// * `fetchedAt` and each `lastUpdated` are required, so freshness is always
///   known.
abstract final class NormalizedArrivalsParser {
  static const int supportedSchemaVersion = 1;

  /// Throws [TransportFetchException] when the payload as a whole is unusable.
  static ParsedArrivals parse(Object? json) {
    if (json is! Map) {
      throw const TransportFetchException('Răspuns neașteptat de la server.');
    }
    if (json['schemaVersion'] != supportedSchemaVersion) {
      throw const TransportFetchException(
        'Versiunea datelor primite nu este suportată.',
      );
    }
    final fetchedAt = _instant(json['fetchedAt']);
    final rawServices = json['services'];
    if (fetchedAt == null || rawServices is! List) {
      throw const TransportFetchException(
        'Răspunsul serverului este incomplet.',
      );
    }

    final services = <TransportService>[];
    final rejected = <String>[];
    for (final (index, raw) in rawServices.indexed) {
      final result = _service(raw);
      if (result.service != null) {
        services.add(result.service!);
      } else {
        rejected.add('services[$index]: ${result.error}');
      }
    }

    return ParsedArrivals(
      snapshot: TransportSnapshot(
        services: services,
        fetchedAt: fetchedAt,
        isMock: services.isNotEmpty && services.every((s) => s.source.isMock),
      ),
      rejected: rejected,
    );
  }

  static ({TransportService? service, String? error}) _service(Object? raw) {
    if (raw is! Map) return (service: null, error: 'not an object');

    final id = _text(raw['id']);
    final number = _text(raw['serviceNumber']);
    final arrivalPoint = _text(raw['arrivalPoint']);
    if (id == null || number == null || arrivalPoint == null) {
      return (
        service: null,
        error: 'missing id, serviceNumber or arrivalPoint',
      );
    }

    final type = TransportType.values.asNameMap()[raw['type']];
    if (type == null) return (service: null, error: 'unknown transport type');

    final quality = DataQuality.values.asNameMap()[raw['dataQuality']];
    if (quality == null) return (service: null, error: 'missing dataQuality');

    final stops = raw['routeStops'];
    if (stops is! List ||
        stops.length < 2 ||
        stops.any((s) => _text(s) == null)) {
      return (
        service: null,
        error: 'route needs at least origin and destination',
      );
    }

    final source = raw['source'];
    final sourceName = source is Map ? _text(source['name']) : null;
    if (sourceName == null) {
      return (service: null, error: 'missing source name');
    }

    final date = _date(raw['serviceDate']);
    final scheduled = _instant(raw['scheduledArrival']);
    final lastUpdated = _instant(raw['lastUpdated']);
    if (date == null || scheduled == null || lastUpdated == null) {
      return (
        service: null,
        error:
            'serviceDate, scheduledArrival and lastUpdated must be valid '
            'with an explicit UTC offset',
      );
    }

    final estimatedRaw = raw['estimatedArrival'];
    final actualRaw = raw['actualArrival'];
    final estimated = estimatedRaw == null ? null : _instant(estimatedRaw);
    final actual = actualRaw == null ? null : _instant(actualRaw);
    if ((estimatedRaw != null && estimated == null) ||
        (actualRaw != null && actual == null)) {
      return (service: null, error: 'invalid estimated/actual timestamp');
    }
    final live =
        quality == DataQuality.estimated || quality == DataQuality.live;
    if ((estimated != null || actual != null) && !live) {
      return (
        service: null,
        error: 'estimated/actual time given for $quality data',
      );
    }

    final sourceTimestampRaw = raw['sourceTimestamp'];
    final sourceTimestamp = sourceTimestampRaw == null
        ? null
        : _instant(sourceTimestampRaw);
    if (sourceTimestampRaw != null && sourceTimestamp == null) {
      return (service: null, error: 'invalid sourceTimestamp');
    }

    return (
      service: TransportService(
        id: id,
        type: type,
        source: SourceInfo(
          name: sourceName,
          url: _text((source as Map)['url']),
          isMock: source['isMock'] == true,
        ),
        serviceNumber: number,
        operatorName: _text(raw['operatorName']),
        routeStops: [for (final s in stops) _text(s)!],
        arrivalPoint: arrivalPoint,
        serviceDate: date,
        scheduledArrival: scheduled,
        estimatedArrival: estimated,
        actualArrival: actual,
        isCancelled: raw['isCancelled'] == true,
        dataQuality: quality,
        lastUpdated: lastUpdated,
        sourceTimestamp: sourceTimestamp,
      ),
      error: null,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static final RegExp _offset = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

  /// An ISO-8601 instant with an explicit offset, converted to UTC.
  static DateTime? _instant(Object? value) {
    if (value is! String || !_offset.hasMatch(value)) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  /// `yyyy-MM-dd` as a UTC-midnight calendar date.
  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final date = DateTime.utc(parsed.year, parsed.month, parsed.day);
    // Reject impossible dates such as 2026-02-30 that parse by rolling over.
    return value == date.toIso8601String().substring(0, 10) ? date : null;
  }
}
