import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/ai_insight_api_data_source.dart';
import '../../data/ai_insight_repository_impl.dart';
import '../../domain/entities/call_ai_insight_state.dart';
import '../../domain/entities/lead_ai_assistant_state.dart';
import '../../domain/entities/lead_ai_insights_state.dart';
import '../../domain/repositories/ai_insight_repository.dart';
import '../controllers/call_ai_insight_controller.dart';
import '../controllers/lead_ai_assistant_controller.dart';
import '../controllers/lead_ai_insights_controller.dart';

final aiInsightApiDataSourceProvider = Provider<AiInsightApiDataSource>((ref) => DioAiInsightApiDataSource());

final aiInsightRepositoryProvider = Provider<AiInsightRepository>((ref) {
  return AiInsightRepositoryImpl(ref.watch(aiInsightApiDataSourceProvider));
});

final callAiInsightControllerProvider =
    StateNotifierProvider.autoDispose.family<CallAiInsightController, CallAiInsightState, String>((ref, callId) {
  return CallAiInsightController(ref.watch(aiInsightRepositoryProvider), ref, callId);
});

final leadAiInsightsControllerProvider =
    StateNotifierProvider.autoDispose.family<LeadAiInsightsController, LeadAiInsightsState, String>((ref, leadId) {
  return LeadAiInsightsController(ref.watch(aiInsightRepositoryProvider), ref, leadId);
});

final leadAiAssistantControllerProvider =
    StateNotifierProvider.autoDispose.family<LeadAiAssistantController, LeadAiAssistantState, String>((ref, leadId) {
  return LeadAiAssistantController(ref.watch(aiInsightRepositoryProvider), ref, leadId);
});
