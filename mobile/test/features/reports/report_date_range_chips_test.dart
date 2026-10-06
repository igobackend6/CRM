import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/reports/domain/entities/report_date_range.dart';
import 'package:mobile/features/reports/presentation/widgets/report_date_range_chips.dart';

Future<List<ReportDateFilter>> _pump(WidgetTester tester, {required bool singleRow, ReportDateFilter filter = const ReportDateFilter()}) async {
  final changes = <ReportDateFilter>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReportDateRangeChips(filter: filter, onChanged: changes.add, singleRow: singleRow),
      ),
    ),
  );
  return changes;
}

void main() {
  testWidgets('by default the chips wrap onto multiple rows (the Reports screen layout)', (tester) async {
    await _pump(tester, singleRow: false);

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(ReportDateRange.values.length));
  });

  testWidgets('singleRow puts every chip on one horizontally scrolling line', (tester) async {
    await _pump(tester, singleRow: true);

    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(find.byType(Wrap), findsNothing);
    // Every chip sits on the same baseline — one row, not several.
    final tops = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip, skipOffstage: false)).map((c) => tester.getTopLeft(find.byWidget(c)).dy).toSet();
    expect(tops.length, 1);
  });

  testWidgets('singleRow keeps the later chips reachable by scrolling', (tester) async {
    final changes = await _pump(tester, singleRow: true);

    await tester.scrollUntilVisible(find.text('All time'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Last month'));
    await tester.pump();

    expect(changes.single.range, ReportDateRange.lastMonth);
  });

  testWidgets('singleRow scrolls the selected chip into view, even when it is the last one', (tester) async {
    // A phone-width viewport, so eight chips cannot all fit.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, singleRow: true); // default filter: All time, the last chip
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text('All time'));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.left, greaterThanOrEqualTo(0));
  });

  testWidgets('singleRow follows the selection when it changes', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, singleRow: true, filter: const ReportDateFilter(range: ReportDateRange.allTime));
    await tester.pumpAndSettle();
    await _pump(tester, singleRow: true, filter: const ReportDateFilter(range: ReportDateRange.today));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Today')).left, greaterThanOrEqualTo(0));
  });

  testWidgets('the wrapped layout never scrolls anything (Reports screen unchanged)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, singleRow: false);
    await tester.pumpAndSettle();

    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('the selected chip is marked in both layouts', (tester) async {
    for (final singleRow in [false, true]) {
      await _pump(tester, singleRow: singleRow, filter: const ReportDateFilter(range: ReportDateRange.thisWeek));

      final selected = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip, skipOffstage: false)).where((c) => c.selected).toList();
      expect(selected.length, 1, reason: 'singleRow=$singleRow');
      expect((selected.single.label as Text).data, 'This week');
    }
  });
}
