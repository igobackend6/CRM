import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

/// Global, feature-agnostic error capture.
///
/// Wires Flutter framework errors and uncaught async errors into
/// [AppLogger]. Feature-specific error handling (mapping a failure to a
/// particular UI state) is added alongside each feature in later phases.
class GlobalErrorHandler {
  GlobalErrorHandler._();

  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error(
        'Uncaught Flutter error: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.error(
        'Uncaught platform error',
        error: error,
        stackTrace: stack,
      );
      return true;
    };
  }
}
