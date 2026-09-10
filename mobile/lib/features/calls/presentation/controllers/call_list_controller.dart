import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/call_list_state.dart';
import '../../domain/repositories/call_repository.dart';

/// Call Log (Phase 9 §2) — loading/success/empty/error + pull-to-refresh
/// + offset-pagination. Reuses [resolveLeadContext] from the leads
/// feature (session + selected workspace, not lead-specific despite its
/// name/location — see its own docstring), same as
/// FollowUpListController. Optionally scoped to one lead's calls
/// (`leadId`) — powers both the global `/app/calls` list (leadId null)
/// and Lead Detail's "View all calls" (§6), through server-side
/// filtering rather than a second controller/state shape.
class CallListController extends StateNotifier<CallListState> {
  // An initializing formal here would force the public parameter name to
  // match the private field name (`_leadId`), leaking it into every call
  // site; keeping the parameter named `leadId` and assigning it
  // explicitly is intentional.
  CallListController(this._repository, this._ref, {String? leadId})
      // ignore: prefer_initializing_formals
      : _leadId = leadId,
        super(const CallListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
  }

  final CallRepository _repository;
  final Ref _ref;
  final String? _leadId;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == CallListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? CallListStatus.loading : CallListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listCalls(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: _leadId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? CallListStatus.empty : CallListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: CallListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load calls', error: e);
      state = state.copyWith(status: CallListStatus.error, errorMessage: 'Could not load calls.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == CallListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: CallListStatus.loadingMore);
    try {
      final page = await _repository.listCalls(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: _leadId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: CallListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      // Keep the already-loaded items visible; only surface the error.
      state = state.copyWith(status: CallListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more calls', error: e);
      state = state.copyWith(status: CallListStatus.success, errorMessage: 'Could not load more calls.');
    }
  }
}
