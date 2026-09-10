import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/activity_list_state.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../providers/dashboard_providers.dart';

/// Dashboard recent-activity feed — loading/success/empty/error +
/// pull-to-refresh + offset-pagination, same shape as every other list
/// controller in this app (CallListController, NotificationListController).
class ActivityListController extends StateNotifier<ActivityListState> with RealtimeRefreshMixin<ActivityListState> {
  ActivityListController(this._repository, this._ref) : super(const ActivityListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B STEP 9 — any relevant table change refreshes the
    // activity feed AND invalidates the KPI summary (a `FutureProvider`,
    // so `ref.invalidate` is the correct "refresh" for it), debounced
    // together so a burst of events (e.g. a bulk action) recomputes
    // once, not once per row.
    subscribeRealtime(_ref, const {'leads', 'follow_ups', 'notifications', 'allocations', 'messages'}, (_) => _refreshDashboard());
  }

  final DashboardRepository _repository;
  final Ref _ref;

  void _refreshDashboard() {
    debouncedRealtimeRefresh(() async {
      _ref.invalidate(dashboardSummaryProvider);
      await refresh();
    }, duration: const Duration(milliseconds: 800));
  }

  @override
  void onRealtimeResync() => _refreshDashboard();

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == ActivityListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? ActivityListStatus.loading : ActivityListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.getRecentActivity(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? ActivityListStatus.empty : ActivityListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: ActivityListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load recent activity', error: e);
      state = state.copyWith(status: ActivityListStatus.error, errorMessage: 'Could not load recent activity.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == ActivityListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: ActivityListStatus.loadingMore);
    try {
      final page = await _repository.getRecentActivity(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: ActivityListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: ActivityListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more activity', error: e);
      state = state.copyWith(status: ActivityListStatus.success, errorMessage: 'Could not load more activity.');
    }
  }

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }
}
