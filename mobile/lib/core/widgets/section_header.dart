import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// A section title with a small colored icon badge — the "AI CALL
/// SUMMARIES"-style icon+heading pattern from the real Runo UI
/// (docs/design/design-tokens.md), used here for every detail-screen
/// section (Tags, Documents, Assignment history, Follow-ups, Calls,
/// Activity, ...) instead of a bare `Text(title, style: titleMedium)`.
/// `action` is the section's own button (e.g. "Add follow-up"), kept
/// inline the way it already was rather than moved to a second row.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.icon, required this.title, this.iconColor, this.action});

  final IconData icon;
  final String title;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.secondary;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.standard * 0.67)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ?action,
      ],
    );
  }
}
