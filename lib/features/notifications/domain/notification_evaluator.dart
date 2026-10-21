import '../../transport/domain/arrival_status.dart';
import '../../settings/domain/notification_preferences.dart';
import '../../transport/domain/transport_service.dart';

enum AlertKind { arrivalReminder, significantDelay }

/// A notification that should be sent. Producing it sends nothing: delivery is
/// not implemented yet.
class AlertEvent {
  const AlertEvent({
    required this.key,
    required this.service,
    required this.kind,
    required this.thresholdMinutes,
    this.minutesUntil,
    this.delayMinutes,
    this.isScheduleBased = false,
  });

  /// Idempotency key: service id (includes the service date), kind and
  /// threshold. The same key must never be notified twice.
  final String key;
  final TransportService service;
  final AlertKind kind;
  final int thresholdMinutes;

  /// Set for arrival reminders.
  final int? minutesUntil;

  /// Set for delay alerts.
  final int? delayMinutes;

  /// True when an arrival reminder rests on the timetable only (no estimate),
  /// so wording must not present it as a live prediction.
  final bool isScheduleBased;
}

class EvaluationResult {
  const EvaluationResult({required this.events, required this.keysToRecord});

  static const empty = EvaluationResult(events: [], keysToRecord: {});

  /// Alerts to send now.
  final List<AlertEvent> events;

  /// Keys the caller must store as handled: the events' keys plus reminder
  /// thresholds that were skipped because a tighter one applied. Pass them back
  /// as `alreadyHandled` on the next evaluation.
  final Set<String> keysToRecord;
}

/// Pure decision logic: given the current services, the user's preferences and
/// the keys already handled, decide which alerts to raise.
///
/// Policy:
/// * Nothing fires when notifications are off, for unfollowed types/services
///   (when specific services are followed, only those count), for cancelled,
///   arrived or already-passed services, or when the data is stale.
/// * Arrival reminder: fires once the time left is at or below a threshold.
///   If several thresholds are already crossed (first seen late), only the
///   tightest one fires and the looser ones are recorded without alerting.
/// * Delay alert: fires once when the delay first reaches the threshold, and
///   only from an estimate that really exists (estimated or live data). A
///   timetable alone never produces a delay alert. Later ETA changes do not
///   re-alert.
/// * Quiet hours are not applied here; delivery will enforce them.
abstract final class NotificationEvaluator {
  /// Data last fetched longer ago than this is ignored.
  static const Duration defaultStaleAfter = Duration(minutes: 10);

  static EvaluationResult evaluate({
    required Iterable<TransportService> services,
    required NotificationPreferences preferences,
    required DateTime now,
    Set<String> alreadyHandled = const {},
    Duration staleAfter = defaultStaleAfter,
  }) {
    if (!preferences.enabled) return EvaluationResult.empty;

    final events = <AlertEvent>[];
    final record = <String>{};
    final thresholds = [...preferences.reminderMinutes]..sort();

    for (final service in services) {
      if (!_eligible(service, preferences, now, staleAfter)) continue;

      if (preferences.arrivalAlertsEnabled) {
        final minutes = service.minutesUntil(now);
        final crossed = thresholds.where((t) => minutes <= t).toList();
        if (crossed.isNotEmpty) {
          for (final t in crossed) {
            record.add(_key(service, AlertKind.arrivalReminder, t));
          }
          final tightest = crossed.first;
          final key = _key(service, AlertKind.arrivalReminder, tightest);
          if (!alreadyHandled.contains(key)) {
            events.add(
              AlertEvent(
                key: key,
                service: service,
                kind: AlertKind.arrivalReminder,
                thresholdMinutes: tightest,
                minutesUntil: minutes,
                isScheduleBased: !_hasRealEstimate(service),
              ),
            );
          }
        }
      }

      if (preferences.delayAlertsEnabled && _hasRealEstimate(service)) {
        final delay = service.delayMinutes ?? 0;
        final threshold = preferences.delayThresholdMinutes;
        if (delay >= threshold) {
          final key = _key(service, AlertKind.significantDelay, threshold);
          record.add(key);
          if (!alreadyHandled.contains(key)) {
            events.add(
              AlertEvent(
                key: key,
                service: service,
                kind: AlertKind.significantDelay,
                thresholdMinutes: threshold,
                delayMinutes: delay,
              ),
            );
          }
        }
      }
    }

    return EvaluationResult(
      events: events,
      keysToRecord: {...record, ...events.map((e) => e.key)},
    );
  }

  static bool _eligible(
    TransportService service,
    NotificationPreferences preferences,
    DateTime now,
    Duration staleAfter,
  ) {
    if (!preferences.followedTypes.contains(service.type)) return false;
    if (preferences.followedServiceIds.isNotEmpty &&
        !preferences.isFollowingService(service.id)) {
      return false;
    }
    if (service.isCancelled || service.actualArrival != null) return false;
    if (now.difference(service.lastUpdated) > staleAfter) return false;
    if (service.minutesUntil(now) < 0) return false;
    return true;
  }

  static bool _hasRealEstimate(TransportService service) =>
      service.estimatedArrival != null &&
      (service.dataQuality == DataQuality.estimated ||
          service.dataQuality == DataQuality.live);

  static String _key(TransportService s, AlertKind kind, int threshold) =>
      '${s.id}|${kind.name}|$threshold';
}
