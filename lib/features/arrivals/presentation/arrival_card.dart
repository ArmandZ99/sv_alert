import 'package:flutter/material.dart';

import '../../transport/domain/arrival_status.dart';
import '../../transport/domain/transport_service.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../transport/presentation/status_badge.dart';
import '../../transport/presentation/styles.dart';

class ArrivalCard extends StatelessWidget {
  const ArrivalCard({
    required this.service,
    required this.now,
    required this.onTap,
    this.followed = false,
    super.key,
  });

  final TransportService service;
  final DateTime now;
  final VoidCallback onTap;
  final bool followed;

  @override
  Widget build(BuildContext context) {
    final status = service.statusAt(now);
    final color = service.type.color;
    final hasEstimate = service.estimatedArrival != null;
    final arrived = service.actualArrival != null;
    final changed =
        hasEstimate &&
        service.estimatedArrival!
                .difference(service.scheduledArrival)
                .inMinutes !=
            0;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(service.type.icon, color: color, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.type.label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          service.serviceNumber,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (service.operatorName != null)
                          Text(
                            service.operatorName!,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          service.routeStops.join(' → '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.neutral,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (followed)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 20,
                        color: AppColors.warning,
                        semanticLabel: 'Urmărită',
                      ),
                    ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _TimeBlock(
                      label: Strings.scheduledLabel,
                      value: formatTime(service.scheduledArrival),
                      strike: changed,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _TimeBlock(
                      label: arrived
                          ? Strings.arrivedAtLabel
                          : Strings.estimatedLabel,
                      value: hasEstimate || arrived
                          ? formatTime(service.effectiveArrival)
                          : Strings.noValue,
                      caption: hasEstimate || arrived
                          ? null
                          : Strings.estimateUnavailable,
                      emphasized: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(service: service, status: status),
                  if (status != ArrivalStatus.arrived &&
                      status != ArrivalStatus.cancelled)
                    Text(
                      formatUntil(service.minutesUntil(now)),
                      style: const TextStyle(
                        color: AppColors.neutral,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      service.arrivalPoint,
                      style: const TextStyle(
                        color: AppColors.neutral,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(service.dataQuality.label),
                  if (service.source.isMock)
                    const _Tag(Strings.mockBadge, highlight: true)
                  else
                    _Tag(service.source.name),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.strike = false,
    this.caption,
  });

  final String label;
  final String value;
  final bool emphasized;
  final bool strike;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 30 : 18,
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            color: emphasized ? AppColors.ink : AppColors.neutral,
            decoration: strike ? TextDecoration.lineThrough : null,
            height: 1.1,
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? AppColors.mockBackground : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? AppColors.mockBorder : AppColors.border,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: highlight ? AppColors.mockText : AppColors.neutral,
        ),
      ),
    );
  }
}
