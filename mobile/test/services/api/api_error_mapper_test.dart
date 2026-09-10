import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/services/api/api_error_mapper.dart';

DioException _withStatus(int? statusCode, {DioExceptionType type = DioExceptionType.badResponse, dynamic data}) {
  final requestOptions = RequestOptions(path: '/api/v1/workspaces/w1/leads');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null ? null : Response(requestOptions: requestOptions, statusCode: statusCode, data: data),
  );
}

void main() {
  group('mapDioExceptionToAppException', () {
    test('401 -> AuthException', () {
      expect(mapDioExceptionToAppException(_withStatus(401)), isA<AuthException>());
    });

    test('403 -> PermissionDeniedException', () {
      expect(mapDioExceptionToAppException(_withStatus(403)), isA<PermissionDeniedException>());
    });

    test('404 -> NotFoundException', () {
      expect(mapDioExceptionToAppException(_withStatus(404)), isA<NotFoundException>());
    });

    test('409 -> ConflictException', () {
      expect(mapDioExceptionToAppException(_withStatus(409)), isA<ConflictException>());
    });

    test('422 -> ValidationException', () {
      expect(mapDioExceptionToAppException(_withStatus(422)), isA<ValidationException>());
    });

    test('500 -> NetworkException (retryable)', () {
      expect(mapDioExceptionToAppException(_withStatus(500)), isA<NetworkException>());
    });

    test('connection error with no response -> NetworkException', () {
      final result = mapDioExceptionToAppException(_withStatus(null, type: DioExceptionType.connectionError));
      expect(result, isA<NetworkException>());
    });

    test('uses the server-provided message when present', () {
      final result = mapDioExceptionToAppException(_withStatus(403, data: {'message': 'Missing permission: leads.delete'}));
      expect(result.message, 'Missing permission: leads.delete');
    });
  });
}
