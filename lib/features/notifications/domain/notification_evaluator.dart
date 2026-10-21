import '../../settings/domain/notification_preferences.dart';
import '../../transport/domain/arrival_status.dart';
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

  /// Idempotency key, see [AlertKeys.of]. The same key is never notified twice.
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

/// Builds the stable idempotency key of an alert.
abstract final class AlertKeys {
  /// `<service id>|<service date>|<kind>|<threshold>`, for example
  /// `ir1831|2026-10-21|arrivalReminder|15`.
  ///
  /// The service date is part of the key even if the id already contains it,
  /// so the same train or flight number on another day is another event. The
  /// threshold distinguishes reminders; for delay alerts it is the user's
  /// delay threshold, so changing the setting is a new, separate event.
  static String of(TransportService service, AlertKind kind, int threshold) {
    final d = service.serviceDate;
    final date =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return '${service.id}|$date|${kind.name}|$threshold';
  }
}

class EvaluationResult {
  const EvaluationResult({
    required this.events,
    required this.keysToRecord,
    this.suppressedByQuietHours = const [],
    this.deferredByQuietHours = const [],
  });

  static const empty = EvaluationResult(events: [], keysToRecord: {});

  /// Alerts to send now.
  final List<AlertEvent> events;

  /// Keys the caller must store as handled: the events' keys, reminder
  /// thresholds skipped because a tighter one applied, and reminders dropped by
  /// quiet hours. Pass them back as `alreadyHandled` on the next evaluation.
  final Set<String> keysToRecord;

  /// Arrival reminders dropped because of quiet hours. They are in
  /// [keysToRecord], so they never fire later. Informational only.
  final List<AlertEvent> suppressedByQuietHours;

  /// Delay alerts held back by quiet hours. They are NOT in [keysToRecord]:
  /// they become eligible again on a later evaluation once quiet hours end, if
  /// the service is still relevant. Informational only.
  final List<AlertEvent> deferredByQuietHours;
}

/// Pure decision logic: given the current services, the user's preferences and
/// the keys already handled, decide which alerts to raise.
///
/// Time: every timestamp is an absolute instant. "Minutes until arrival" is a
/// difference of instants, so daylight-saving changes never distort it. Quiet
/// hours are judged on the Europe/Bucharest wall clock (see `BucharestTime`),
/// never on the device's time zone.
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
/// * Quiet hours:
///   - Arrival reminders are time-critical, so during quiet hours they are
///     SUPPRESSED: not sent, and recorded as handled so they do not fire when
///     quiet hours end. A later, tighter threshold still fires normally.
///   - Delay alerts are informational, so they are DEFERRED: not sent and not
///     recorded, so the first evaluation after quiet hours sends them, provided
///     the service is still relevant and still delayed past the threshold.
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

    final quiet = preferences.quietHours.contains(now);
    final events = <AlertEvent>[];
    final suppressed = <AlertEvent>[];
    final deferred = <AlertEvent>[];
    final record = <String>{};
    final thresholds = [...preferences.reminderMinutes]..sort();

    for (final service in services) {
      if (!_eligible(service, preferences, now, staleAfter)) continue;

      if (preferences.arrivalAlertsEnabled) {
        final minutes = service.minutesUntil(now);
        final crossed = thresholds.where((t) => minutes <= t).toList();
        if (crossed.isNotEmpty) {
          for (final t in crossed) {
            record.add(AlertKeys.of(service, AlertKind.arrivalReminder, t));
          }
          final tightest = crossed.first;
          final key = AlertKeys.of(
            service,
            AlertKind.arrivalReminder,
            tightest,
          );
          if (!alreadyHandled.contains(key)) {
            final event = AlertEvent(
              key: key,
              service: service,
              kind: AlertKind.arrivalReminder,
              thresholdMinutes: tightest,
              minutesUntil: minutes,
              isScheduleBased: !_hasRealEstimate(service),
            );
            (quiet ? suppressed : events).add(event);
          }
        }
      }

      if (preferences.delayAlertsEnabled && _hasRealEstimate(service)) {
        final delay = service.delayMinutes ?? 0;
        final threshold = preferences.delayThresholdMinutes;
        if (delay >= threshold) {
          final key = AlertKeys.of(
            service,
            AlertKind.significantDelay,
            threshold,
          );
          if (!alreadyHandled.contains(key)) {
            final event = AlertEvent(
              key: key,
              service: service,
              kind: AlertKind.significantDelay,
              thresholdMinutes: threshold,
              delayMinutes: delay,
            );
            if (quiet) {
              deferred.add(event);
            } else {
              events.add(event);
            }
          }
        }
      }
    }

    return EvaluationResult(
      events: events,
      keysToRecord: {...record, ...events.map((e) => e.key)},
      suppressedByQuietHours: suppressed,
      deferredByQuietHours: deferred,
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
}
