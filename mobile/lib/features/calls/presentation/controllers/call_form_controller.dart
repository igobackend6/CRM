import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/call_draft.dart';
import '../../domain/entities/call_form_state.dart';
import '../../domain/repositories/call_repository.dart';

/// Manual call-log creation (Phase 9 §4). Mirrors FollowUpFormController's
/// shape exactly (create-only here — there is no call edit surface this
/// phase, matching calls_update RLS existing but not being exposed by
/// any endpoint yet outside this repository's read/create surface).
class CallFormController extends StateNotifier<CallFormState> {
  CallFormController(this._repository, this._ref) : super(const CallFormState.idle());

  final CallRepository _repository;
  final Ref _ref;

  Future<void> create(String leadId, CallDraft draft) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) {
      state = const CallFormState.error('No workspace selected.');
      return;
    }
    state = const CallFormState.submitting();
    try {
      final call = await _repository.createCall(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        draft: draft,
      );
      state = CallFormState.success(call);
    } on AppException catch (e) {
      state = CallFormState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to log call', error: e);
      state = const CallFormState.error('Could not log the call.');
    }
  }
}
