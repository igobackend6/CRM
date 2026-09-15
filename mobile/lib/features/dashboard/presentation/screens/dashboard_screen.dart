import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../calls/presentation/screens/call_list_screen.dart' show CallTile, formatCallDateTime;
import '../../../followups/domain/entities/follow_up.dart';
import '../../../followups/presentation/screens/follow_up_list_screen.dart' show formatFollowUpDateTime;
import '../../domain/entities/activity_list_state.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/entities/leads_by_status_item.dart';
import '../../domain/entities/recent_activity_item.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/dashboard_date_range_chips.dart';

/// Phase 11 — Dashboard & CRM Analytics. Content-only (no Scaffold/AppBar
/// of its own) — embedded as `AppShellScreen`'s body so the existing
/// shell (app bar, notification bell, sign-out) is reused unchanged
/// (§"Do NOT redesign the shell"). Every section below is independently
/// async (its own `FutureProvider`/controller) so one slow/failed source
/// never blocks the rest of the page — same pattern Lead Detail's
/// Follow-ups/Calls sections already use.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(dashboardPendingFollowUpsProvider);
    ref.invalidate(dashboardRecentCallsProvider);
    await ref.read(activityListControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Overview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const _SummarySection(),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(icon: Icons.date_range_outlined, title: 'Analytics for'),
          const SizedBox(height: AppSpacing.sm),
          const _DateRangeSection(),
          const SizedBox(height: AppSpacing.sm),
          const _PeriodAnalyticsSection(),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(icon: Icons.pie_chart_outline, title: 'Pipeline distribution'),
          const SizedBox(height: AppSpacing.sm),
          const _PipelineDistributionSection(),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            icon: Icons.event_note_outlined,
            title: 'Follow-ups',
            action: TextButton(onPressed: () => context.push(RoutePaths.followUps), child: const Text('View all')),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _FollowUpsSection(),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            icon: Icons.call_outlined,
            title: 'Calls',
            action: TextButton(onPressed: () => context.push(RoutePaths.calls), child: const Text('View all')),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _CallSummarySection(),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(icon: Icons.leaderboard_outlined, title: 'Team productivity'),
          const SizedBox(height: AppSpacing.sm),
          const _TeamProductivitySection(),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(icon: Icons.timeline_outlined, title: 'Recent activity'),
          const SizedBox(height: AppSpacing.sm),
          const _RecentActivitySection(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// KPI grid (Phase 11 §"KPI/summary cards") — nine stat tiles from
/// `GET /dashboard/summary`, each a single number rather than a fetched
/// list, kept to one small request (no chart library — §"Charts are
/// optional. Do NOT add a chart library just for this phase.").
class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    return summaryAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load your dashboard summary.',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (summary) => _KpiGrid(summary: summary),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTileData('Active leads', summary.totalActiveLeads, Icons.people_outline, AppColors.accent, RoutePaths.leads),
      _KpiTileData('New leads', summary.newLeads, Icons.person_add_alt_outlined, AppColors.accent, RoutePaths.leads),
      _KpiTileData('Customers', summary.customers, Icons.verified_outlined, AppColors.success, null),
      _KpiTileData('Pending follow-ups', summary.pendingFollowUps, Icons.event_note_outlined, AppColors.accent, RoutePaths.followUps),
      _KpiTileData('Overdue follow-ups', summary.overdueFollowUps, Icons.warning_amber_outlined, Theme.of(context).colorScheme.error, RoutePaths.followUps),
      _KpiTileData('Completed follow-ups', summary.completedFollowUps, Icons.check_circle_outline, AppColors.success, RoutePaths.followUps),
      _KpiTileData('Total calls', summary.totalCalls, Icons.call_outlined, AppColors.gold, RoutePaths.calls),
      _KpiTileData("Today's calls", summary.todaysCalls, Icons.today_outlined, AppColors.gold, RoutePaths.calls),
      _KpiTileData('Unread notifications', summary.unreadNotifications, Icons.notifications_none_outlined, AppColors.success, RoutePaths.notifications),
    ];
    // A plain Column-of-Rows rather than GridView.count: a fixed
    // two-column stat layout doesn't need a whole scrollable-grid
    // widget (and its own shrinkWrap sizing pass) just to lay out nine
    // known items — this is simpler and cheaper. Two tiles per row, the
    // last row left with one tile (and a blank spacer) when the count
    // is odd.
    return Column(children: _kpiRows(tiles));
  }
}

class _KpiTileData {
  const _KpiTileData(this.label, this.value, this.icon, this.color, this.route, {this.displayOverride});

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? route;

  /// When set, rendered instead of `'$value'` — Phase 17's conversion-
  /// rate tile is a percentage, not a plain count, and reusing this same
  /// tile shape (rather than a one-off widget) keeps every KPI-style
  /// stat, Phase 11 and Phase 17 alike, visually consistent.
  final String? displayOverride;
}

/// Two-tiles-per-row layout shared by every KPI-style grid on this
/// screen (Phase 11's `_KpiGrid`, Phase 17's `_PeriodAnalyticsSection`)
/// — factored out so the row-building logic exists exactly once
/// (§"reuse instead of duplicating logic").
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
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        onTap: data.route == null ? null : () => context.push(data.route!),
        child: Container(
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
              Text(data.displayOverride ?? '${data.value}', style: theme.textTheme.headlineSmall),
              Text(data.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pending/overdue follow-up previews (Phase 11 §"pending follow-ups"/
/// "overdue follow-ups") — one fetch (`dashboardPendingFollowUpsProvider`,
/// reusing the existing Phase 7 follow-ups repository), split
/// client-side by the `isOverdue` flag the backend already computes.
class _FollowUpsSection extends ConsumerWidget {
  const _FollowUpsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followUpsAsync = ref.watch(dashboardPendingFollowUpsProvider);
    return followUpsAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load follow-ups.',
        onRetry: () => ref.invalidate(dashboardPendingFollowUpsProvider),
      ),
      data: (followUps) {
        if (followUps.isEmpty) {
          return const EmptyStateView(icon: Icons.event_note_outlined, message: 'No pending follow-ups.');
        }
        final overdue = followUps.where((f) => f.isOverdue).take(5).toList();
        final upcoming = followUps.where((f) => !f.isOverdue).take(5).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overdue.isNotEmpty) ...[
              Text('Overdue', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.error)),
              ...overdue.map((f) => _FollowUpPreviewTile(followUp: f)),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text('Upcoming', style: Theme.of(context).textTheme.labelLarge),
            if (upcoming.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xs), child: Text('Nothing else due soon.'))
            else
              ...upcoming.map((f) => _FollowUpPreviewTile(followUp: f)),
          ],
        );
      },
    );
  }
}

class _FollowUpPreviewTile extends StatelessWidget {
  const _FollowUpPreviewTile({required this.followUp});

  final FollowUp followUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = followUp.isOverdue ? theme.colorScheme.error : theme.colorScheme.secondary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: tone.withValues(alpha: 0.12),
        child: Icon(followUp.isOverdue ? Icons.warning_amber_outlined : Icons.event_note_outlined, size: 14, color: tone),
      ),
      title: Text(followUp.lead.name, style: theme.textTheme.bodyMedium),
      subtitle: Text('${followUp.type} • ${formatFollowUpDateTime(followUp.dueAt)}', style: theme.textTheme.bodySmall),
      onTap: () => context.push(RoutePaths.followUpDetail(followUp.id)),
    );
  }
}

/// Phase 17 §"Date Range" — the chip row that drives every period metric
/// below it (`_PeriodAnalyticsSection`, `_PipelineDistributionSection`,
/// `_TeamProductivitySection`) by writing `dashboardDateRangeProvider`,
/// which `dashboardSummaryProvider` already watches — selecting a chip
/// re-fetches the summary automatically, no manual invalidate needed.
class _DateRangeSection extends ConsumerWidget {
  const _DateRangeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(dashboardDateRangeProvider);
    return DashboardDateRangeChips(
      selected: selected,
      onChanged: (range) => ref.read(dashboardDateRangeProvider.notifier).state = range,
    );
  }
}

/// Phase 17 §"KPI summary" — the period-scoped counterpart to Phase 11's
/// all-time `_KpiGrid`, reusing the exact same `_KpiTileData`/`_KpiCard`/
/// `_kpiRows` shapes (§"reuse instead of duplicating logic") for the six
/// new metrics that only make sense over the selected date range.
class _PeriodAnalyticsSection extends ConsumerWidget {
  const _PeriodAnalyticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    return summaryAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load your period analytics.',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (summary) {
        final tiles = [
          _KpiTileData('Leads created', summary.leadsCreatedInRange, Icons.person_add_alt_outlined, AppColors.accent, RoutePaths.leads),
          _KpiTileData('Converted', summary.convertedLeadsInRange, Icons.verified_outlined, AppColors.success, null),
          _KpiTileData(
            'Conversion rate',
            0,
            Icons.trending_up_outlined,
            AppColors.success,
            null,
            displayOverride: '${(summary.conversionRate * 100).round()}%',
          ),
          _KpiTileData('Calls connected', summary.callsConnectedInRange, Icons.phone_in_talk_outlined, AppColors.gold, RoutePaths.calls),
          _KpiTileData('Calls completed', summary.callsCompletedInRange, Icons.call_end_outlined, AppColors.gold, RoutePaths.calls),
          _KpiTileData(
            'Follow-ups completed',
            summary.completedFollowUpsInRange,
            Icons.task_alt_outlined,
            AppColors.accent,
            RoutePaths.followUps,
          ),
        ];
        return Column(children: _kpiRows(tiles));
      },
    );
  }
}

/// Pipeline distribution (Phase 17 §"Pipeline metrics") — leads grouped
/// by the workspace's own `lead_statuses`, same status objects/order the
/// Phase 12 pipeline board already uses. A plain proportional bar per
/// row (a `Container` sized by `count / max`) rather than a charting
/// package — §"DO NOT add a chart library just for this phase."
class _PipelineDistributionSection extends ConsumerWidget {
  const _PipelineDistributionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    return summaryAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load the pipeline distribution.',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (summary) {
        final columns = summary.leadsByStatus;
        if (columns.isEmpty) {
          return const EmptyStateView(icon: Icons.pie_chart_outline, message: 'No pipeline stages configured yet.');
        }
        final maxCount = columns.map((c) => c.count).fold(0, (a, b) => a > b ? a : b);
        return Column(children: columns.map((c) => _PipelineStatusBar(item: c, maxCount: maxCount)).toList());
      },
    );
  }
}

class _PipelineStatusBar extends StatelessWidget {
  const _PipelineStatusBar({required this.item, required this.maxCount});

  final LeadsByStatusItem item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxCount > 0 ? item.count / maxCount : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(item.status.name, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.standard * 0.4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
                ),
              ),
            ),
          ),
          SizedBox(width: 28, child: Text('${item.count}', style: theme.textTheme.bodyMedium, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// Team productivity (Phase 17 §"Team productivity") — member, assigned
/// leads, calls, completed follow-ups. A plain `DataTable` (an existing
/// Flutter widget, no new dependency) inside a horizontal scroll so it
/// stays usable on a narrow phone (§"responsive layout"). Only members
/// with at least one nonzero count ever appear — see the backend's own
/// `TeamProductivityRow` docstring for why (RLS-driven visibility, not a
/// client-side filter).
class _TeamProductivitySection extends ConsumerWidget {
  const _TeamProductivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    return summaryAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load team productivity.',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (summary) {
        final rows = summary.teamProductivity;
        if (rows.isEmpty) {
          return const EmptyStateView(icon: Icons.leaderboard_outlined, message: 'No team activity in this period yet.');
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: AppSpacing.lg,
            columns: const [
              DataColumn(label: Text('Member')),
              DataColumn(label: Text('Leads'), numeric: true),
              DataColumn(label: Text('Calls'), numeric: true),
              DataColumn(label: Text('Follow-ups')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(Text(row.member.displayName)),
                    DataCell(Text('${row.leadsCount}')),
                    DataCell(Text('${row.callsCount}')),
                    DataCell(Text('${row.completedFollowUpsCount}')),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Call summary (Phase 11 §"call summary") — the today's/total-calls
/// counts already live in the KPI grid above; this section previews the
/// most recent calls, reusing the existing `CallTile` widget unchanged
/// (Phase 9) rather than a third call-row implementation.
class _CallSummarySection extends ConsumerWidget {
  const _CallSummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(dashboardRecentCallsProvider);
    return callsAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => AppRetryView(
        message: 'Could not load calls.',
        onRetry: () => ref.invalidate(dashboardRecentCallsProvider),
      ),
      data: (calls) {
        if (calls.isEmpty) return const EmptyStateView(icon: Icons.call_outlined, message: 'No calls logged yet.');
        return Column(children: calls.map((c) => CallTile(call: c)).toList());
      },
    );
  }
}

/// Icon + color per activity type — the multi-hue category rail used
/// throughout this app's list screens (docs/design/design-tokens.md),
/// extended here with a generic fallback for `interactions.type` values
/// this feed doesn't otherwise special-case (status_change/document/
/// message).
(IconData, Color) _activityVisual(BuildContext context, String type) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (type) {
    case 'call':
      return (Icons.call_outlined, colorScheme.secondary);
    case 'follow_up':
      return (Icons.event_note_outlined, AppColors.pink);
    case 'note':
      return (Icons.sticky_note_2_outlined, AppColors.accent);
    case 'allocation':
      return (Icons.person_pin_circle_outlined, AppColors.gold);
    case 'notification':
      return (Icons.notifications_outlined, AppColors.success);
    case 'document':
      return (Icons.insert_drive_file_outlined, AppColors.success);
    default:
      return (Icons.history, colorScheme.outline);
  }
}

/// Resolves a recent-activity item to one of the app's *existing* detail
/// routes — same "no placeholder screens" rule as Phase 10's
/// notification navigation. Only `call`/`follow_up` items have a
/// standalone detail screen to jump to; interactions/allocations/
/// notifications are shown but not tappable-to-navigate.
String? resolveActivityRoute(RecentActivityItem item) {
  final id = item.entityId;
  if (id == null) return null;
  switch (item.entityType) {
    case 'call':
      return RoutePaths.callDetail(id);
    case 'follow_up':
      return RoutePaths.followUpDetail(id);
    default:
      return null;
  }
}

class _RecentActivitySection extends ConsumerStatefulWidget {
  const _RecentActivitySection();

  @override
  ConsumerState<_RecentActivitySection> createState() => _RecentActivitySectionState();
}

class _RecentActivitySectionState extends ConsumerState<_RecentActivitySection> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activityListControllerProvider);
    switch (state.status) {
      case ActivityListStatus.initial:
      case ActivityListStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Center(child: CircularProgressIndicator()));

      case ActivityListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load recent activity.',
          onRetry: () => ref.read(activityListControllerProvider.notifier).refresh(),
        );

      case ActivityListStatus.empty:
        return const EmptyStateView(icon: Icons.timeline_outlined, message: 'No activity yet.');

      case ActivityListStatus.success:
      case ActivityListStatus.refreshing:
      case ActivityListStatus.loadingMore:
        return Column(
          children: [
            ...state.items.map((item) => _ActivityTile(item: item)),
            if (state.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: state.status == ActivityListStatus.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton(
                        onPressed: () => ref.read(activityListControllerProvider.notifier).loadMore(),
                        child: const Text('Load more'),
                      ),
              ),
          ],
        );
    }
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final RecentActivityItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _activityVisual(context, item.type);
    final route = resolveActivityRoute(item);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 16, color: color)),
      title: Text(item.summary, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        [if (item.actorMember != null) item.actorMember!.displayName, formatCallDateTime(item.occurredAt)].join(' • '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: route != null ? Icon(Icons.chevron_right, color: theme.colorScheme.outline) : null,
      onTap: route == null ? null : () => context.push(route),
    );
  }
}
