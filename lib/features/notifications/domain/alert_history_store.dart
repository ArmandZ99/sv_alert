/// Persistent record of alert keys that were already handled, with the instant
/// each was handled (absolute time, stored as UTC).
abstract interface class AlertHistoryStore {
  /// Never throws: missing or unreadable data yields an empty history.
  Future<Map<String, DateTime>> load();

  /// Replaces the stored history. May throw if storage fails.
  Future<void> save(Map<String, DateTime> handled);
}
