import 'package:mobile/services/api/ai_insight_api_data_source.dart';

class FakeAiInsightApiDataSource implements AiInsightApiDataSource {
  Map<String, dynamic>? getCallInsightResponse;
  Object? getCallInsightError;
  Map<String, dynamic> requestCallAnalysisResponse = const {};
  List<dynamic> listLeadInsightsResponse = const [];
  Map<String, dynamic> askAssistantResponse = const {'available': false, 'answer': null, 'message': 'not available'};

  String? lastCallId;
  String? lastLeadId;
  String? lastQuestion;

  @override
  Future<Map<String, dynamic>?> getCallInsight({required String accessToken, required String workspaceId, required String callId}) async {
    if (getCallInsightError != null) throw getCallInsightError!;
    lastCallId = callId;
    return getCallInsightResponse;
  }

  @override
  Future<Map<String, dynamic>> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId}) async {
    lastCallId = callId;
    return requestCallAnalysisResponse;
  }

  @override
  Future<List<dynamic>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId}) async {
    lastLeadId = leadId;
    return listLeadInsightsResponse;
  }

  @override
  Future<Map<String, dynamic>> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  }) async {
    lastLeadId = leadId;
    lastQuestion = question;
    return askAssistantResponse;
  }
}
