import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A titled, collapsible group of form fields — the "Personal
/// Information / Custom Fields / Priority / Others" grouped-section
/// pattern from the real Runo app (docs/design/design-tokens.md),
/// wrapping the stock [ExpansionTile] in the app's own card styling
/// (via `CardTheme` — see `AppTheme`) so it reads as one of this app's
/// sections rather than a bare Material default.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({super.key, required this.title, required this.children, this.initiallyExpanded = false});

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        // ExpansionTile paints a divider above/below its expanded body by
        // default — the card's own border already does that job.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
