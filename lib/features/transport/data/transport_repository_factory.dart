import 'package:http/http.dart' as http;

import '../../../core/clock.dart';
import 'mock_transport_repository.dart';
import 'remote_transport_repository.dart';
import 'sources/provider_config.dart';
import 'transport_repository.dart';

/// Picks the data source from the central configuration (`AppConfig`).
///
/// * No usable backend URL (empty override, invalid, or still the placeholder):
///   demo data only, every service marked as such.
/// * A valid backend URL: real data from the backend only. When it cannot be
///   reached or read the app shows an error with a retry action; it never
///   swaps in demo data silently.
TransportRepository createTransportRepository(
  ProviderConfig config, {
  Clock clock = systemClock,
  http.Client? client,
}) {
  final base = config.apiBaseUrl;
  if (base == null) return MockTransportRepository(clock: clock);
  return RemoteTransportRepository(baseUrl: base, client: client, now: clock);
}
