import '../../settings/domain/notification_preferences.dart';
import '../../transport/domain/transport_service.dart';
import 'alert_history_store.dart';
import 'notification_evaluator.dart';

/// Runs the pure [NotificationEvaluator] against a persistent history so a
/// handled alert stays handled across app restarts. It decides only: nothing
/// is delivered here.
///
/// Delivery semantics are at-most-once. Keys are recorded when an evaluation
/// returns them, before any delivery attempt, so a crash or a failed delivery
/// can lose an alert but can never repeat one.
///
/// Storage failures are tolerated: if loading fails the history starts empty
/// (an alert may repeat once), and if saving fails the in-memory history still
/// suppresses duplicates for the rest of the session.
class AlertEngine {
  AlertEngine({required this.store, this.retention = const Duration(days: 2)});

  /// Handled keys older than this are dropped. Keys include the service date,
  /// so an old key can only matter for a service that is long gone.
  final Duration retention;

  final AlertHistoryStore store;
  final Map<String, DateTime> _handled = {};
  bool _loaded = false;

  /// True if the last attempt to save the history failed.
  bool lastSaveFailed = false;

  Set<String> get handledKeys => Set.unmodifiable(_handled.keys);

  Future<void> load() async {
    _handled.clear();
    try {
      _handled.addAll(await store.load());
    } catch (_) {
      // Unreadable history: start empty rather than blocking all alerts.
    }
    _loaded = true;
  }

  Future<EvaluationResult> evaluate({
    required Iterable<TransportService> services,
    required NotificationPreferences preferences,
    required DateTime now,
    Duration staleAfter = NotificationEvaluator.defaultStaleAfter,
  }) async {
    if (!_loaded) await load();

    final result = NotificationEvaluator.evaluate(
      services: services,
      preferences: preferences,
      now: now,
      alreadyHandled: _handled.keys.toSet(),
      staleAfter: staleAfter,
    );

    final instant = now.toUtc();
    var changed = false;
    for (final key in result.keysToRecord) {
      if (!_handled.containsKey(key)) {
        _handled[key] = instant;
        changed = true;
      }
    }
    final cutoff = instant.subtract(retention);
    final before = _handled.length;
    _handled.removeWhere((_, handledAt) => handledAt.isBefore(cutoff));
    if (_handled.length != before) changed = true;

    if (changed) await _persist();
    return result;
  }

  Future<void> _persist() async {
    try {
      await store.save(Map.of(_handled));
      lastSaveFailed = false;
    } catch (_) {
      lastSaveFailed = true;
    }
  }
}
