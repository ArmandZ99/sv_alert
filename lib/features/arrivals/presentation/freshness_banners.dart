import 'package:flutter/material.dart';

import '../../../core/l10n/formatters.dart';
import '../../../core/l10n/strings.dart';
import 'arrivals_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notice_banner.dart';

/// Data-freshness line plus the mock, stale and failed-refresh banners.
class FreshnessBanners extends StatelessWidget {
  const FreshnessBanners({required this.controller, super.key});

  final ArrivalsController controller;

  @override
  Widget build(BuildContext context) {
    final age = controller.dataAge;
    final error = controller.error;
    final hasData = controller.snapshot != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (age != null)
          Row(
            children: [
              Icon(
                controller.isStale ? Icons.history_toggle_off : Icons.update,
                size: 16,
                color: controller.isStale ? AppColors.warning : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  formatUpdatedAgo(age),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: controller.isStale
                        ? AppColors.warning
                        : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        if (controller.degradedReason != null) ...[
          const SizedBox(height: 10),
          NoticeBanner(
            title: Strings.degradedTitle,
            body: controller.degradedReason!,
            icon: Icons.cloud_off_outlined,
          ),
        ],
        if (controller.hasMock) ...[
          const SizedBox(height: 10),
          controller.hasReal
              ? const NoticeBanner.mixed()
              : const NoticeBanner.mock(),
        ],
        if (controller.hasReal && !controller.hasLiveTimes) ...[
          const SizedBox(height: 10),
          const NoticeBanner.scheduledOnly(),
        ],
        if (hasData && error != null) ...[
          const SizedBox(height: 10),
          NoticeBanner(
            title: error.isOffline ? Strings.offlineTitle : Strings.errorTitle,
            body:
                '${error.message} Se afișează ultimele date primite (${formatAge(age ?? Duration.zero)}).',
            icon: error.isOffline ? Icons.wifi_off : Icons.error_outline,
          ),
        ] else if (controller.isStale) ...[
          const SizedBox(height: 10),
          NoticeBanner(
            title: Strings.staleTitle,
            body:
                'Ultima actualizare a fost ${formatAge(age!)}. Trage în jos pentru a reîncerca.',
            icon: Icons.history_toggle_off,
          ),
        ],
      ],
    );
  }
}
