import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/pipeline_state.dart';
import '../../domain/repositories/pipeline_repository.dart';

/// Loading/success/empty/error + pull-to-refresh + a server-confirmed
/// status-change action (Phase 12). Reacts to workspace selection rather
/// than loading once at construction, same as LeadListController/
/// LeadDetailController.
class PipelineController extends StateNotifier<PipelineState> with RealtimeRefreshMixin<PipelineState> {
  PipelineController(this._repository, this._ref) : super(const PipelineState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — the board shows every status column at once with no
    // pagination to preserve (§4 docstring below), so any lead/
    // allocation change just debounces a full reload rather than a
    // per-column patch.
    subscribeRealtime(_ref, const {'leads', 'allocations'}, (_) => debouncedRealtimeRefresh(refresh));
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(refresh);

  final PipelineRepository _repository;
  final Ref _ref;
  Timer? _debounce;

  /// Per-column fetch bound — a Kanban board shows every status at
  /// once, so this is generous enough to cover a typical column without
  /// needing client-side "load more" (Phase 12 §"Prefer a simple
  /// efficient pipeline UI").
  static const int _columnLimit = 50;

  Future<void> refresh() async {
    final user = _ref.read(authControllerProvider).user;
    final workspace = _ref.read(workspaceControllerProvider).selected;
    if (user == null || workspace == null) return;

    final isFirstLoad = state.status == PipelineStatus.initial;
    state = state.copyWith(status: isFirstLoad ? PipelineStatus.loading : PipelineStatus.refreshing, clearError: true);

    try {
      final columns = await _repository.getPipeline(
        accessToken: user.accessToken,
        workspaceId: workspace.workspace.id,
        search: state.searchQuery.isEmpty ? null : state.searchQuery,
        limit: _columnLimit,
        offset: 0,
      );
      final hasAnyLead = columns.any((column) => column.leads.isNotEmpty);
      state = state.copyWith(
        status: hasAnyLead ? PipelineStatus.success : PipelineStatus.empty,
        columns: columns,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: PipelineStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load pipeline', error: e);
      state = state.copyWith(status: PipelineStatus.error, errorMessage: 'Could not load the pipeline.');
    }
  }

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  /// Changes [leadId]'s status to [statusId] and refreshes the board so
  /// every column reflects the server's (authoritative) new grouping —
  /// never moved client-side ahead of confirmation, since the server/DB
  /// is the only real source of truth for whether the change was
  /// actually permitted (Phase 12 §"Security"). Returns whether the
  /// change succeeded, so the caller can show a SnackBar on failure —
  /// same `Future<bool>` action convention as LeadDetailController.
  Future<bool> changeStatus({required String leadId, required String statusId}) async {
    final user = _ref.read(authControllerProvider).user;
    final workspace = _ref.read(workspaceControllerProvider).selected;
    if (user == null || workspace == null) return false;

    try {
      await _repository.changeLeadStatus(
        accessToken: user.accessToken,
        workspaceId: workspace.workspace.id,
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
