import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/follow_up_list_state.dart';
import '../../domain/repositories/follow_up_repository.dart';

/// Global Follow-Up List (Phase 7 §2A) — loading/success/empty/error +
/// pull-to-refresh + offset-pagination. Reuses [resolveLeadContext] from
/// the leads feature rather than re-deriving accessToken/workspaceId:
/// that helper is generic (session + selected workspace), not
/// lead-specific despite its name/location — see its own docstring.
class FollowUpListController extends StateNotifier<FollowUpListState> with RealtimeRefreshMixin<FollowUpListState> {
  FollowUpListController(this._repository, this._ref) : super(const FollowUpListState.initial()) {
    // Reacts to workspace selection, same pattern as LeadListController —
    // correct even if this controller happens to build a moment before
    // workspace selection resolves.
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — created/updated/reassigned/completed/cancelled
    // elsewhere refreshes this list; a delete removes the row in place
    // (follow_ups has no delete policy today, but the handler stays
    // correct regardless of future schema changes).
    subscribeRealtime(_ref, const {'follow_ups'}, _onRealtimeEvent);
  }

  final FollowUpRepository _repository;
  final Ref _ref;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    if (event.type == RealtimeEventType.delete) {
      final id = event.id;
      if (id != null && state.items.any((f) => f.id == id)) {
        state = state.copyWith(items: state.items.where((f) => f.id != id).toList(), total: state.total > 0 ? state.total - 1 : 0);
      }
      return;
    }
    debouncedRealtimeRefresh(refresh);
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(refresh);

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == FollowUpListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? FollowUpListStatus.loading : FollowUpListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listFollowUps(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? FollowUpListStatus.empty : FollowUpListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: FollowUpListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load follow-ups', error: e);
      state = state.copyWith(status: FollowUpListStatus.error, errorMessage: 'Could not load follow-ups.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == FollowUpListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: FollowUpListStatus.loadingMore);
    try {
      final page = await _repository.listFollowUps(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: FollowUpListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      // Keep the already-loaded items visible; only surface the error.
      state = state.copyWith(status: FollowUpListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more follow-ups', error: e);
      state = state.copyWith(status: FollowUpListStatus.success, errorMessage: 'Could not load more follow-ups.');
    }
  }

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }
}
