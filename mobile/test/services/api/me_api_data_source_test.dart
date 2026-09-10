import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/api/me_api_data_source.dart';

DioException _withStatus(int? statusCode, {DioExceptionType type = DioExceptionType.badResponse}) {
  final requestOptions = RequestOptions(path: '/api/v1/me');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null ? null : Response(requestOptions: requestOptions, statusCode: statusCode),
  );
}

void main() {
  group('mapDioExceptionToMeResult', () {
    test('401 -> BackendMeUnauthorized', () {
      expect(mapDioExceptionToMeResult(_withStatus(401)), isA<BackendMeUnauthorized>());
    });

    test('403 -> BackendMeForbidden', () {
      expect(mapDioExceptionToMeResult(_withStatus(403)), isA<BackendMeForbidden>());
    });

    test('connection failure (no response) -> BackendMeNetworkError', () {
      final result = mapDioExceptionToMeResult(
        _withStatus(null, type: DioExceptionType.connectionError),
      );
      expect(result, isA<BackendMeNetworkError>());
    });

    test('other status codes -> BackendMeNetworkError, not mistaken for auth failure', () {
      expect(mapDioExceptionToMeResult(_withStatus(500)), isA<BackendMeNetworkError>());
    });
  });

  group('BackendMeResult', () {
    test('a 200 response is represented as BackendMeSuccess with the body', () {
      const result = BackendMeSuccess({'id': 'u1', 'email': 'a@b.com'});
      expect(result.data['id'], 'u1');
    });
  });
}
