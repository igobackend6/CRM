import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One row of the Settings list: icon, title, an optional current value in the brand colour, and a
/// chevron — the layout of the reference app's settings list.
///
/// A [comingSoon] row is dimmed, shows a "Coming soon" tag, and explains itself when tapped instead
/// of doing nothing silently. Used for options that need phone-level access the app doesn't have yet.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.trailing,
    this.comingSoon = false,
    this.comingSoonHint,
  });

  final IconData icon;
  final String title;

  /// Current choice, shown before the chevron (e.g. "System theme").
  final String? value;
  final VoidCallback? onTap;

  /// Replaces the value + chevron (e.g. a Switch).
  final Widget? trailing;
  final bool comingSoon;
  final String? comingSoonHint;

  void _explainComingSoon(BuildContext context) {
    final hint = comingSoonHint;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(hint == null ? '$title is coming soon.' : '$title is coming soon. $hint')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimmed = comingSoon;

    Widget end;
    if (comingSoon) {
      end = const _ComingSoonTag();
    } else if (trailing != null) {
      end = trailing!;
    } else {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Flexible(
              child: Text(
                value!,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w500),
              ),
            ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurface),
        ],
      );
    }

    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: ListTile(
        minVerticalPadding: 14,
        leading: Icon(icon, color: AppColors.accent, size: 26),
        title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
        trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: Align(alignment: Alignment.centerRight, widthFactor: 1, child: end)),
        onTap: comingSoon ? () => _explainComingSoon(context) : onTap,
      ),
    );
  }
}

class _ComingSoonTag extends StatelessWidget {
  const _ComingSoonTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppColors.goldBg, borderRadius: BorderRadius.circular(20)),
      child: const Text('Coming soon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
    );
  }
}

/// Bottom sheet with one radio per option. Returns the picked option, or null if dismissed.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T) labelOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
          ),
          RadioGroup<T>(
            groupValue: selected,
            onChanged: (value) => Navigator.of(sheetContext).pop(value),
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<T>(
                    value: option,
                    title: Text(labelOf(option)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
