import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

/// Centralized application logger.
///
/// Never pass passwords, access/refresh tokens, API keys, Supabase
/// service-role keys, or other sensitive customer data as [message] or
/// [error] — this logger does not redact content, it only routes it.
class AppLogger {
  AppLogger._();

  static const Map<LogLevel, int> _severity = {
    LogLevel.debug: 500,
    LogLevel.info: 800,
    LogLevel.warning: 900,
    LogLevel.error: 1000,
  };

  static void debug(String message) => _log(LogLevel.debug, message);

  static void info(String message) => _log(LogLevel.info, message);

  static void warning(String message) => _log(LogLevel.warning, message);

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'CRM',
      level: _severity[level]!,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
