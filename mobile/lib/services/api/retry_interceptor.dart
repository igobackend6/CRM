import 'dart:async';

import 'package:dio/dio.dart';

/// Gives a request that failed for a reason that usually passes by itself a second and third chance:
/// a dropped connection, a timeout on a slow or switching network (Wi-Fi <-> mobile data), a
/// serverless function waking up, or a 502/503/504 from the host. Only requests that are safe to repeat
/// are retried (reads, and the activity heartbeat); a write is never repeated, so nothing is saved twice.
///
/// Waits a little longer each time (0.6 s, then 1.8 s) so a network that is just coming back is not
/// hammered. Anything else (a 401, 403, 404, 422, a real 500) is returned at once.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.retries = 2, this.baseDelay = const Duration(milliseconds: 600), Future<void> Function(Duration)? wait})
      : _wait = wait ?? Future<void>.delayed;

  final Dio _dio;
  final int retries;
  final Duration baseDelay;
  final Future<void> Function(Duration) _wait;

  static const _attemptKey = 'retry_attempt';

  /// Reads are always safe to repeat; the heartbeat is an idempotent "I'm here" ping.
  static bool isSafeToRepeat(RequestOptions options) =>
      options.method.toUpperCase() == 'GET' || options.path.endsWith('/activity/heartbeat');

  static bool isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        return status == 502 || status == 503 || status == 504;
      default:
        return false;
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    if (!isTransient(err) || !isSafeToRepeat(options) || attempt >= retries) {
      return handler.next(err);
    }
    await _wait(baseDelay * (attempt == 0 ? 1 : 3));
    options.extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
