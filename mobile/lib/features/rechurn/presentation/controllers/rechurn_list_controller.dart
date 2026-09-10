import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../pipeline/domain/repositories/pipeline_repository.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/rechurn_filters.dart';
import '../../domain/entities/rechurn_list_state.dart';
import '../../domain/entities/rechurn_page.dart';
import '../../domain/repositories/rechurn_repository.dart';

/// Loading/success/empty/error + pull-to-refresh + basic offset-
/// pagination (Phase 19), mirroring `LeadListController`'s shape
/// exactly. Also owns the queue's one inline write action — "Update
/// status" — by reusing `PipelineRepository.changeLeadStatus`
/// (Phase 12's existing status-change write path, the same one the
/// Pipeline board's drag-and-drop already uses) rather than adding a
/// second status-change call anywhere. Call/outcome/follow-up actions
/// need no controller method at all: the queue screen navigates to the
/// existing Call/Follow-up form screens for those (see
/// RechurnQueueScreen), so this class never re-implements that
/// business logic either.
class RechurnListController extends StateNotifier<RechurnListState> with RealtimeRefreshMixin<RechurnListState> {
  RechurnListController(this._repository, this._pipelineRepository, this._ref) : super(const RechurnListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — a lead's status/assignment changing elsewhere can move
    // it into or out of rechurn eligibility; a debounced full reload
    // (rather than a client-side eligibility check that would duplicate
    // the backend's own rechurn-segment logic) is the safe way to keep
    // this queue current.
    subscribeRealtime(_ref, const {'leads', 'allocations'}, (_) => debouncedRealtimeRefresh(refresh));
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(refresh);

  final RechurnRepository _repository;
  final PipelineRepository _pipelineRepository;
  final Ref _ref;
  Timer? _debounce;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == RechurnListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? RechurnListStatus.loading : RechurnListStatus.refreshing, clearError: true);

    try {
      final page = await _fetch(context, offset: 0);
      state = state.copyWith(
        status: page.items.isEmpty ? RechurnListStatus.empty : RechurnListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: RechurnListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load the rechurn queue', error: e);
      state = state.copyWith(status: RechurnListStatus.error, errorMessage: 'Could not load the rechurn queue.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == RechurnListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: RechurnListStatus.loadingMore);
    try {
      final page = await _fetch(context, offset: state.items.length);
      state = state.copyWith(status: RechurnListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: RechurnListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more of the rechurn queue', error: e);
      state = state.copyWith(status: RechurnListStatus.success, errorMessage: 'Could not load more of the queue.');
    }
  }

  Future<RechurnPage> _fetch(LeadRequestContext context, {required int offset}) => _repository.getQueue(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        segment: state.filters.segment,
        inactiveDays: state.filters.inactiveDays,
        assignedMemberId: state.filters.assignedMemberId,
        priority: state.filters.priority,
        statusId: state.filters.statusId,
        sourceId: state.filters.sourceId,
        search: state.searchQuery.isEmpty ? null : state.searchQuery,
        limit: state.limit,
        offset: offset,
      );

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  Future<void> applyFilters(RechurnFilters filters) {
    state = state.copyWith(filters: filters);
    return refresh();
  }

  Future<void> clearFilters() {
    state = state.copyWith(filters: const RechurnFilters.empty());
    return refresh();
  }

  /// Changes [leadId]'s status via the existing Pipeline write path
  /// (Phase 12) and refreshes the queue — a lead that's no longer stale/
  /// lost under the active filters simply drops out on the next load,
  /// same "server is the source of truth for grouping" rule
  /// `PipelineController.changeStatus` already documents. Returns
  /// whether the change succeeded, same `Future<bool>` convention as
  /// every other action controller in this app.
  Future<bool> changeStatus({required String leadId, required String statusId}) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;

    try {
      await _pipelineRepository.changeLeadStatus(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        statusId: statusId,
      );
      await refresh();
      return true;
    } on AppException catch (e) {
      state = state.copyWith(errorMessage: e.message);
      return false;
    } catch (e) {
      AppLogger.error('Failed to change status for lead $leadId', error: e);
      state = state.copyWith(errorMessage: 'Could not change the lead status.');
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    disposeRealtime();
    super.dispose();
  }
}
