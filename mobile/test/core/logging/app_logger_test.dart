import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';

void main() {
  tearDown(() {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
  });

  test('nothing is kept while capture is off', () {
    AppLogger.info('ignored');
    expect(AppLogger.bufferedLines, isEmpty);
  });

  test('captured lines carry the level and the message', () {
    AppLogger.capture = true;
    AppLogger.warning('careful');
    AppLogger.error('boom', error: 'details');

    expect(AppLogger.bufferedLines, hasLength(2));
    expect(AppLogger.bufferedLines[0], contains('[WARNING] careful'));
    expect(AppLogger.bufferedLines[1], contains('[ERROR] boom | details'));
  });

  test('only the newest lines are kept', () {
    AppLogger.capture = true;
    for (var i = 0; i < AppLogger.maxBufferedLines + 25; i++) {
      AppLogger.info('line $i');
    }

    final lines = AppLogger.bufferedLines;
    expect(lines, hasLength(AppLogger.maxBufferedLines));
    expect(lines.first, contains('line 25'));
    expect(lines.last, contains('line ${AppLogger.maxBufferedLines + 24}'));
  });

  test('clearBuffer empties it', () {
    AppLogger.capture = true;
    AppLogger.info('x');
    AppLogger.clearBuffer();
    expect(AppLogger.bufferedLines, isEmpty);
  });
}
