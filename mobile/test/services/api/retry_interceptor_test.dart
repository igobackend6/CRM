import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/api/api_error_mapper.dart';
import 'package:mobile/services/api/retry_interceptor.dart';

/// Plays back a scripted list of outcomes: a status code, or a thrown connection error.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script; // int status, or DioExceptionType
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final step = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (step is DioExceptionType) throw DioException(requestOptions: options, type: step);
    return ResponseBody.fromString('{"ok":true}', step as int, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_ScriptedAdapter adapter, List<Duration> waits) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  dio.interceptors.add(RetryInterceptor(dio, wait: (d) async => waits.add(d)));
  return dio;
}

void main() {
  test('a read that fails on a bad connection is tried again and then succeeds', () async {
    final adapter = _ScriptedAdapter([DioExceptionType.connectionError, DioExceptionType.connectionTimeout, 200]);
    final waits = <Duration>[];
    final response = await _dio(adapter, waits).get<dynamic>('/leads');
    expect(response.statusCode, 200);
    expect(adapter.calls, 3);
    expect(waits, [const Duration(milliseconds: 600), const Duration(milliseconds: 1800)], reason: 'waits longer each time');
  });

  test('it gives up after two retries and reports the network error', () async {
    final adapter = _ScriptedAdapter([DioExceptionType.connectionError]);
    await expectLater(_dio(adapter, []).get<dynamic>('/leads'), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('a 503 from the host is retried; a 401 / 422 / 500 is not', () async {
    final a503 = _ScriptedAdapter([503, 200]);
    expect((await _dio(a503, []).get<dynamic>('/x')).statusCode, 200);
    expect(a503.calls, 2);
    for (final code in [401, 422, 500]) {
      final adapter = _ScriptedAdapter([code, 200]);
      await expectLater(_dio(adapter, []).get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(adapter.calls, 1, reason: 'status $code is a real answer, not a glitch');
    }
  });

  test('a write is never repeated, so nothing is saved twice', () async {
    final adapter = _ScriptedAdapter([DioExceptionType.connectionError, 200]);
    await expectLater(_dio(adapter, []).post<dynamic>('/leads', data: {'name': 'x'}), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('the activity heartbeat is repeated like a read', () async {
    final adapter = _ScriptedAdapter([DioExceptionType.connectionError, 200]);
    final response = await _dio(adapter, []).post<dynamic>('/api/v1/workspaces/w/activity/heartbeat');
    expect(response.statusCode, 200);
    expect(adapter.calls, 2);
  });

  test('no connection says so and suggests checking the internet', () {
    final error = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
    expect(mapDioExceptionToAppException(error).message, contains('internet connection'));
    final slow = DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.receiveTimeout);
    expect(mapDioExceptionToAppException(slow).message, 'Could not reach the server. Please try again.');
  });
}
