import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI calls surface
/// (`/api/v1/workspaces/{workspace_id}/...` — backend/app/api/v1/calls.py
/// and the lead-nested GET in backend/app/api/v1/leads.py). Kept
/// table-agnostic about domain entities, same split as
/// lead_api_data_source.dart/follow_up_api_data_source.dart — converting
/// JSON <-> Call is CallRepositoryImpl's job.
abstract class CallApiDataSource {
  Future<Map<String, dynamic>> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> getCall({required String accessToken, required String workspaceId, required String callId});

  Future<Map<String, dynamic>> createCall({required String accessToken, required String workspaceId, required Map<String, dynamic> body});

  Future<List<dynamic>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId});

  Future<List<dynamic>> listCallOutcomes({required String accessToken, required String workspaceId});
}

class DioCallApiDataSource implements CallApiDataSource {
  DioCallApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/calls',
        queryParameters: {
          'lead_id': ?leadId,
          'direction': ?direction,
          'limit': limit,
          'offset': offset,
        },
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getCall({required String accessToken, required String workspaceId, required String callId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/calls/$callId',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createCall({
    required String accessToken,
    required String workspaceId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/calls',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/calls',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listCallOutcomes({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '${_base(workspaceId)}/call-outcomes',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
