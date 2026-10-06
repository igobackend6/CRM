import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The small tab pinned to the right edge of Home that opens the
/// Analytics hub — half a pill, flush with the screen edge, so it reads
/// as an edge handle rather than a second FAB competing with the call
/// button. Deliberately a different glyph from the app bar's Reports
/// icon (a plain bar chart): Reports is the KPI tables, this is the
/// trends/funnel hub.
class AnalyticsFloatingTab extends StatelessWidget {
  const AnalyticsFloatingTab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Analytics',
      child: Material(
        color: AppColors.accent,
        elevation: 4,
        shadowColor: AppColors.accent.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 46,
            height: 56,
            child: Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.insights, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
