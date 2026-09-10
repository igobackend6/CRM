import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Centered icon + message for an empty list/section — replaces the
/// plain, icon-less `Text('No X yet.')` scattered across every list and
/// section in the app, and `workspace_selection_screen.dart`'s private
/// `_MessageView` (kept there for its own, more specific icon usage —
/// see that file — but sharing the same visual shape).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
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
          ],
        ),
      ),
    );
  }
}
