import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../transport/data/sources/source_catalog.dart';
import '../../transport/presentation/styles.dart';

/// States plainly that no real data source is connected and where each
/// candidate source stands.
class DataSourcesCard extends StatelessWidget {
  const DataSourcesCard({super.key});

  static String statusLabel(IntegrationStatus status) => switch (status) {
    IntegrationStatus.verified => Strings.sourceVerified,
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              Strings.dataSourcesIntro,
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final source in DataSourceCatalog.all)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(source.type.icon, size: 20, color: source.type.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${statusLabel(source.status)} · '
                            '${natureLabel(source.nature)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
