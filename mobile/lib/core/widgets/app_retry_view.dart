import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Centered "something went wrong" + Retry button — replaces the
/// message+OutlinedButton column that used to be duplicated, near
/// verbatim, across every list screen's error state (`_ErrorView`,
/// four copies) and every detail screen's error state (four more,
/// inline in `_buildBody`'s `case ...Status.error`).
class AppRetryView extends StatelessWidget {
  const AppRetryView({super.key, required this.message, required this.onRetry, this.icon = Icons.error_outline});

  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
