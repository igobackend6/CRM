import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

/// Centralized application logger.
///
/// Never pass passwords, access/refresh tokens, API keys, Supabase
/// service-role keys, or other sensitive customer data as [message] or
/// [error] — this logger does not redact content, it only routes it.
class AppLogger {
  AppLogger._();

  /// Settings > Enable Log. While true, every line is also kept in a small in-memory buffer so the
  /// member can copy it from Settings > Troubleshooting and send it to support. Off by default; the
  /// buffer is never persisted or uploaded.
  static bool capture = false;

  static const int maxBufferedLines = 500;
  static final List<String> _buffer = <String>[];

  /// The captured lines, oldest first (empty while [capture] has never been on).
  static List<String> get bufferedLines => List.unmodifiable(_buffer);

  static void clearBuffer() => _buffer.clear();

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
    if (capture) {
      _buffer.add('${DateTime.now().toIso8601String()} [${level.name.toUpperCase()}] $message${error == null ? '' : ' | $error'}');
      if (_buffer.length > maxBufferedLines) _buffer.removeRange(0, _buffer.length - maxBufferedLines);
    }
    developer.log(
      message,
      name: 'CRM',
      level: _severity[level]!,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
