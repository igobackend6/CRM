import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI rechurn surface
/// (`/api/v1/workspaces/{workspace_id}/rechurn` —
/// backend/app/api/v1/rechurn.py). Kept table-agnostic about domain
/// entities on purpose, same split as PipelineApiDataSource/
/// LeadApiDataSource — converting JSON <-> RechurnLeadCard is
/// RechurnRepositoryImpl's job. Rechurn *actions* (call, status change,
/// follow-up) are deliberately not here — they reuse the existing pipeline/
/// call/follow-up data sources unchanged (see RechurnListController).
abstract class RechurnApiDataSource {
  Future<Map<String, dynamic>> getQueue({
    required String accessToken,
    required String workspaceId,
    String? segment,
    int inactiveDays = 30,
    String? assignedMemberId,
    String? priority,
    String? statusId,
    String? sourceId,
    String? search,
    required int limit,
    required int offset,
  });
}

class DioRechurnApiDataSource implements RechurnApiDataSource {
  DioRechurnApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> getQueue({
    required String accessToken,
    required String workspaceId,
    String? segment,
    int inactiveDays = 30,
    String? assignedMemberId,
    String? priority,
    String? statusId,
    String? sourceId,
    String? search,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/rechurn',
        queryParameters: {
          'segment': ?segment,
          'inactive_days': inactiveDays,
          'assigned_member_id': ?assignedMemberId,
          'priority': ?priority,
          'status_id': ?statusId,
          'source_id': ?sourceId,
          if (search != null && search.isNotEmpty) 'search': search,
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
}
