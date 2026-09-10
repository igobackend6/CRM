import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw calls for `/api/v1/device-tokens` (backend/app/api/v1/device_tokens.py).
/// Not workspace-scoped — a token belongs to the person.
abstract class DeviceTokenApiDataSource {
  Future<void> register({required String accessToken, required String token, required String platform});
  Future<void> deregister({required String accessToken, required String token});
}

class DioDeviceTokenApiDataSource implements DeviceTokenApiDataSource {
  DioDeviceTokenApiDataSource([Dio? dio]) : _dio = dio;

  // Resolved lazily: this data source is constructed at app boot (the
  // push registrar is booted from the router's auth listener), which is
  // before `AppConfig.load()` completes in a widget test. Touching
  // `ApiClient.instance` eagerly would throw there. No real call happens
  // until a device actually has an FCM token to register.
  final Dio? _dio;
  Dio get _client => _dio ?? ApiClient.instance;

  @override
  Future<void> register({required String accessToken, required String token, required String platform}) async {
    try {
      await _client.put<void>(
        '/api/v1/device-tokens',
        data: {'token': token, 'platform': platform},
        options: ApiClient.authOptions(accessToken),
      );
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> deregister({required String accessToken, required String token}) async {
    try {
      await _client.delete<void>('/api/v1/device-tokens/$token', options: ApiClient.authOptions(accessToken));
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
