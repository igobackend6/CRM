import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON for `/api/v1/workspaces/{workspace_id}/custom-fields`
/// (backend/app/api/v1/custom_fields.py). The app only reads — field
/// definitions are managed from the Admin panel.
abstract class CustomFieldApiDataSource {
  Future<List<dynamic>> listFields({required String accessToken, required String workspaceId});
}

class DioCustomFieldApiDataSource implements CustomFieldApiDataSource {
  DioCustomFieldApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  @override
  Future<List<dynamic>> listFields({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/workspaces/$workspaceId/custom-fields',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
