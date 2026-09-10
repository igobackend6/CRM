import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/report_date_range.dart';
import '../../domain/entities/team_report_state.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';

/// Team report — loading/success/empty/error + pull-to-refresh +
/// offset-pagination for the member rows, same shape as
/// ActivityListController. Re-fetches from the top whenever the
/// workspace or the shared date-range filter changes (selecting a new
/// range mid-list would otherwise mix rows computed over two different
/// windows).
class TeamReportController extends StateNotifier<TeamReportState> {
  TeamReportController(this._repository, this._ref) : super(const TeamReportState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    _ref.listen<ReportDateFilter>(reportDateFilterProvider, (previous, next) {
      if (previous != next) refresh();
    });
  }

  final ReportsRepository _repository;
  final Ref _ref;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    final filter = _ref.read(reportDateFilterProvider);

    final isFirstLoad = state.status == TeamReportStatus.initial;
    state = state.copyWith(status: isFirstLoad ? TeamReportStatus.loading : TeamReportStatus.refreshing, clearError: true);

    try {
      final page = await _repository.getTeamReport(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        range: filter.range.apiValue,
        since: filter.customSince,
        until: filter.customUntil,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? TeamReportStatus.empty : TeamReportStatus.success,
        items: page.items,
        total: page.total,
        totals: page.totals,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: TeamReportStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load the team report', error: e);
      state = state.copyWith(status: TeamReportStatus.error, errorMessage: 'Could not load the team report.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == TeamReportStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    final filter = _ref.read(reportDateFilterProvider);

    state = state.copyWith(status: TeamReportStatus.loadingMore);
    try {
      final page = await _repository.getTeamReport(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        range: filter.range.apiValue,
        since: filter.customSince,
        until: filter.customUntil,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: TeamReportStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: TeamReportStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more of the team report', error: e);
      state = state.copyWith(status: TeamReportStatus.success, errorMessage: 'Could not load more team members.');
    }
  }
}
