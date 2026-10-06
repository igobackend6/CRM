import 'package:dio/dio.dart';

import '../../../services/api/api_client.dart';

/// Measures a round trip to the CRM backend's public health endpoint (no sign-in needed). Behind an
/// abstraction so tests don't need a network.
abstract class ServerPing {
  /// Milliseconds the server took to answer, or null when it could not be reached.
  Future<int?> pingMilliseconds();
}

class ApiServerPing implements ServerPing {
  @override
  Future<int?> pingMilliseconds() async {
    final watch = Stopwatch()..start();
    try {
      await ApiClient.instance.get<void>(
        '/health',
        options: Options(sendTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6)),
      );
      return watch.elapsedMilliseconds;
    } on DioException {
      return null;
    }
  }
}
