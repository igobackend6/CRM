import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// The white, bordered, 44px-high box the Analytics screens put dropdowns
/// and the period button in (matching the reference's filter row).
class AnalyticsFilterBox extends StatelessWidget {
  const AnalyticsFilterBox({super.key, required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: child,
    );
  }
}
