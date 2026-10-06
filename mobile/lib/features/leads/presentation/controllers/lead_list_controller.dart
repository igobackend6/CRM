import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/bulk_action_result.dart';
import '../../domain/entities/lead_bulk_action.dart';
import '../../domain/entities/lead_filters.dart';
import '../../domain/entities/lead_list_state.dart';
import '../../domain/repositories/lead_repository.dart';
import 'lead_request_context.dart';

/// Loading/success/empty/error + pull-to-refresh + basic
/// offset-pagination (Phase 5 §2). Search is server/database-filtered
/// (Phase 5 §2 "do not load the entire workspace lead table
/// unnecessarily"), debounced client-side so typing doesn't fire a
/// request per keystroke.
class LeadListController extends StateNotifier<LeadListState> with RealtimeRefreshMixin<LeadListState> {
  /// [initialFilters] lets a screen pin a filter from the start (the Customers tab pins
  /// `isCustomer: true`); every other list starts unfiltered.
  LeadListController(this._repository, this._ref, {LeadFilters initialFilters = const LeadFilters.empty()})
      : super(const LeadListState.initial().copyWith(filters: initialFilters)) {
    // Reacts to workspace selection rather than refreshing once in the
    // constructor — mirrors WorkspaceController's `ref.listen(auth...)`
    // pattern (Phase 4). The router only allows /app/leads once a
    // workspace is selected, but this stays correct even if this
    // controller's provider happens to build a moment before that.
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — a lead created/updated/reassigned/status-changed
    // elsewhere (or an allocation touching one) refreshes this list; a
    // delete removes the row in place immediately (no data needed beyond
    // the id, so no reason to wait for the debounce).
    subscribeRealtime(_ref, const {'leads', 'allocations'}, _onRealtimeEvent);
  }

  final LeadRepository _repository;
  final Ref _ref;
  Timer? _debounce;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    if (event.table == 'leads' && event.type == RealtimeEventType.delete) {
      final id = event.id;
      if (id != null && state.items.any((l) => l.id == id)) {
        state = state.copyWith(items: state.items.where((l) => l.id != id).toList(), total: state.total > 0 ? state.total - 1 : 0);
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

    final isFirstLoad = state.status == LeadListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? LeadListStatus.loading : LeadListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listLeads(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        search: state.searchQuery.isEmpty ? null : state.searchQuery,
        statusId: state.filters.statusId,
        sourceId: state.filters.sourceId,
        assignedMemberId: state.filters.assignedMemberId,
        priority: state.filters.priority,
        isCustomer: state.filters.isCustomer,
        createdFrom: state.filters.createdFrom,
        createdTo: state.filters.createdTo,
        tagId: state.filters.tagId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? LeadListStatus.empty : LeadListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: LeadListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load leads', error: e);
      state = state.copyWith(status: LeadListStatus.error, errorMessage: 'Could not load leads.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == LeadListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: LeadListStatus.loadingMore);
    try {
      final page = await _repository.listLeads(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        search: state.searchQuery.isEmpty ? null : state.searchQuery,
        statusId: state.filters.statusId,
        sourceId: state.filters.sourceId,
        assignedMemberId: state.filters.assignedMemberId,
        priority: state.filters.priority,
        isCustomer: state.filters.isCustomer,
        createdFrom: state.filters.createdFrom,
        createdTo: state.filters.createdTo,
        tagId: state.filters.tagId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: LeadListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      // Keep the already-loaded items visible; only surface the error.
      state = state.copyWith(status: LeadListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more leads', error: e);
      state = state.copyWith(status: LeadListStatus.success, errorMessage: 'Could not load more leads.');
    }
  }

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  // ---- advanced filters (Phase 14) ----

  /// Replaces the active filter set and reruns the query from the first
  /// page — same "a filter change is a fresh paginated query" rule as
  /// `updateSearch`, just without the debounce (this only fires once, on
  /// the filter sheet's explicit Apply, not per keystroke).
  Future<void> applyFilters(LeadFilters filters) {
    state = state.copyWith(filters: filters);
    return refresh();
  }

  Future<void> clearFilters() {
    state = state.copyWith(filters: const LeadFilters.empty());
    return refresh();
  }

  // ---- bulk selection (Phase 13 §"Bulk Selection") ----

  void enterSelectionMode() => state = state.copyWith(selectionMode: true, selectedIds: {});

  void exitSelectionMode() => state = state.copyWith(selectionMode: false, selectedIds: {});

  void toggleSelection(String leadId) {
    final next = Set<String>.from(state.selectedIds);
    if (!next.remove(leadId)) next.add(leadId);
    state = state.copyWith(selectedIds: next);
  }

  /// Selects every currently-loaded (visible) lead — not the full,
  /// possibly-unloaded workspace total, matching the spec's "select all
  /// visible leads" wording exactly.
  void selectAllVisible() => state = state.copyWith(selectedIds: state.items.map((l) => l.id).toSet());

  void clearSelection() => state = state.copyWith(selectedIds: {});

  /// Runs [action] against every selected lead and, on a successful
  /// round trip, exits selection mode and reloads the list — mirroring
  /// LeadDetailController's "refresh what changed after a mutation"
  /// convention. Returns null (and sets `errorMessage`, same
  /// `Future<bool>`-shaped-outcome convention as
  /// LeadDetailController.assignLead/deleteLead, just returning the
  /// richer per-lead result instead of a bare bool) if the request
  /// itself failed to even reach the server; a non-null result can still
  /// carry per-lead failures (§"return per-lead success/failure
  /// information when practical") without this having failed.
  Future<BulkActionResult?> runBulkAction({required LeadBulkAction action, String? memberId, String? statusId}) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null || state.selectedIds.isEmpty) return null;

    try {
      final result = await _repository.bulkAction(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadIds: state.selectedIds.toList(),
        action: action,
        memberId: memberId,
        statusId: statusId,
      );
      state = state.copyWith(selectionMode: false, selectedIds: {}, clearError: true);
      await refresh();
      return result;
    } on AppException catch (e) {
      state = state.copyWith(errorMessage: e.message);
      return null;
    } catch (e) {
      AppLogger.error('Bulk lead action failed', error: e);
      state = state.copyWith(errorMessage: 'Could not complete the bulk action.');
      return null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    disposeRealtime();
    super.dispose();
  }
}
