import 'package:flutter/material.dart';

import '../../domain/arrival_status.dart';
import '../../domain/transport_service.dart';
import '../l10n/formatters.dart';
import '../l10n/strings.dart';
import '../state/preferences_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/notice_banner.dart';
import '../widgets/status_badge.dart';
import '../widgets/styles.dart';

Future<void> showServiceDetails(
  BuildContext context, {
  required TransportService service,
  required DateTime now,
  required PreferencesController preferences,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    builder: (context) => ServiceDetailsSheet(
      service: service,
      now: now,
      preferences: preferences,
    ),
  );
}

class ServiceDetailsSheet extends StatelessWidget {
  const ServiceDetailsSheet({
    required this.service,
    required this.now,
    required this.preferences,
    super.key,
  });

  final TransportService service;
  final DateTime now;
  final PreferencesController preferences;

  @override
  Widget build(BuildContext context) {
    final status = service.statusAt(now);
    final delay = service.delayMinutes;
    final color = service.type.color;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(service.type.icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                service.type.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            service.serviceNumber,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          if (service.operatorName != null)
            Text(
              service.operatorName!,
              style: const TextStyle(color: AppColors.muted),
            ),
          const SizedBox(height: 10),
          StatusBadge(service: service, status: status),
          if (service.source.isMock) ...[
            const SizedBox(height: 14),
            const NoticeBanner.mock(),
          ],
          const SizedBox(height: 18),
          _Section(
            title: Strings.detailsRoute,
            child: _RouteTimeline(stops: service.routeStops),
          ),
          _Section(
            title: Strings.arrivalsTitle,
            child: Column(
              children: [
                _Row(Strings.detailsArrivalPoint, service.arrivalPoint),
                _Row(
                  Strings.detailsServiceDate,
                  formatDate(service.serviceDate),
                ),
                _Row(
                  Strings.scheduledLabel,
                  formatTime(service.scheduledArrival),
                ),
                _Row(
                  Strings.estimatedLabel,
                  service.estimatedArrival == null
                      ? Strings.estimateUnavailable
                      : formatTime(service.estimatedArrival!),
                ),
                if (service.actualArrival != null)
                  _Row(
                    Strings.arrivedAtLabel,
                    formatTime(service.actualArrival!),
                  ),
                _Row(
                  Strings.detailsDelay,
                  delay == null
                      ? Strings.detailsUnavailable
                      : delay > 0
                      ? '+${Strings.minutesShort(delay)}${service.source.isMock ? ' (${Strings.sampleSuffix})' : ''}'
                      : (delay < 0
                            ? '${Strings.minutesShort(delay)} (mai devreme)'
                            : '0 min'),
                ),
                if (status != ArrivalStatus.arrived &&
                    status != ArrivalStatus.cancelled)
                  _Row('Timp rămas', formatUntil(service.minutesUntil(now))),
                _Row(
                  Strings.detailsDelayHistory,
                  Strings.detailsDelayHistoryNone,
                ),
              ],
            ),
          ),
          _Section(
            title: Strings.detailsSource,
            child: Column(
              children: [
                _Row(Strings.detailsDataType, service.dataQuality.label),
                _Row(Strings.detailsSource, service.source.name),
                _Row(
                  Strings.detailsSourceLink,
                  service.source.url ?? Strings.detailsNoLink,
                  selectable: service.source.url != null,
                ),
                _Row(
                  Strings.detailsLastUpdated,
                  formatDateTime(service.lastUpdated),
                ),
                _Row(
                  Strings.detailsSourceTime,
                  service.sourceTimestamp == null
                      ? Strings.detailsUnavailable
                      : formatDateTime(service.sourceTimestamp!),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => Card(
              child: SwitchListTile(
                value: preferences.value.isFollowingService(service.id),
                onChanged: (_) => preferences.toggleFollowedService(service.id),
                title: const Text(
                  Strings.followService,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(Strings.followServiceHint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w900,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.selectable = false});

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: selectable
                ? SelectableText(value, textAlign: TextAlign.end, style: style)
                : Text(value, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({required this.stops});

  final List<String> stops;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 30,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: 2,
                        color: i == 0 ? Colors.transparent : AppColors.border,
                      ),
                    ),
                    Icon(
                      stops[i].contains('Suceava')
                          ? Icons.location_on
                          : Icons.circle,
                      size: stops[i].contains('Suceava') ? 16 : 8,
                      color: stops[i].contains('Suceava')
                          ? AppColors.primary
                          : AppColors.muted,
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: i == stops.length - 1
                            ? Colors.transparent
                            : AppColors.border,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stops[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: stops[i].contains('Suceava')
                        ? FontWeight.w900
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
