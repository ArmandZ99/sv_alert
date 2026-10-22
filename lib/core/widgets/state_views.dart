import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Spinner with a message. When [slow] is set (the first load has taken long)
/// it adds the likely cause: a hosted server waking from idle. No progress
/// figure or countdown is shown, because the wait cannot be predicted.
class LoadingView extends StatelessWidget {
  const LoadingView({this.slow = false, super.key});

  final bool slow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            Strings.loading,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          if (slow) ...[
            const SizedBox(height: 12),
            const Text(
              Strings.loadingSlow,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              Strings.loadingSlowNote,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Generic centered message with an optional action, used for empty, error and
/// offline states.
class MessageView extends StatelessWidget {
  const MessageView({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.muted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
