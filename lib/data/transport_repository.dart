import '../domain/transport_service.dart';

/// Result of one fetch from a transport source.
class TransportSnapshot {
  const TransportSnapshot({
    required this.services,
    required this.fetchedAt,
    required this.isMock,
  });

  final List<TransportService> services;
  final DateTime fetchedAt;

  /// True when the data is generated demo data, not a real source.
  final bool isMock;
}

class TransportFetchException implements Exception {
  const TransportFetchException(this.message, {this.isOffline = false});

  /// Safe to show to users; never contains secrets or backend details.
  final String message;
  final bool isOffline;

  @override
  String toString() => 'TransportFetchException: $message';
}

/// Source of upcoming arrivals in Suceava. Real provider adapters (airport,
/// CFR, coaches) implement this and keep all parsing out of the UI.
abstract interface class TransportRepository {
  Future<TransportSnapshot> fetchUpcomingArrivals();
}
