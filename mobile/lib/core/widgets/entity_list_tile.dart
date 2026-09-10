import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'initials_avatar.dart';
import 'meta_row.dart';

/// A list-tile shape shared by the lead list and follow-up list (Runo's
/// own list rows: an avatar, a title + status chip, and a wrapping row
/// of small metadata — "Acme Corp Inc | Outgoing Call | 10:51 AM") —
/// replaces the near-identical, independently hand-built `_LeadTile`/
/// `_FollowUpTile` compositions. `CallTile` (calls feature) is
/// deliberately not migrated onto this: its leading element is a
/// direction icon, not a person avatar, which existing tests assert on
/// by exact `Icon` identity (`find.byIcon(Icons.call_made)`).
class EntityListTile extends StatelessWidget {
  const EntityListTile({
    super.key,
    required this.avatarName,
    required this.title,
    required this.onTap,
    this.trailing,
    this.subtitle,
    this.metaItems = const [],
    this.trailingMeta,
  });

  final String avatarName;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitle;
  final List<MetaItem> metaItems;
  final String? trailingMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(name: avatarName),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                      ?trailing,
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle!, style: theme.textTheme.bodyMedium),
                  ],
                  if (metaItems.isNotEmpty || trailingMeta != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(child: MetaRow(items: metaItems)),
                        if (trailingMeta != null) Text(trailingMeta!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
