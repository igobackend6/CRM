import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/lead_ai_assistant_state.dart';
import '../../domain/repositories/ai_insight_repository.dart';

/// Lead Detail's "AI Assistant" section (Phase 20) — one stateless
/// question at a time; no persisted conversation (see
/// AIAssistantService's own docstring for why). `unavailable` (not
/// `error`) is the expected, honest outcome whenever no AI provider is
/// configured — distinct from a genuine network/permission failure.
class LeadAiAssistantController extends StateNotifier<LeadAiAssistantState> {
  LeadAiAssistantController(this._repository, this._ref, this.leadId) : super(const LeadAiAssistantState.idle());

  final AiInsightRepository _repository;
  final Ref _ref;
  final String leadId;

  Future<void> ask(String question) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null || question.trim().isEmpty) return;

    state = state.copyWith(status: LeadAiAssistantStatus.asking);
    try {
      final result = await _repository.askAssistant(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        question: question.trim(),
      );
      if (result.available) {
        state = state.copyWith(status: LeadAiAssistantStatus.answered, answer: result.answer);
      } else {
        state = state.copyWith(status: LeadAiAssistantStatus.unavailable, message: result.message);
      }
    } on AppException catch (e) {
      state = state.copyWith(status: LeadAiAssistantStatus.error, message: e.message);
    } catch (e) {
      AppLogger.error('Failed to ask the AI assistant for lead $leadId', error: e);
      state = state.copyWith(status: LeadAiAssistantStatus.error, message: 'Could not reach the AI assistant.');
    }
  }
}
