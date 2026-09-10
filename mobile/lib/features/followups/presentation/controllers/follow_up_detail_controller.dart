import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/follow_up_detail_state.dart';
import '../../domain/repositories/follow_up_repository.dart';

/// Follow-Up Detail (Phase 7 §2B/§2E) — loads one follow-up and exposes
/// the Complete/Cancel quick actions. Same load-on-workspace-context
/// pattern as LeadDetailController (react to workspace selection rather
/// than loading once at construction time, since selection can still be
/// resolving asynchronously), scoped to a single followUpId via
/// `.family` in the provider.
class FollowUpDetailController extends StateNotifier<FollowUpDetailState> {
  FollowUpDetailController(this._repository, this._ref, this.followUpId) : super(const FollowUpDetailState.loading()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) load();
    }, fireImmediately: true);
  }

  final FollowUpRepository _repository;
  final Ref _ref;
  final String followUpId;

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    state = const FollowUpDetailState.loading();
    try {
      final followUp = await _repository.getFollowUp(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        followUpId: followUpId,
      );
      state = FollowUpDetailState.success(followUp);
    } on NotFoundException {
      state = const FollowUpDetailState.notFound();
    } on AppException catch (e) {
      state = FollowUpDetailState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to load follow-up $followUpId', error: e);
      state = const FollowUpDetailState.error('Could not load this follow-up.');
    }
  }

  Future<bool> updateStatus(String status) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;
    try {
      final updated = await _repository.updateFollowUpStatus(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        followUpId: followUpId,
        status: status,
      );
      state = state.copyWithFollowUp(updated);
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }
}
