import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI Customer 360 surface
/// (`/api/v1/workspaces/{workspace_id}/customers/...` —
/// backend/app/api/v1/customers.py). Kept table-agnostic about domain
/// entities on purpose, same split as LeadApiDataSource/FollowUpApiDataSource.
abstract class CustomerApiDataSource {
  Future<Map<String, dynamic>> getCustomer({required String accessToken, required String workspaceId, required String customerId});

  Future<Map<String, dynamic>> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  });

  Future<List<dynamic>> listFollowUps({required String accessToken, required String workspaceId, required String customerId});

  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  });
}

class DioCustomerApiDataSource implements CustomerApiDataSource {
  DioCustomerApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId, String customerId) => '/api/v1/workspaces/$workspaceId/customers/$customerId';

  @override
  Future<Map<String, dynamic>> getCustomer({required String accessToken, required String workspaceId, required String customerId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(_base(workspaceId, customerId), options: ApiClient.authOptions(accessToken));
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId, customerId)}/timeline',
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listFollowUps({required String accessToken, required String workspaceId, required String customerId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '${_base(workspaceId, customerId)}/follow-ups',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId, customerId)}/notes',
        data: {'text': text},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
