import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/call_ai_insight_state.dart';
import '../../domain/repositories/ai_insight_repository.dart';

/// Call Detail's "AI Insight" section (Phase 20) — loads whatever
/// analysis already exists for this call (if any) and can request a
/// fresh one. Mirrors CallDetailController's own load/error shape;
/// `requestAnalysis` mirrors LeadDetailController.convertToCustomer's
/// `Future<bool>` action convention.
class CallAiInsightController extends StateNotifier<CallAiInsightState> {
  CallAiInsightController(this._repository, this._ref, this.callId) : super(const CallAiInsightState.initial()) {
    load();
  }

  final AiInsightRepository _repository;
  final Ref _ref;
  final String callId;

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: CallAiInsightStatus.loading, clearError: true);
    try {
      final insight = await _repository.getCallInsight(accessToken: context.accessToken, workspaceId: context.workspaceId, callId: callId);
      state = state.copyWith(status: CallAiInsightStatus.loaded, insight: insight, clearInsight: insight == null, clearError: true);
    } on AppException catch (e) {
      state = state.copyWith(status: CallAiInsightStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load AI insight for call $callId', error: e);
      state = state.copyWith(status: CallAiInsightStatus.error, errorMessage: 'Could not load the AI insight.');
    }
  }

  Future<bool> requestAnalysis() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;

    state = state.copyWith(status: CallAiInsightStatus.requesting, clearError: true);
    try {
      final insight = await _repository.requestCallAnalysis(accessToken: context.accessToken, workspaceId: context.workspaceId, callId: callId);
      state = state.copyWith(status: CallAiInsightStatus.loaded, insight: insight, clearError: true);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(status: CallAiInsightStatus.loaded, errorMessage: e.message);
      return false;
    } catch (e) {
      AppLogger.error('Failed to request AI analysis for call $callId', error: e);
      state = state.copyWith(status: CallAiInsightStatus.loaded, errorMessage: 'Could not request AI analysis.');
      return false;
    }
  }
}
