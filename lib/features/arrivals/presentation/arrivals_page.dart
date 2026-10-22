import 'package:flutter/material.dart';

import '../../transport/domain/transport_type.dart';
import '../../../core/l10n/strings.dart';
import 'arrivals_controller.dart';
import '../../settings/presentation/preferences_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'arrival_card.dart';
import 'freshness_banners.dart';
import '../../../core/widgets/state_views.dart';
import '../../transport/presentation/styles.dart';
import 'service_details_sheet.dart';

class ArrivalsPage extends StatefulWidget {
  const ArrivalsPage({
    required this.arrivals,
    required this.preferences,
    super.key,
  });

  final ArrivalsController arrivals;
  final PreferencesController preferences;

  @override
  State<ArrivalsPage> createState() => _ArrivalsPageState();
}

class _ArrivalsPageState extends State<ArrivalsPage> {
  late final TextEditingController _search = TextEditingController(
    text: widget.arrivals.filter.query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arrivals = widget.arrivals;
    return RefreshIndicator(
      onRefresh: arrivals.refresh,
      child: ListenableBuilder(
        listenable: Listenable.merge([arrivals, widget.preferences]),
        builder: (context, _) {
          final now = arrivals.now;
          final results = arrivals.filtered;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    Strings.arrivalsTitle,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    Strings.arrivalsSubtitle,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: FreshnessBanners(controller: arrivals),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(child: _searchField(arrivals)),
              ),
              SliverToBoxAdapter(child: _filterChips(arrivals)),
              if (arrivals.snapshot == null)
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
                )
              else if (arrivals.allServices.isEmpty)
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
              else if (results.isEmpty)
                SliverToBoxAdapter(
                  child: MessageView(
                    icon: Icons.search_off,
                    title: Strings.noResultsTitle,
                    actionLabel: Strings.clearFilters,
                    onAction: () {
                      _search.clear();
                      arrivals.clearFilters();
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final service = results[index];
                      return ArrivalCard(
                        service: service,
                        now: now,
                        followed: widget.preferences.value.isFollowingService(
                          service.id,
                        ),
                        onTap: () => showServiceDetails(
                          context,
                          service: service,
                          now: now,
                          preferences: widget.preferences,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField(ArrivalsController arrivals) {
    return TextField(
      controller: _search,
      onChanged: arrivals.setQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: Strings.searchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: arrivals.filter.query.isEmpty
            ? null
            : IconButton(
                tooltip: Strings.clearSearch,
                icon: const Icon(Icons.close),
                onPressed: () {
                  _search.clear();
                  arrivals.setQuery('');
                },
              ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _filterChips(ArrivalsController arrivals) {
    final options = <(TransportType?, String, IconData)>[
      (null, Strings.filterAll, Icons.view_agenda_outlined),
      for (final type in TransportType.values)
        (type, type.filterLabel, type.icon),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (type, label, icon) in options)
            FilterChip(
              selected: arrivals.filter.type == type,
              avatar: Icon(icon, size: 17),
              label: Text('$label (${arrivals.countFor(type)})'),
              onSelected: (_) => arrivals.setType(type),
            ),
        ],
      ),
    );
  }
}
