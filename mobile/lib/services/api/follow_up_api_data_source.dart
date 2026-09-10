import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI follow-ups surface
/// (`/api/v1/workspaces/{workspace_id}/...` — backend/app/api/v1/followups.py
/// and the lead-nested GET in backend/app/api/v1/leads.py). Kept
/// table-agnostic about domain entities, same split as
/// lead_api_data_source.dart — converting JSON <-> FollowUp is
/// FollowUpRepositoryImpl's job.
abstract class FollowUpApiDataSource {
  Future<Map<String, dynamic>> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> getFollowUp({required String accessToken, required String workspaceId, required String followUpId});

  Future<Map<String, dynamic>> createFollowUp({required String accessToken, required String workspaceId, required Map<String, dynamic> body});

  Future<Map<String, dynamic>> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required Map<String, dynamic> body,
  });

  Future<List<dynamic>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId});
}

class DioFollowUpApiDataSource implements FollowUpApiDataSource {
  DioFollowUpApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/follow-ups',
        queryParameters: {
          'lead_id': ?leadId,
          'status': ?status,
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
  Future<Map<String, dynamic>> getFollowUp({required String accessToken, required String workspaceId, required String followUpId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/follow-ups/$followUpId',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createFollowUp({
    required String accessToken,
    required String workspaceId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/follow-ups',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${_base(workspaceId)}/follow-ups/$followUpId',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/follow-ups',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
