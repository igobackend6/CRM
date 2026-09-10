import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// A form-level error banner — replaces the `_ErrorBanner` private
/// widget that used to be duplicated verbatim in the login screen and
/// every create/edit form (lead, follow-up, call). Adds a colored left
/// accent bar (the same device the real "Call Summary" card uses for
/// its highlight — docs/design/design-tokens.md) and the real 12px
/// radius instead of the ad hoc 8px each copy hardcoded.
class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border(left: BorderSide(color: colorScheme.error, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: colorScheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message, style: TextStyle(color: colorScheme.onErrorContainer))),
          ],
        ),
      ),
    );
  }
}
