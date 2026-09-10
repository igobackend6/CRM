import '../entities/ai_assistant_answer.dart';
import '../entities/ai_call_insight.dart';

abstract class AiInsightRepository {
  Future<AiCallInsight?> getCallInsight({required String accessToken, required String workspaceId, required String callId});

  Future<AiCallInsight> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId});

  Future<List<AiCallInsight>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId});

  Future<AiAssistantAnswer> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  });
}
