import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI pipeline surface
/// (`/api/v1/workspaces/{workspace_id}/pipeline` and
/// `/api/v1/workspaces/{workspace_id}/leads/{lead_id}/status` —
/// backend/app/api/v1/leads.py). Kept table-agnostic about domain
/// entities on purpose, same split as LeadApiDataSource/
/// DashboardApiDataSource — converting JSON <-> PipelineColumn/Lead is
/// PipelineRepositoryImpl's job.
abstract class PipelineApiDataSource {
  Future<Map<String, dynamic>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  });
}

class DioPipelineApiDataSource implements PipelineApiDataSource {
  DioPipelineApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/pipeline',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'assigned_member_id': ?assignedMemberId,
          'source_id': ?sourceId,
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
  Future<Map<String, dynamic>> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/status',
        data: {'status_id': statusId},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
