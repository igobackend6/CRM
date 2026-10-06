import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/call_analytics_period.dart';
import 'package:mobile/features/analytics/presentation/widgets/analytics_period_sheet.dart';

// Wednesday 23 Sep 2026.
final _now = DateTime(2026, 9, 23, 15, 30);

/// Opens the sheet from a button and records what it resolved to.
class _Harness {
  CallAnalyticsPeriod? result;
  bool resolved = false;
}

Future<_Harness> _open(WidgetTester tester, {required CallAnalyticsPeriod current}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              harness.result = await showCallAnalyticsPeriodSheet(context, current: current, now: _now);
              harness.resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tapKind(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byKey(const Key('period-kind')), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('period-apply')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Apply with no change returns the period it opened with', (tester) async {
    final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));

    await _apply(tester);

    expect(harness.result, CallAnalyticsPeriod.day(_now));
  });

  testWidgets('Cancel resolves to null', (tester) async {
    final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));

    await tester.tap(find.byKey(const Key('period-cancel')));
    await tester.pumpAndSettle();

    expect(harness.resolved, isTrue);
    expect(harness.result, isNull);
  });

  group('day', () {
    testWidgets('shows the month and year of the selected day', (tester) async {
      await _open(tester, current: CallAnalyticsPeriod.today(_now));

      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets('tapping an earlier day selects it', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));

      await tester.tap(find.byKey(const Key('period-day-10')));
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.day(DateTime(2026, 9, 10)));
    });

    testWidgets('tapping a future day does nothing', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));

      await tester.tap(find.byKey(const Key('period-day-24')));
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.day(_now), reason: 'the 24th is tomorrow');
    });

    testWidgets('the next-month chevron is disabled on the current month', (tester) async {
      await _open(tester, current: CallAnalyticsPeriod.today(_now));

      expect(tester.widget<IconButton>(find.byKey(const Key('period-next'))).onPressed, isNull);
    });

    testWidgets('the previous-month chevron moves the calendar back, and next comes forward again', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));

      await tester.tap(find.byKey(const Key('period-prev')));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('period-next'))).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('period-day-31')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-next')));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.day(DateTime(2026, 8, 31)));
    });

    testWidgets('going back from January lands in December of the previous year', (tester) async {
      await _open(tester, current: CallAnalyticsPeriod.day(DateTime(2026, 1, 15)));

      await tester.tap(find.byKey(const Key('period-prev')));
      await tester.pumpAndSettle();

      expect(find.text('December 2025'), findsOneWidget);
    });
  });

  group('week', () {
    testWidgets('tapping any day selects the whole Monday-start week around it', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));
      await _tapKind(tester, 'Week');

      await tester.tap(find.byKey(const Key('period-day-16'))); // a Wednesday
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.week(DateTime(2026, 9, 14)));
      expect(harness.result!.start, DateTime(2026, 9, 14));
      expect(harness.result!.end, DateTime(2026, 9, 21));
    });

    testWidgets('switching Day -> Week keeps the same anchor date', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.day(DateTime(2026, 9, 10)));

      await _tapKind(tester, 'Week');
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.week(DateTime(2026, 9, 10)));
    });
  });

  group('month', () {
    testWidgets('shows a 12-month grid for the selected year', (tester) async {
      await _open(tester, current: CallAnalyticsPeriod.today(_now));
      await _tapKind(tester, 'Month');

      expect(find.text('2026'), findsOneWidget);
      for (final name in ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('tapping an earlier month selects it', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));
      await _tapKind(tester, 'Month');

      await tester.tap(find.byKey(const Key('period-month-3')));
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.month(DateTime(2026, 3)));
    });

    testWidgets('a future month cannot be selected', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));
      await _tapKind(tester, 'Month');

      await tester.tap(find.byKey(const Key('period-month-10')));
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.month(_now), reason: 'still September — October is in the future');
    });

    testWidgets('years can be paged back but not past the current one', (tester) async {
      final harness = await _open(tester, current: CallAnalyticsPeriod.today(_now));
      await _tapKind(tester, 'Month');
      expect(tester.widget<IconButton>(find.byKey(const Key('period-next'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('period-prev')));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);

      // Every month of a past year is selectable.
      await tester.tap(find.byKey(const Key('period-month-12')));
      await tester.pumpAndSettle();
      await _apply(tester);

      expect(harness.result, CallAnalyticsPeriod.month(DateTime(2025, 12)));
    });
  });
}
