import '../../../services/api/ai_insight_api_data_source.dart';
import '../domain/entities/ai_assistant_answer.dart';
import '../domain/entities/ai_call_insight.dart';
import '../domain/repositories/ai_insight_repository.dart';

class AiInsightRepositoryImpl implements AiInsightRepository {
  AiInsightRepositoryImpl(this._dataSource);

  final AiInsightApiDataSource _dataSource;

  @override
  Future<AiCallInsight?> getCallInsight({required String accessToken, required String workspaceId, required String callId}) async {
    final json = await _dataSource.getCallInsight(accessToken: accessToken, workspaceId: workspaceId, callId: callId);
    return json != null ? AiCallInsight.fromJson(json) : null;
  }

  @override
  Future<AiCallInsight> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId}) async {
    final json = await _dataSource.requestCallAnalysis(accessToken: accessToken, workspaceId: workspaceId, callId: callId);
    return AiCallInsight.fromJson(json);
  }

  @override
  Future<List<AiCallInsight>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId}) async {
    final json = await _dataSource.listLeadInsights(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return json.cast<Map<String, dynamic>>().map(AiCallInsight.fromJson).toList();
  }

  @override
  Future<AiAssistantAnswer> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  }) async {
    final json = await _dataSource.askAssistant(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, question: question);
    return AiAssistantAnswer.fromJson(json);
  }
}
