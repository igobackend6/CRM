import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../reports/domain/entities/team_report.dart';
import '../../../reports/domain/entities/team_report_state.dart';
import '../../../reports/domain/reports_access.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../../reports/presentation/widgets/report_date_range_chips.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/format_talk_time.dart';
import '../widgets/analytics_stat_tile.dart';

String _percent(double rate) => '${(rate * 100).round()}%';

/// Analytics hub → User Performances: the team ranked by conversions, with
/// each agent's calls, connected calls and talk time. Team-wide data, so
/// it needs `reports.read` (manager/admin/ceo); the hub already dims the
/// entry for other roles, and this screen repeats the check so a direct
/// navigation to it degrades to an explanation, not a bare 403.
///
/// Reads the same `teamReportControllerProvider` (and shared date filter)
/// the Reports screen's Team tab does — no second fetch path.
class UserPerformancesScreen extends ConsumerWidget {
  const UserPerformancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(workspaceControllerProvider).selected?.roleName;

    return Scaffold(
      appBar: brandAppBar(title: const Text('User Performances')),
      body: !canViewTeamReports(role)
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyStateView(icon: Icons.lock_outline, message: 'Manager access is required to view user performances.'),
            )
          : const _PerformanceBody(),
    );
  }
}

class _PerformanceBody extends ConsumerWidget {
  const _PerformanceBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportDateFilterProvider);
    final state = ref.watch(teamReportControllerProvider);
    final controller = ref.read(teamReportControllerProvider.notifier);

    Widget content;
    switch (state.status) {
      case TeamReportStatus.initial:
      case TeamReportStatus.loading:
        content = const Center(child: CircularProgressIndicator());
      case TeamReportStatus.error:
        content = AppRetryView(message: state.errorMessage ?? 'Could not load user performances.', onRetry: controller.refresh);
      case TeamReportStatus.empty:
        content = RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            children: const [
              Padding(padding: EdgeInsets.all(AppSpacing.lg), child: EmptyStateView(icon: Icons.groups_outlined, message: 'No team activity in this period yet.')),
            ],
          ),
        );
      case TeamReportStatus.success:
      case TeamReportStatus.refreshing:
      case TeamReportStatus.loadingMore:
        content = RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Row(
                children: [
                  Expanded(child: AnalyticsStatTile(icon: Icons.call_outlined, color: AppColors.accent, value: '${state.totals.calls}', label: 'Calls')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AnalyticsStatTile(icon: Icons.phone_in_talk_outlined, color: AppColors.success, value: '${state.totals.connectedCalls}', label: 'Connected'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AnalyticsStatTile(icon: Icons.timer_outlined, color: AppColors.gold, value: formatTalkTime(state.totals.talkTimeSeconds), label: 'Talk time'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(icon: Icons.leaderboard_outlined, title: 'Ranking (${state.total})'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Ranked by leads converted in the selected period.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textDim),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < state.items.length; i++) ...[
                _AgentCard(rank: i + 1, row: state.items[i]),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (state.hasMore)
                Center(
                  child: state.status == TeamReportStatus.loadingMore
                      ? const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: CircularProgressIndicator())
                      : TextButton(key: const Key('load-more-agents'), onPressed: controller.loadMore, child: const Text('Load more')),
                ),
            ],
          ),
        );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: ReportDateRangeChips(
            singleRow: true,
            filter: filter,
            onChanged: (next) => ref.read(reportDateFilterProvider.notifier).state = next,
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.rank, required this.row});

  final int rank;
  final TeamMemberReportRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = row.member.displayName;
    // The podium gets the brand gold; everyone after stays neutral so the
    // top of the list reads at a glance without a rainbow of ranks.
    final rankColor = rank <= 3 ? AppColors.gold : AppColors.textDim;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#$rank', style: theme.textTheme.labelLarge?.copyWith(color: rankColor))),
          InitialsAvatar(name: name, size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${row.calls} calls · ${row.connectedCalls} connected · ${formatTalkTime(row.talkTimeSeconds)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textBody),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${row.leadsConverted}', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.success)),
              Text('${_percent(row.conversionRate)} conv.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
            ],
          ),
        ],
      ),
    );
  }
}
