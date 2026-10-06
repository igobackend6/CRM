import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/settings/presentation/screens/troubleshooting_screen.dart';

import 'settings_fakes.dart';

Future<void> _pump(WidgetTester tester, {int? pingMs = 42}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = settingsContainer(ping: FakeServerPing(pingMs));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: TroubleshootingScreen())));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
  });

  testWidgets('reports a reachable server, and that nobody is signed in or has a workspace here', (tester) async {
    await _pump(tester);

    expect(find.text('Reachable (42 ms)'), findsOneWidget);
    expect(find.text('Not signed in. Sign in again.'), findsOneWidget);
    expect(find.text('No workspace is selected.'), findsOneWidget);
    expect(find.text('Off. Turn on "Enable Log" in Settings to capture one.'), findsOneWidget);
  });

  testWidgets('an unreachable server is flagged as a problem with advice', (tester) async {
    await _pump(tester, pingMs: null);

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsWidgets);
  });

  testWidgets('copying with an empty log tells the member how to capture one', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('copy-log')));
    await tester.pump();

    expect(find.textContaining('The log is empty'), findsOneWidget);
  });

  testWidgets('copying puts the captured lines on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    AppLogger.capture = true;
    AppLogger.info('first line');
    AppLogger.warning('second line');
    await _pump(tester);

    await tester.tap(find.byKey(const Key('copy-log')));
    await tester.pump();

    expect(copied, contains('first line'));
    expect(copied, contains('[WARNING] second line'));
    expect(find.textContaining('Copied 2 log lines'), findsOneWidget);
  });

  testWidgets('Clear log empties the buffer', (tester) async {
    AppLogger.capture = true;
    AppLogger.info('something');
    await _pump(tester);

    await tester.tap(find.byKey(const Key('clear-log')));
    await tester.pumpAndSettle();

    expect(AppLogger.bufferedLines, isEmpty);
  });

  testWidgets('Run checks again re-runs them', (tester) async {
    await _pump(tester);
    expect(find.text('Reachable (42 ms)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-checks')));
    await tester.pumpAndSettle();

    expect(find.text('Reachable (42 ms)'), findsOneWidget);
  });
}
