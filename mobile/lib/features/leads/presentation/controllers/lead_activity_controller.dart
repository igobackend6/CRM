import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../customer360/domain/entities/activity_filter.dart';
import '../../../customer360/domain/entities/timeline_item.dart';
import '../../../customer360/domain/entities/timeline_list_state.dart';
import '../../domain/repositories/lead_repository.dart';
import 'lead_request_context.dart';

/// Phase 15 — Lead Detail's unified activity feed. Deliberately mirrors
/// CustomerTimelineController (Phase 8) method-for-method rather than
/// sharing a base class with it: both are already small, independent
/// StateNotifiers over the same [TimelineListState] shape (matching the
/// rest of this codebase's convention of parallel, not inherited, list
/// controllers — see LeadListController/FollowUpListController/
/// CallListController), and the two differ only in which repository
/// method they call (`LeadRepository.getActivity` vs.
/// `CustomerRepository.getTimeline`) — not worth a shared abstraction for
/// that one call. One instance per lead (`.family`), loaded lazily by
/// LeadDetailScreen's activity section.
class LeadActivityController extends StateNotifier<TimelineListState> {
  LeadActivityController(this._repository, this._ref, this.leadId) : super(const TimelineListState.initial());

  final LeadRepository _repository;
  final Ref _ref;
  final String leadId;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == TimelineListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? TimelineListStatus.loading : TimelineListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.getActivity(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
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
      AppLogger.error('Failed to load activity for lead $leadId', error: e);
      state = state.copyWith(status: TimelineListStatus.error, errorMessage: 'Could not load the activity feed.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == TimelineListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: TimelineListStatus.loadingMore);
    try {
      final page = await _repository.getActivity(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: TimelineListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: TimelineListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more activity for lead $leadId', error: e);
      state = state.copyWith(status: TimelineListStatus.success, errorMessage: 'Could not load more activity.');
    }
  }

  /// §"Activity Filters" — switching the type filter resets pagination
  /// (a fresh first-page load), matching CustomerTimelineController.
  Future<void> setFilter(ActivityFilter filter) {
    state = state.copyWith(filter: filter);
    return refresh();
  }

  /// Prepends a just-created note without a full refetch — mirrors
  /// CustomerTimelineController.prependItem.
  void prependItem(TimelineItem item) {
    state = state.copyWith(status: TimelineListStatus.success, items: [item, ...state.items], total: state.total + 1);
  }
}
