/// State of one data source as reported by the backend.
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

class SourceStatusInfo {
  const SourceStatusInfo({
    required this.id,
    required this.name,
    required this.connection,
    required this.message,
    this.serviceCount = 0,
    this.fetchedAt,
  });

  final String id;
  final String name;
  final SourceConnection connection;

  /// Explanation from the backend (caveats, or why it is unavailable).
  final String message;

  /// Services this source contributed to the current response.
  final int serviceCount;

  /// When the backend last fetched the source.
  final DateTime? fetchedAt;

  /// Whether this source can contribute services at all right now.
  bool get providesData =>
      connection == SourceConnection.connected ||
      connection == SourceConnection.scheduledOnly;
}
