import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/presentation/widgets/analytics_bar_chart.dart';

Future<Offset> _pumpChart(WidgetTester tester, List<double> values) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          // 336 wide = 36px y-axis gutter + 300px of bars, so 3 bars are 100px slots.
          child: SizedBox(
            width: 336,
            child: AnalyticsBarChart(
              values: values,
              xLabels: const ['a', 'b', 'c'],
              yLabel: (v) => v.round().toString(),
              describe: (i) => 'bar $i = ${values[i].round()}',
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getTopLeft(find.descendant(of: find.byType(AnalyticsBarChart), matching: find.byType(CustomPaint)).first);
}

void main() {
  testWidgets('starts with a hint and no selection', (tester) async {
    await _pumpChart(tester, [1, 3, 2]);

    expect(find.text('Tap a bar for details'), findsOneWidget);
  });

  testWidgets('tapping a bar shows its description', (tester) async {
    final origin = await _pumpChart(tester, [1, 3, 2]);

    await tester.tapAt(origin + const Offset(36 + 150, 60)); // middle slot
    await tester.pump();

    expect(find.text('bar 1 = 3'), findsOneWidget);
    expect(find.text('Tap a bar for details'), findsNothing);
  });

  testWidgets('tapping a different bar moves the selection', (tester) async {
    final origin = await _pumpChart(tester, [1, 3, 2]);

    await tester.tapAt(origin + const Offset(36 + 50, 60));
    await tester.pump();
    await tester.tapAt(origin + const Offset(36 + 250, 60));
    await tester.pump();

    expect(find.text('bar 0 = 1'), findsNothing);
    expect(find.text('bar 2 = 2'), findsOneWidget);
  });

  testWidgets('tapping the selected bar again clears the selection', (tester) async {
    final origin = await _pumpChart(tester, [1, 3, 2]);

    await tester.tapAt(origin + const Offset(36 + 150, 60));
    await tester.pump();
    await tester.tapAt(origin + const Offset(36 + 150, 60));
    await tester.pump();

    expect(find.text('Tap a bar for details'), findsOneWidget);
  });

  testWidgets('tapping the y-axis gutter selects nothing', (tester) async {
    final origin = await _pumpChart(tester, [1, 3, 2]);

    await tester.tapAt(origin + const Offset(10, 60));
    await tester.pump();

    expect(find.text('Tap a bar for details'), findsOneWidget);
  });

  testWidgets('an all-zero series renders without error', (tester) async {
    await _pumpChart(tester, [0, 0, 0]);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a selection is dropped when the data shrinks beneath it', (tester) async {
    final origin = await _pumpChart(tester, [1, 3, 2]);
    await tester.tapAt(origin + const Offset(36 + 250, 60));
    await tester.pump();
    expect(find.text('bar 2 = 2'), findsOneWidget);

    await _pumpChart(tester, [1, 3]);

    expect(find.text('Tap a bar for details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
