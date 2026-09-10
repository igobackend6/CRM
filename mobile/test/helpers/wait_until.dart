import 'dart:async';

/// Polls [predicate] until it's true, for tests driving async
/// StateNotifier flows without a widget tree to pump.
Future<void> waitUntil(bool Function() predicate, {Duration timeout = const Duration(seconds: 2)}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
