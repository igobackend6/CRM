import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/dashboard_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../calls/domain/entities/call.dart';
import '../../../calls/presentation/providers/call_providers.dart';
import '../../../followups/domain/entities/follow_up.dart';
import '../../../followups/presentation/providers/followup_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/dashboard_repository_impl.dart';
import '../../domain/entities/activity_list_state.dart';
import '../../domain/entities/dashboard_date_range.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../controllers/activity_list_controller.dart';

final dashboardApiDataSourceProvider = Provider<DashboardApiDataSource>((ref) => DioDashboardApiDataSource());

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(ref.watch(dashboardApiDataSourceProvider));
});

/// The dashboard's date-range filter (Phase 17 §"Date Range") — plain
/// `StateProvider`, not `.autoDispose`, so the user's chosen range
/// survives navigating away from the dashboard tab and back (same
/// lifetime as `workspaceControllerProvider`, which this screen already
/// depends on). Defaults to `DashboardDateRange.all`, which reproduces
/// the dashboard's pre-Phase-17 request exactly (§"Default should
/// preserve current dashboard behavior").
final dashboardDateRangeProvider = StateProvider<DashboardDateRange>((ref) => DashboardDateRange.all);

/// KPI summary (Phase 11 §"Backend"; extended Phase 17 with period/
/// productivity analytics) — one small request, re-fetched whenever the
/// workspace or the selected date range changes, or the screen
/// invalidates it (pull-to-refresh), same pattern as
/// `callOutcomesProvider`/`leadReferenceDataProvider`.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  final range = ref.watch(dashboardDateRangeProvider);
  if (workspace == null || user == null) {
    return const DashboardSummary(
      totalActiveLeads: 0,
      newLeads: 0,
      customers: 0,
      pendingFollowUps: 0,
      overdueFollowUps: 0,
      completedFollowUps: 0,
      totalCalls: 0,
      todaysCalls: 0,
      unreadNotifications: 0,
    );
  }
  final repository = ref.watch(dashboardRepositoryProvider);
  return repository.getSummary(accessToken: user.accessToken, workspaceId: workspace.workspace.id, range: range.apiValue);
});

final activityListControllerProvider = StateNotifierProvider.autoDispose<ActivityListController, ActivityListState>((ref) {
  return ActivityListController(ref.watch(dashboardRepositoryProvider), ref);
});

/// "Pending follow-ups" preview section — reuses the existing Phase 7
/// `FollowUpRepository.listFollowUps(status:)` unchanged rather than
/// asking the backend for a second, dashboard-specific follow-up list
/// (Phase 11 §"reuse instead of duplicating logic"). `isOverdue` (a
/// field the backend already computes per follow-up — Phase 7) is used
/// client-side to split this same fetch into the "overdue" preview too,
/// so there's only one network call for both sections.
final dashboardPendingFollowUpsProvider = FutureProvider.autoDispose<List<FollowUp>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(followUpRepositoryProvider);
  final page = await repository.listFollowUps(
    accessToken: user.accessToken,
    workspaceId: workspace.workspace.id,
    status: 'pending',
    limit: 20,
  );
  return page.items;
});

/// "Call summary" preview section — reuses the existing Phase 9
/// `CallRepository.listCalls` unchanged.
final dashboardRecentCallsProvider = FutureProvider.autoDispose<List<Call>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(callRepositoryProvider);
  final page = await repository.listCalls(accessToken: user.accessToken, workspaceId: workspace.workspace.id, limit: 5);
  return page.items;
});
