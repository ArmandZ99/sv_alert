import '../../transport/domain/transport_service.dart';
import '../../transport/domain/transport_type.dart';

/// Type filter plus free-text search over service number, operator, route and
/// arrival point. Matching ignores case, spaces and Romanian diacritics.
class ServiceFilter {
  const ServiceFilter({this.type, this.query = ''});

  final TransportType? type;
  final String query;

  bool get isActive => type != null || query.trim().isNotEmpty;

  ServiceFilter copyWith({
    TransportType? type,
    bool clearType = false,
    String? query,
  }) => ServiceFilter(
    type: clearType ? null : (type ?? this.type),
    query: query ?? this.query,
  );

  bool matches(TransportService service) {
    if (type != null && service.type != type) return false;
    final needle = _normalize(query);
    if (needle.isEmpty) return true;
    final haystack = _normalize(
      [
        service.serviceNumber,
        if (service.operatorName != null) service.operatorName!,
        ...service.routeStops,
        service.arrivalPoint,
      ].join(' '),
    );
    return haystack.contains(needle);
  }

  /// Matching services sorted by best known arrival time.
  List<TransportService> apply(Iterable<TransportService> services) =>
      services.where(matches).toList()
        ..sort((a, b) => a.effectiveArrival.compareTo(b.effectiveArrival));
}

String _normalize(String input) {
  const map = {
    'ă': 'a',
    'â': 'a',
    'î': 'i',
    'ș': 's',
    'ş': 's',
    'ț': 't',
    'ţ': 't',
  };
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) continue;
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}
