import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/personal_report.dart';
import '../../domain/entities/pipeline_report.dart';
import '../../domain/entities/team_report.dart';
import '../../domain/entities/team_report_state.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_date_range_chips.dart';

const _managerRoles = {'manager', 'admin', 'ceo'};

/// Phase 21C — Complete Reports & Analytics. A dedicated screen (its own
/// route, `RoutePaths.reports`, reachable from the app shell's app bar —
/// same "lightweight entry point" pattern Phase 19's Rechurn queue used)
/// rather than a Dashboard tab: Dashboard stays the high-level CRM
/// overview; this screen is the detailed-analytics counterpart, with its
/// own three tabs (§"Personal"/"Team"/"Pipeline") and one shared date
/// range filter above them (§"Date Range Support": "one canonical
/// date-range implementation across reports").
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reportDateFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Personal'), Tab(text: 'Team'), Tab(text: 'Pipeline')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: ReportDateRangeChips(
              filter: filter,
              onChanged: (next) => ref.read(reportDateFilterProvider.notifier).state = next,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_PersonalReportTab(), _TeamReportTab(), _PipelineReportTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-tiles-per-row KPI card, styled to match the Dashboard's own
/// `_KpiCard` (dashboard_screen.dart) for visual consistency — kept as
/// its own small widget here rather than importing that one (it's
/// private to that file, and Reports/Dashboard are deliberately kept
/// independent — §"Do not duplicate the existing Dashboard").
class _KpiTileData {
  const _KpiTileData(this.label, this.display, this.icon, this.color);

  final String label;
  final String display;
  final IconData icon;
  final Color color;
}

List<Widget> _kpiRows(List<_KpiTileData> tiles) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += 2) {
    final second = i + 1 < tiles.length ? tiles[i + 1] : null;
    rows.add(
      Padding(
        padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? AppSpacing.sm : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _KpiCard(data: tiles[i])),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: second != null ? _KpiCard(data: second) : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
  return rows;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiTileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: data.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.standard * 0.6)),
            child: Icon(data.icon, size: 16, color: data.color),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(data.display, style: theme.textTheme.headlineSmall),
          Text(data.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

String _pct(double rate) => '${(rate * 100).round()}%';

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '${minutes}m ${remaining}s';
}

/// A permission-gated section — Team/Pipeline require `reports.read`
/// (manager/admin/ceo only). Checked client-side from the workspace
/// membership's own `roleName` purely to skip a doomed request and show
/// a clear message (never the real security boundary — the backend
/// still enforces `Permission.REPORTS_READ` regardless of what this
/// check decides, per §"Security": "Do not trust Flutter filtering for
/// security").
class _ManagerGate extends ConsumerWidget {
  const _ManagerGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(workspaceControllerProvider).selected?.roleName;
    if (role != null && !_managerRoles.contains(role)) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: EmptyStateView(icon: Icons.lock_outline, message: 'Manager access is required to view this report.'),
      );
    }
    return child;
  }
}

// ---- Personal tab ----

class _PersonalReportTab extends ConsumerWidget {
  const _PersonalReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(personalReportProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(personalReportProvider),
      child: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppRetryView(
          message: 'Could not load your personal report.',
          onRetry: () => ref.invalidate(personalReportProvider),
        ),
        data: (report) => _PersonalReportBody(report: report),
      ),
    );
  }
}

class _PersonalReportBody extends StatelessWidget {
  const _PersonalReportBody({required this.report});

  final PersonalReport report;

  @override
  Widget build(BuildContext context) {
    final calls = report.calls;
    final followUps = report.followUps;
    final leads = report.leads;
    final pipeline = report.pipeline;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const SectionHeader(icon: Icons.call_outlined, title: 'Calls'),
        const SizedBox(height: AppSpacing.sm),
        ..._kpiRows([
          _KpiTileData('Total calls', '${calls.totalCalls}', Icons.call_outlined, AppColors.gold),
          _KpiTileData('Connected', '${calls.connectedCalls}', Icons.phone_in_talk_outlined, AppColors.success),
          _KpiTileData('Unconnected', '${calls.unconnectedCalls}', Icons.phone_missed_outlined, Theme.of(context).colorScheme.error),
          _KpiTileData('Completed', '${calls.completedCalls}', Icons.call_end_outlined, AppColors.gold),
          _KpiTileData('Total talk time', _duration(calls.totalTalkTimeSeconds), Icons.timer_outlined, AppColors.accent),
          _KpiTileData('Avg. call duration', _duration(calls.averageCallDurationSeconds.round()), Icons.speed_outlined, AppColors.accent),
        ]),
        if (calls.callsByOutcome.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('By outcome', style: Theme.of(context).textTheme.labelLarge),
          for (final item in calls.callsByOutcome)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(item.outcome.name), Text('${item.count}')],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.event_note_outlined, title: 'Follow-ups'),
        const SizedBox(height: AppSpacing.sm),
        ..._kpiRows([
          _KpiTileData('Total', '${followUps.totalFollowUps}', Icons.event_note_outlined, AppColors.accent),
          _KpiTileData('Pending', '${followUps.pendingFollowUps}', Icons.pending_actions_outlined, AppColors.accent),
          _KpiTileData('Completed', '${followUps.completedFollowUps}', Icons.check_circle_outline, AppColors.success),
          _KpiTileData('Cancelled', '${followUps.cancelledFollowUps}', Icons.cancel_outlined, Theme.of(context).colorScheme.outline),
          _KpiTileData('Overdue', '${followUps.overdueFollowUps}', Icons.warning_amber_outlined, Theme.of(context).colorScheme.error),
        ]),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.person_add_alt_outlined, title: 'Leads'),
        const SizedBox(height: AppSpacing.sm),
        ..._kpiRows([
          _KpiTileData('Created', '${leads.leadsCreated}', Icons.add_circle_outline, AppColors.accent),
          _KpiTileData('Assigned', '${leads.leadsAssigned}', Icons.assignment_ind_outlined, AppColors.accent),
          _KpiTileData('Contacted', '${leads.leadsContacted}', Icons.call_made_outlined, AppColors.gold),
          _KpiTileData('Converted', '${leads.leadsConverted}', Icons.verified_outlined, AppColors.success),
          _KpiTileData('Conversion rate', _pct(leads.conversionRate), Icons.trending_up_outlined, AppColors.success),
        ]),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.pie_chart_outline, title: 'My pipeline'),
        const SizedBox(height: AppSpacing.sm),
        ..._kpiRows([
          _KpiTileData('Customers', '${pipeline.customerCount}', Icons.verified_outlined, AppColors.success),
          _KpiTileData('Lost', '${pipeline.lostLeads}', Icons.cancel_outlined, Theme.of(context).colorScheme.error),
          _KpiTileData('Active pipeline', '${pipeline.activePipelineCount}', Icons.trending_up_outlined, AppColors.accent),
        ]),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

// ---- Team tab ----

class _TeamReportTab extends ConsumerWidget {
  const _TeamReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ManagerGate(child: _TeamReportBody(key: const ValueKey('team-report-body')));
  }
}

class _TeamReportBody extends ConsumerWidget {
  const _TeamReportBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(teamReportControllerProvider);
    switch (state.status) {
      case TeamReportStatus.initial:
      case TeamReportStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case TeamReportStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load the team report.',
          onRetry: () => ref.read(teamReportControllerProvider.notifier).refresh(),
        );

      case TeamReportStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(teamReportControllerProvider.notifier).refresh(),
          child: ListView(
            children: const [Padding(padding: EdgeInsets.all(AppSpacing.lg), child: EmptyStateView(icon: Icons.groups_outlined, message: 'No team activity in this period yet.'))],
          ),
        );

      case TeamReportStatus.success:
      case TeamReportStatus.refreshing:
      case TeamReportStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => ref.read(teamReportControllerProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SectionHeader(icon: Icons.groups_outlined, title: 'Team totals'),
              const SizedBox(height: AppSpacing.sm),
              ..._kpiRows([
                _KpiTileData('Leads assigned', '${state.totals.leadsAssigned}', Icons.assignment_ind_outlined, AppColors.accent),
                _KpiTileData('Converted', '${state.totals.leadsConverted}', Icons.verified_outlined, AppColors.success),
                _KpiTileData('Conversion rate', _pct(state.totals.conversionRate), Icons.trending_up_outlined, AppColors.success),
                _KpiTileData('Calls', '${state.totals.calls}', Icons.call_outlined, AppColors.gold),
                _KpiTileData('Connected calls', '${state.totals.connectedCalls}', Icons.phone_in_talk_outlined, AppColors.gold),
                _KpiTileData('Talk time', _duration(state.totals.talkTimeSeconds), Icons.timer_outlined, AppColors.accent),
              ]),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(icon: Icons.leaderboard_outlined, title: 'By member (${state.total})'),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: AppSpacing.lg,
                  columns: const [
                    DataColumn(label: Text('Member')),
                    DataColumn(label: Text('Leads'), numeric: true),
                    DataColumn(label: Text('Converted'), numeric: true),
                    DataColumn(label: Text('Rate'), numeric: true),
                    DataColumn(label: Text('Calls'), numeric: true),
                    DataColumn(label: Text('Follow-ups'), numeric: true),
                  ],
                  rows: [
                    for (final row in state.items) _memberRow(row),
                  ],
                ),
              ),
              if (state.hasMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: state.status == TeamReportStatus.loadingMore
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: OutlinedButton(
                            onPressed: () => ref.read(teamReportControllerProvider.notifier).loadMore(),
                            child: const Text('Load more'),
                          ),
                        ),
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
    }
  }

  DataRow _memberRow(TeamMemberReportRow row) {
    return DataRow(
      cells: [
        DataCell(Text(row.member.displayName)),
        DataCell(Text('${row.leadsAssigned}')),
        DataCell(Text('${row.leadsConverted}')),
        DataCell(Text(_pct(row.conversionRate))),
        DataCell(Text('${row.calls}')),
        DataCell(Text('${row.completedFollowUps}/${row.pendingFollowUps}')),
      ],
    );
  }
}

// ---- Pipeline tab ----

class _PipelineReportTab extends ConsumerWidget {
  const _PipelineReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ManagerGate(
      child: Consumer(
        builder: (context, ref, _) {
          final reportAsync = ref.watch(pipelineReportProvider);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pipelineReportProvider),
            child: reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => AppRetryView(
                message: 'Could not load the pipeline report.',
                onRetry: () => ref.invalidate(pipelineReportProvider),
              ),
              data: (report) => _PipelineReportBody(report: report),
            ),
          );
        },
      ),
    );
  }
}

class _PipelineReportBody extends StatelessWidget {
  const _PipelineReportBody({required this.report});

  final PipelineReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ..._kpiRows([
          _KpiTileData('Converted customers', '${report.convertedCustomers}', Icons.verified_outlined, AppColors.success),
          _KpiTileData('Lost leads', '${report.lostLeads}', Icons.cancel_outlined, Theme.of(context).colorScheme.error),
          _KpiTileData('Active leads', '${report.activeLeads}', Icons.trending_up_outlined, AppColors.accent),
        ]),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.pie_chart_outline, title: 'Status distribution'),
        const SizedBox(height: AppSpacing.sm),
        if (report.leadsByStatus.isEmpty)
          const EmptyStateView(icon: Icons.pie_chart_outline, message: 'No pipeline stages configured yet.')
        else
          for (final item in report.leadsByStatus) _DistributionBar(label: item.status.name, count: item.count, percentage: item.percentage),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.source_outlined, title: 'Source performance'),
        const SizedBox(height: AppSpacing.sm),
        if (report.sourcePerformance.isEmpty)
          const EmptyStateView(icon: Icons.source_outlined, message: 'No lead sources configured yet.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: AppSpacing.lg,
              columns: const [
                DataColumn(label: Text('Source')),
                DataColumn(label: Text('Leads'), numeric: true),
                DataColumn(label: Text('Converted'), numeric: true),
                DataColumn(label: Text('Rate'), numeric: true),
              ],
              rows: [
                for (final item in report.sourcePerformance)
                  DataRow(
                    cells: [
                      DataCell(Text(item.source.name)),
                      DataCell(Text('${item.leadsCount}')),
                      DataCell(Text('${item.convertedCount}')),
                      DataCell(Text(_pct(item.conversionRate))),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.flag_outlined, title: 'Priority distribution'),
        const SizedBox(height: AppSpacing.sm),
        for (final item in report.priorityDistribution)
          _DistributionBar(label: item.priority, count: item.count, percentage: item.percentage),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.label, required this.count, required this.percentage});

  final String label;
  final int count;
  final double percentage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.standard * 0.4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
                ),
              ),
            ),
          ),
          SizedBox(width: 56, child: Text('$count (${percentage.toStringAsFixed(1)}%)', style: theme.textTheme.bodySmall, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
