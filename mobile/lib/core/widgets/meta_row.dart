import 'package:flutter/material.dart';

/// One icon+text pair for [MetaRow] — e.g. a source, an assignee, a
/// due date. `color` overrides the row's default (muted) tint, e.g. to
/// render an overdue date in the error color.
class MetaItem {
  const MetaItem(this.icon, this.text, {this.color});

  final IconData icon;
  final String text;
  final Color? color;
}

/// A wrapping row of small icon+text pairs — the "Acme Corp Inc |
/// Outgoing Call | 10:51 AM" metadata line pattern used throughout the
/// real app's list tiles and detail screens. `Wrap` (not `Row`) so it
/// reflows onto a second line on a narrow screen instead of overflowing,
/// which the ad hoc `Row`s it replaces did not handle.
class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.items, this.spacing = 16});

  final List<MetaItem> items;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.outline;
    return Wrap(
      spacing: spacing,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 14, color: item.color ?? defaultColor),
              const SizedBox(width: 4),
              Text(item.text, style: theme.textTheme.bodySmall?.copyWith(color: item.color)),
            ],
          ),
      ],
    );
  }
}
