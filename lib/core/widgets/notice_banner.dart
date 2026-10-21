import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Warning-style banner for demo data, stale data and failed refreshes.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.action,
    super.key,
  });

  /// The standing "this is mock data" banner.
  const NoticeBanner.mock({super.key})
    : title = Strings.mockBannerTitle,
      body = Strings.mockBannerBody,
      icon = Icons.science_outlined,
      action = null;

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.mockBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.mockBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.mockText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.mockText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppColors.mockText,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 4), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
