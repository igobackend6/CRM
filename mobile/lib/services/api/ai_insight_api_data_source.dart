import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI AI surface (Phase 20 —
/// backend/app/api/v1/ai_insights.py). Kept table-agnostic about domain
/// entities on purpose, same split as every other *ApiDataSource in this
/// app — converting JSON <-> AiCallInsight/AiAssistantAnswer is
/// AiInsightRepositoryImpl's job. Flutter never calls an AI provider
/// directly and never holds a provider key — every request here goes
/// through the backend (§"Architecture Rule").
abstract class AiInsightApiDataSource {
  Future<Map<String, dynamic>?> getCallInsight({required String accessToken, required String workspaceId, required String callId});

  Future<Map<String, dynamic>> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId});

  Future<List<dynamic>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId});

  Future<Map<String, dynamic>> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  });
}

class DioAiInsightApiDataSource implements AiInsightApiDataSource {
  DioAiInsightApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>?> getCallInsight({required String accessToken, required String workspaceId, required String callId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/calls/$callId/ai-insight',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data;
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/calls/$callId/ai-insight',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/ai-insights',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/ai-assistant',
        data: {'question': question},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
