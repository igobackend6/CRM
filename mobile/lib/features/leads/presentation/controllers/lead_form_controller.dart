import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lead_draft.dart';
import '../../domain/entities/lead_form_state.dart';
import '../../domain/repositories/lead_repository.dart';
import 'lead_request_context.dart';

/// Shared by both create and edit (Phase 5 §3/§4) — the form screen
/// decides which method to call based on whether it has a leadId.
class LeadFormController extends StateNotifier<LeadFormState> {
  LeadFormController(this._repository, this._ref) : super(const LeadFormState.idle());

  final LeadRepository _repository;
  final Ref _ref;

  Future<void> create(LeadDraft draft) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) {
      state = const LeadFormState.error('No workspace selected.');
      return;
    }
    state = const LeadFormState.submitting();
    try {
      final lead = await _repository.createLead(accessToken: context.accessToken, workspaceId: context.workspaceId, draft: draft);
      state = LeadFormState.success(lead);
    } on AppException catch (e) {
      state = LeadFormState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to create lead', error: e);
      state = const LeadFormState.error('Could not create the lead.');
    }
  }

  Future<void> update(String leadId, LeadDraft draft) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) {
      state = const LeadFormState.error('No workspace selected.');
      return;
    }
    state = const LeadFormState.submitting();
    try {
      final lead = await _repository.updateLead(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        draft: draft,
      );
      state = LeadFormState.success(lead);
    } on AppException catch (e) {
      state = LeadFormState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to update lead $leadId', error: e);
      state = const LeadFormState.error('Could not save changes.');
    }
  }
}
