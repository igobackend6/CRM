import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';

/// Central Dio -> AppException mapper, shared by every backend-calling
/// data source (Phase 5 §13's 401/403/404/409/422/network/500 cases).
/// Pure, so it's unit-testable without real HTTP transport — same rule
/// as me_api_data_source.dart's mapDioExceptionToMeResult. Extends the
/// existing error-handling system (core/errors/app_exception.dart)
/// rather than introducing a second one.
AppException mapDioExceptionToAppException(DioException error) {
  final statusCode = error.response?.statusCode;
  final body = error.response?.data;
  final serverMessage = body is Map ? body['message'] as String? : null;

  switch (statusCode) {
    case 401:
      return AuthException(serverMessage ?? 'Your session has expired. Please sign in again.', cause: error);
    case 403:
      return PermissionDeniedException(serverMessage ?? 'You do not have permission to do that.', cause: error);
    case 404:
      return NotFoundException(serverMessage ?? 'Not found.', cause: error);
    case 409:
      return ConflictException(serverMessage ?? 'This conflicts with existing data.', cause: error);
    case 422:
      return ValidationException(serverMessage ?? 'Some fields are invalid.', cause: error);
  }

  // Timeouts, no connection, DNS failure, 5xx, or anything else — all
  // treated as retryable rather than a specific client-input problem.
  return NetworkException(serverMessage ?? 'Could not reach the server. Please try again.', cause: error);
}
