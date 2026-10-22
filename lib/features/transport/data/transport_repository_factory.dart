import 'package:http/http.dart' as http;

import '../../../core/clock.dart';
import 'mock_transport_repository.dart';
import 'remote_transport_repository.dart';
import 'sources/provider_config.dart';
import 'transport_repository.dart';

/// Picks the data source from build-time configuration.
///
/// * No backend URL: demo data only, every service marked as such.
/// * A valid backend URL: real data from the backend, with the demo data as an
///   explicit fallback when the backend cannot be reached.
TransportRepository createTransportRepository(
  ProviderConfig config, {
  Clock clock = systemClock,
  http.Client? client,
}) {
  final mock = MockTransportRepository(clock: clock);
  final base = config.apiBaseUrl;
  if (base == null) return mock;
  return FallbackTransportRepository(
    primary: RemoteTransportRepository(
      baseUrl: base,
      client: client,
      now: clock,
    ),
    fallback: mock,
  );
}
