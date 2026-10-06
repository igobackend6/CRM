import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../reports/domain/reports_access.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../../../core/widgets/brand_app_bar.dart';

/// The Analytics landing screen (the floating tab on Home opens it): one
/// row per analytics area. User Performances is team-wide data, so it is
/// dimmed for roles without `reports.read` (same role check as the Reports
/// screen's Team tab) — tapping it explains why instead of navigating to a
/// screen that could only show a permission error.
class AnalyticsHubScreen extends ConsumerWidget {
  const AnalyticsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(workspaceControllerProvider).selected?.roleName;
    final canSeeTeam = canViewTeamReports(role);

    return Scaffold(
      appBar: brandAppBar(title: const Text('Analytics')),
      body: ListView(
        children: [
          _AnalyticsEntry(
            key: const Key('analytics-calls'),
            icon: Icons.phone_in_talk_outlined,
            color: AppColors.accent,
            title: 'Call Analytics',
            description: 'Measure call volume, connection rates, and talk time over selected time periods.',
            onTap: () => context.push(RoutePaths.analyticsCalls),
          ),
          const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
          _AnalyticsEntry(
            key: const Key('analytics-customers'),
            icon: Icons.pie_chart_outline,
            color: AppColors.success,
            title: 'Customer Analytics',
            description: 'Track customer distribution by stage and status with clear funnel management.',
            onTap: () => context.push(RoutePaths.analyticsCustomers),
          ),
          const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
          _AnalyticsEntry(
            key: const Key('analytics-users'),
            icon: Icons.emoji_events_outlined,
            color: AppColors.gold,
            title: 'User Performances',
            description: 'Identify top-performing agents by their call activity and customer engagement.',
            enabled: canSeeTeam,
            onTap: () {
              if (canSeeTeam) {
                context.push(RoutePaths.analyticsUsers);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Manager access is required to view User Performances.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AnalyticsEntry extends StatelessWidget {
  const _AnalyticsEntry({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = enabled ? color : AppColors.textDim;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.standard)),
                child: Icon(icon, size: 30, color: tint),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                        if (!enabled) const Icon(Icons.lock_outline, size: 16, color: AppColors.textDim),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textBody)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
