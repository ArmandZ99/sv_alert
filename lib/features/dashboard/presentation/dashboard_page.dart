import 'package:flutter/material.dart';

import '../../transport/domain/transport_service.dart';
import '../../../core/l10n/strings.dart';
import '../../arrivals/presentation/arrivals_controller.dart';
import '../../settings/presentation/preferences_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../arrivals/presentation/arrival_card.dart';
import 'demand_card.dart';
import '../../arrivals/presentation/freshness_banners.dart';
import '../../../core/widgets/state_views.dart';
import '../../arrivals/presentation/service_details_sheet.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.arrivals,
    required this.preferences,
    required this.onOpenArrivals,
    required this.onOpenSettings,
    super.key,
  });

  final ArrivalsController arrivals;
  final PreferencesController preferences;
  final VoidCallback onOpenArrivals;
  final VoidCallback onOpenSettings;

  static const int previewCount = 4;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: arrivals.refresh,
      child: ListenableBuilder(
        listenable: Listenable.merge([arrivals, preferences]),
        builder: (context, _) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _Header(onOpenSettings: onOpenSettings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: FreshnessBanners(controller: arrivals),
              ),
            ),
            ..._body(context),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Text(
                  Strings.independentNotice,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    if (arrivals.snapshot == null) {
      return [
        SliverToBoxAdapter(
          child: arrivals.status == LoadStatus.error
              ? MessageView(
                  icon: arrivals.error?.isOffline == true
                      ? Icons.wifi_off
                      : Icons.error_outline,
                  title: arrivals.error?.isOffline == true
                      ? Strings.offlineTitle
                      : Strings.errorTitle,
                  body: arrivals.error?.message,
                  actionLabel: Strings.retry,
                  onAction: arrivals.refresh,
                )
              : LoadingView(slow: arrivals.isSlowLoad),
        ),
      ];
    }

    final now = arrivals.now;
    final upcoming = arrivals.upcoming;
    final preview = upcoming.take(previewCount).toList();

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverToBoxAdapter(
          child: DemandCard(overview: arrivals.demand),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  Strings.nextArrivals,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: onOpenArrivals,
                child: const Text(Strings.seeAll),
              ),
            ],
          ),
        ),
      ),
      if (preview.isEmpty)
        SliverToBoxAdapter(
          child: arrivals.noSourceAvailable
              ? const MessageView(
                  icon: Icons.cloud_off_outlined,
                  title: Strings.noSourcesTitle,
                  body: Strings.noSourcesBody,
                )
              : const MessageView(
                  icon: Icons.event_busy_outlined,
                  title: Strings.emptyTitle,
                  body: Strings.emptyBody,
                ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          sliver: SliverList.separated(
            itemCount: preview.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _card(context, preview[index], now),
          ),
        ),
    ];
  }

  Widget _card(BuildContext context, TransportService service, DateTime now) {
    return ArrivalCard(
      service: service,
      now: now,
      followed: preferences.value.isFollowingService(service.id),
      onTap: () => showServiceDetails(
        context,
        service: service,
        now: now,
        preferences: preferences,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Strings.appName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 2),
              Text(
                Strings.appTagline,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onOpenSettings,
          tooltip: Strings.settingsTooltip,
          icon: const Icon(Icons.notifications_active_outlined),
        ),
      ],
    );
  }
}
