import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../transport/data/sources/source_catalog.dart';
import '../../transport/data/sources/source_status.dart';
import '../../transport/presentation/styles.dart';

/// Where every data source stands. With the backend connected it shows each
/// source's live state; otherwise it shows the researched catalog and says
/// that no real source is connected.
class DataSourcesCard extends StatelessWidget {
  const DataSourcesCard({this.live = const [], super.key});

  /// Status reported by the backend, empty when running on demo data.
  final List<SourceStatusInfo> live;

  static String statusLabel(IntegrationStatus status) => switch (status) {
    IntegrationStatus.verified => Strings.sourceVerified,
    IntegrationStatus.implementedScheduledOnly =>
      Strings.sourceImplementedScheduled,
    IntegrationStatus.awaitingCredentials => Strings.sourceAwaitingCredentials,
    IntegrationStatus.awaitingPermission => Strings.sourceAwaitingPermission,
    IntegrationStatus.awaitingVerification =>
      Strings.sourceAwaitingVerification,
    IntegrationStatus.unavailable => Strings.sourceUnavailable,
  };

  static String natureLabel(SourceNature nature) => switch (nature) {
    SourceNature.scheduledOnly => Strings.sourceScheduledOnly,
    SourceNature.liveEstimated => Strings.sourceLiveClaimed,
    SourceNature.unknown => Strings.sourceNatureUnknown,
  };

  static String connectionLabel(SourceConnection connection) =>
      switch (connection) {
        SourceConnection.connected => Strings.sourceConnected,
        SourceConnection.scheduledOnly => Strings.sourceScheduledOnlyLive,
        SourceConnection.unavailable => Strings.sourceUnavailable,
        SourceConnection.awaitingCredentials =>
          Strings.sourceAwaitingCredentials,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              live.isEmpty
                  ? Strings.dataSourcesIntro
                  : Strings.dataSourcesLiveIntro,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (live.isEmpty)
              for (final source in DataSourceCatalog.all)
                _Row(
                  icon: source.type.icon,
                  color: source.type.color,
                  name: source.name,
                  status:
                      '${statusLabel(source.status)} · '
                      '${natureLabel(source.nature)}',
                )
            else
              for (final source in live)
                _Row(
                  icon: Icons.sync_alt,
                  color: AppColors.neutral,
                  name: source.name,
                  status:
                      '${connectionLabel(source.connection)}'
                      '${source.serviceCount > 0 ? ' · ${source.serviceCount} curse' : ''}',
                  detail: source.message,
                ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.name,
    required this.status,
    this.detail = '',
  });

  final IconData icon;
  final Color color;
  final String name;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  status,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
