import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/call_detail_state.dart';
import '../../domain/repositories/call_repository.dart';

/// Call Detail (Phase 9 §3) — loads one call. Same
/// load-on-workspace-context pattern as FollowUpDetailController, scoped
/// to a single callId via `.family` in the provider.
class CallDetailController extends StateNotifier<CallDetailState> {
  CallDetailController(this._repository, this._ref, this.callId) : super(const CallDetailState.loading()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) load();
    }, fireImmediately: true);
  }

  final CallRepository _repository;
  final Ref _ref;
  final String callId;

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    state = const CallDetailState.loading();
    try {
      final call = await _repository.getCall(accessToken: context.accessToken, workspaceId: context.workspaceId, callId: callId);
      state = CallDetailState.success(call);
    } on NotFoundException {
      state = const CallDetailState.notFound();
    } on AppException catch (e) {
      state = CallDetailState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to load call $callId', error: e);
      state = const CallDetailState.error('Could not load this call.');
    }
  }
}
