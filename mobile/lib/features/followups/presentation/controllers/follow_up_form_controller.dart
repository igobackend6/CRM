import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/follow_up_draft.dart';
import '../../domain/entities/follow_up_form_state.dart';
import '../../domain/repositories/follow_up_repository.dart';

/// Shared by Create (§2C) and Edit/Reschedule (§2D) — the form screen
/// decides which method to call based on whether it has a followUpId.
/// Mirrors LeadFormController's shape exactly.
class FollowUpFormController extends StateNotifier<FollowUpFormState> {
  FollowUpFormController(this._repository, this._ref) : super(const FollowUpFormState.idle());

  final FollowUpRepository _repository;
  final Ref _ref;

  Future<void> create(String leadId, FollowUpDraft draft) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) {
      state = const FollowUpFormState.error('No workspace selected.');
      return;
    }
    state = const FollowUpFormState.submitting();
    try {
      final followUp = await _repository.createFollowUp(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        draft: draft,
      );
      state = FollowUpFormState.success(followUp);
    } on AppException catch (e) {
      state = FollowUpFormState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to create follow-up', error: e);
      state = const FollowUpFormState.error('Could not create the follow-up.');
    }
  }

  Future<void> update(String followUpId, FollowUpDraft draft) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) {
      state = const FollowUpFormState.error('No workspace selected.');
      return;
    }
    state = const FollowUpFormState.submitting();
    try {
      final followUp = await _repository.updateFollowUp(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        followUpId: followUpId,
        draft: draft,
      );
      state = FollowUpFormState.success(followUp);
    } on AppException catch (e) {
      state = FollowUpFormState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to save follow-up $followUpId', error: e);
      state = const FollowUpFormState.error('Could not save changes.');
    }
  }
}
