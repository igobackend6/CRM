import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/lead_ai_insights_state.dart';
import '../../domain/repositories/ai_insight_repository.dart';

/// Lead Detail/Customer 360's "Lead Insights" section (Phase 20) —
/// every AI insight across this lead's own calls. Read-only, loads once
/// per lead (same shape as `leadCallsProvider`'s FutureProvider, but a
/// StateNotifier so the screen can also expose a retry action on
/// failure, matching every other section on these screens).
class LeadAiInsightsController extends StateNotifier<LeadAiInsightsState> {
  LeadAiInsightsController(this._repository, this._ref, this.leadId) : super(const LeadAiInsightsState.initial()) {
    load();
  }

  final AiInsightRepository _repository;
  final Ref _ref;
  final String leadId;

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: LeadAiInsightsStatus.loading);
    try {
      final items = await _repository.listLeadInsights(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: leadId);
      state = state.copyWith(status: items.isEmpty ? LeadAiInsightsStatus.empty : LeadAiInsightsStatus.success, items: items);
    } on AppException catch (e) {
      state = state.copyWith(status: LeadAiInsightsStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load AI insights for lead $leadId', error: e);
      state = state.copyWith(status: LeadAiInsightsStatus.error, errorMessage: 'Could not load lead insights.');
    }
  }
}
