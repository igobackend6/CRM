import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A short warning with one action, for the call-sync settings screens ("set this up first",
/// "notifications are off").
class SetupNotice extends StatelessWidget {
  const SetupNotice({super.key, required this.icon, required this.text, required this.button, required this.onPressed});

  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
          TextButton(onPressed: onPressed, child: Text(button)),
        ],
      ),
    );
  }
}
