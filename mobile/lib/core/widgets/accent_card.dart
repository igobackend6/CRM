import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// A card with a colored left accent stripe — the real "Call Summary"
/// card's own signature (a rainbow-gradient left border in the source
/// screenshot; a single semantic color here, since this app doesn't
/// have a matching multi-hue meaning to reuse it for — see
/// docs/design/design-tokens.md). Used for a detail screen's header
/// identity block (name + avatar + primary status).
class AccentCard extends StatelessWidget {
  const AccentCard({super.key, required this.child, this.accentColor, this.padding = const EdgeInsets.all(AppSpacing.md)});

  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}
