import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/activity_filter.dart';
import '../../domain/entities/timeline_item.dart';
import '../../domain/entities/timeline_list_state.dart';
import '../../domain/repositories/customer_repository.dart';

/// One instance per customer (`.family`) — the unified timeline section
/// (Phase 8 §3/§10), loaded lazily by CustomerDetailScreen (not at
/// construction) and offset-paginated via [loadMore] (§15: never fetch
/// every timeline item at once).
class CustomerTimelineController extends StateNotifier<TimelineListState> with RealtimeRefreshMixin<TimelineListState> {
  CustomerTimelineController(this._repository, this._ref, this.customerId) : super(const TimelineListState.initial()) {
    // Phase 21B — a customer is a converted lead (Phase 18), so
    // `customerId` IS that lead's id; `leads`/`follow_ups` rows
    // referencing it refresh this timeline live. `messages`/`calls`
    // aren't included: their raw payloads carry a `conversation_id`
    // rather than `lead_id` (calls aren't published at all — see
    // 000016_realtime.sql) with no cheap client-side way to resolve
    // that back to this lead, so those sources still update on the
    // screen's next natural refresh/reopen — see the Phase 21B report's
    // "Remaining Limitations".
    subscribeRealtime(_ref, const {'leads', 'follow_ups'}, _onRealtimeEvent);
  }

  final CustomerRepository _repository;
  final Ref _ref;
  final String customerId;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    final affectsThisCustomer = event.table == 'leads' ? event.id == customerId : event.record['lead_id'] == customerId;
    if (!affectsThisCustomer) return;
    debouncedRealtimeRefresh(refresh);
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(refresh);

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == TimelineListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? TimelineListStatus.loading : TimelineListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.getTimeline(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        customerId: customerId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? TimelineListStatus.empty : TimelineListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: TimelineListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load timeline for customer $customerId', error: e);
      state = state.copyWith(status: TimelineListStatus.error, errorMessage: 'Could not load the activity timeline.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == TimelineListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: TimelineListStatus.loadingMore);
    try {
      final page = await _repository.getTimeline(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        customerId: customerId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: TimelineListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: TimelineListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more timeline items for customer $customerId', error: e);
      state = state.copyWith(status: TimelineListStatus.success, errorMessage: 'Could not load more activity.');
    }
  }

  /// Phase 15 §"Activity Filters" — switching the active type filter
  /// resets pagination (a fresh first-page load), same as
  /// LeadListController.applyFilters (Phase 14).
  Future<void> setFilter(ActivityFilter filter) {
    state = state.copyWith(filter: filter);
    return refresh();
  }

  /// Prepends a just-created note (Phase 8 §7) without a full refetch —
  /// the note create endpoint already returns the created row, adapted
  /// to a [TimelineItem] by the repository.
  void prependItem(TimelineItem item) {
    state = state.copyWith(status: TimelineListStatus.success, items: [item, ...state.items], total: state.total + 1);
  }
}
