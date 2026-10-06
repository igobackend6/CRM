import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/analytics/presentation/screens/customer_analytics_screen.dart';
import 'package:mobile/features/analytics/presentation/widgets/analytics_stat_tile.dart';
import 'package:mobile/features/reports/domain/entities/pipeline_report.dart';
import 'package:mobile/features/reports/domain/entities/pipeline_snapshot.dart';

import '../reports/fake_reports_repository.dart';
import 'analytics_test_helpers.dart';

Future<void> _pump(WidgetTester tester, FakeReportsRepository repo, {String role = 'team_mate', FakeFileSaver? saver}) async {
  // A funnel of several stage cards is taller than the default 800x600.
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpAnalytics(tester, screen: const CustomerAnalyticsScreen(), repository: repo, role: role, saver: saver);
}

/// Taps the download button, then lets the export run as far as the saver.
/// Building the PDF loads the bundled font from disk, which is real async
/// I/O that pump alone does not advance under FakeAsync, so the wait is in
/// real time.
Future<void> _tapDownload(WidgetTester tester, FakeFileSaver saver) async {
  await tester.tap(find.byKey(const Key('export-conversion-funnel')));
  await tester.runAsync(() async {
    for (var i = 0; i < 300 && saver.callCount == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Every text inside the summary tiles (value and label of each).
List<String?> _tileTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.descendant(of: find.byType(AnalyticsStatTile), matching: find.byType(Text))).map((t) => t.data).toList();

void main() {
  group('a team_mate sees their own pipeline', () {
    testWidgets('from the personal report, never asking for the workspace-wide one', (tester) async {
      // If the screen wrongly asked for the pipeline report the screen would show an error.
      final repo = FakeReportsRepository()..pipelineError = const PermissionDeniedException('nope');

      await _pump(tester, repo, role: 'team_mate');

      expect(find.text('Your pipeline'), findsOneWidget);
      expect(find.text('Could not load customer analytics.'), findsNothing);
    });

    testWidgets('shows customers, active pipeline and lost from the snapshot', (tester) async {
      final repo = FakeReportsRepository()
        ..personalReportToReturn = testPersonalReport(); // customers 2, active 2, lost 1

      await _pump(tester, repo);

      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('In pipeline'), findsOneWidget);
      expect(find.text('Lost'), findsOneWidget);
      final values = _tileTexts(tester);
      expect(values, containsAll(['2', '2', '1']));
    });
  });

  group('a manager sees the team pipeline', () {
    testWidgets('from the pipeline report, never asking for the personal one', (tester) async {
      final repo = FakeReportsRepository()..personalError = const NetworkException('should not be called');

      await _pump(tester, repo, role: 'manager');

      expect(find.text('Team pipeline'), findsOneWidget);
      expect(find.text('Could not load customer analytics.'), findsNothing);
    });

    testWidgets('shows converted customers, active leads and lost from the report', (tester) async {
      final repo = FakeReportsRepository(); // converted 3, active 4, lost 1

      await _pump(tester, repo, role: 'manager');

      final values = _tileTexts(tester);
      expect(values, containsAll(['3', '4', '1']));
    });

    for (final role in ['admin', 'ceo']) {
      testWidgets('$role gets the team pipeline as well', (tester) async {
        await _pump(tester, FakeReportsRepository(), role: role);

        expect(find.text('Team pipeline'), findsOneWidget);
      });
    }
  });

  group('the funnel', () {
    PipelineReport report(List<PipelineStatusItem> items) => PipelineReport(
          range: 'all_time',
          leadsByStatus: items,
          convertedCustomers: 0,
          lostLeads: 0,
          activeLeads: 0,
          sourcePerformance: const [],
          priorityDistribution: const [],
        );

    testWidgets('groups statuses under their stage, in pipeline order, with counts and share', (tester) async {
      final repo = FakeReportsRepository()
        ..pipelineReportToReturn = report([
          PipelineStatusItem(status: testStatus(id: 'l', name: 'Lost deal', stage: 'closed_lost'), count: 1, percentage: 10),
          PipelineStatusItem(status: testStatus(id: 'n', name: 'New', stage: 'start'), count: 6, percentage: 60),
          PipelineStatusItem(status: testStatus(id: 'c', name: 'Contacted', stage: 'in_progress'), count: 3, percentage: 30),
        ]);

      await _pump(tester, repo, role: 'manager');

      expect(find.byKey(const Key('funnel-stage-start')), findsOneWidget);
      expect(find.byKey(const Key('funnel-stage-in_progress')), findsOneWidget);
      expect(find.byKey(const Key('funnel-stage-closed_lost')), findsOneWidget);
      // No won stage was configured, so none is drawn.
      expect(find.byKey(const Key('funnel-stage-closed_won')), findsNothing);

      expect(find.text('6 · 60%'), findsOneWidget); // start: 6 of 10
      expect(find.text('3 · 30%'), findsOneWidget);
      expect(find.text('1 · 10%'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Contacted'), findsOneWidget);
      expect(find.text('Lost deal'), findsOneWidget);

      // Start is drawn above In progress, which is above Lost.
      final startY = tester.getTopLeft(find.byKey(const Key('funnel-stage-start'))).dy;
      final progressY = tester.getTopLeft(find.byKey(const Key('funnel-stage-in_progress'))).dy;
      final lostY = tester.getTopLeft(find.byKey(const Key('funnel-stage-closed_lost'))).dy;
      expect(startY, lessThan(progressY));
      expect(progressY, lessThan(lostY));
    });

    testWidgets('explains what the counts mean', (tester) async {
      await _pump(tester, FakeReportsRepository());

      expect(find.text('Leads created in the selected period, by their current status.'), findsOneWidget);
    });

    testWidgets('an empty pipeline shows a message instead of an empty funnel', (tester) async {
      final repo = FakeReportsRepository()..personalReportToReturn = testPersonalReport(pipeline: PipelineSnapshot.empty);

      await _pump(tester, repo);

      expect(find.text('No pipeline stages are configured yet.'), findsOneWidget);
    });

    testWidgets('a zero-lead status is still drawn, without dividing by zero', (tester) async {
      final repo = FakeReportsRepository()
        ..pipelineReportToReturn = report([PipelineStatusItem(status: testStatus(name: 'New', stage: 'start'), count: 0, percentage: 0)]);

      await _pump(tester, repo, role: 'manager');

      expect(find.text('New'), findsOneWidget);
      expect(find.text('0 · 0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the Conversion Funnel heading and download', () {
    testWidgets('the top heading is Conversion Funnel with an icon, and the scope sits under it', (tester) async {
      await _pump(tester, FakeReportsRepository());

      expect(find.text('Conversion Funnel'), findsOneWidget);
      expect(find.byIcon(Icons.stacked_line_chart), findsOneWidget);
      expect(find.text('Your pipeline'), findsOneWidget); // scope caption, no longer the heading
    });

    testWidgets('a download icon sits beside the heading', (tester) async {
      await _pump(tester, FakeReportsRepository());

      final button = find.byKey(const Key('export-conversion-funnel'));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.byIcon(Icons.file_download_outlined)), findsOneWidget);
      expect(tester.widget<IconButton>(button).tooltip, 'Download PDF');
      // Same row as the heading.
      expect((tester.getCenter(button).dy - tester.getCenter(find.text('Conversion Funnel')).dy).abs(), lessThan(20));
    });

    testWidgets('tapping it saves a PDF named after the range and today, and confirms', (tester) async {
      final saver = FakeFileSaver();
      await _pump(tester, FakeReportsRepository(), saver: saver);

      await _tapDownload(tester, saver);

      final now = DateTime.now();
      String pad(int n) => n.toString().padLeft(2, '0');
      expect(saver.lastFileName, 'conversion-funnel-all-time-${now.year}-${pad(now.month)}-${pad(now.day)}.pdf');
      expect(saver.lastMimeType, 'application/pdf');
      expect(latin1.decode(saver.lastBytes!.sublist(0, 5)), '%PDF-');
      expect(find.text('Conversion funnel saved.'), findsOneWidget);
    });

    testWidgets('the file name follows the selected date range', (tester) async {
      final saver = FakeFileSaver();
      await _pump(tester, FakeReportsRepository(), saver: saver);

      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      await _tapDownload(tester, saver);

      expect(saver.lastFileName, startsWith('conversion-funnel-this-week-'));
    });

    testWidgets('a manager can download the team funnel', (tester) async {
      final saver = FakeFileSaver();
      await _pump(tester, FakeReportsRepository(), role: 'manager', saver: saver);

      await _tapDownload(tester, saver);

      expect(saver.callCount, 1);
      expect(latin1.decode(saver.lastBytes!.sublist(0, 5)), '%PDF-');
    });

    testWidgets('an empty pipeline can still be downloaded', (tester) async {
      final saver = FakeFileSaver();
      final repo = FakeReportsRepository()..personalReportToReturn = testPersonalReport(pipeline: PipelineSnapshot.empty);
      await _pump(tester, repo, saver: saver);

      await _tapDownload(tester, saver);

      expect(saver.callCount, 1);
    });

    testWidgets('says nothing when the user cancels the save dialog', (tester) async {
      final saver = FakeFileSaver()..saved = false;
      await _pump(tester, FakeReportsRepository(), saver: saver);

      await _tapDownload(tester, saver);

      expect(find.text('Conversion funnel saved.'), findsNothing);
      expect(find.text('Could not save the file.'), findsNothing);
    });

    testWidgets('reports a failure to save instead of crashing', (tester) async {
      final saver = FakeFileSaver()..error = Exception('disk full');
      await _pump(tester, FakeReportsRepository(), saver: saver);

      await _tapDownload(tester, saver);

      expect(find.text('Could not save the file.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the button is disabled while the file is being saved, then re-enabled', (tester) async {
      final saver = FakeFileSaver()..hold = Completer<bool>();
      await _pump(tester, FakeReportsRepository(), saver: saver);

      await _tapDownload(tester, saver);
      expect(tester.widget<IconButton>(find.byKey(const Key('export-conversion-funnel'))).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget); // in place of the icon

      saver.hold!.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<IconButton>(find.byKey(const Key('export-conversion-funnel'))).onPressed, isNotNull);
      expect(find.text('Conversion funnel saved.'), findsOneWidget);
    });
  });

  group('date range', () {
    testWidgets('choosing a range chip refetches for it', (tester) async {
      final repo = FakeReportsRepository();
      await _pump(tester, repo);
      expect(repo.lastRange, 'all_time');

      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();

      expect(repo.lastRange, 'this_week');
    });
  });

  group('failure', () {
    testWidgets('shows an error with Retry, and Retry reloads', (tester) async {
      final repo = FakeReportsRepository()..personalError = const NetworkException('offline');
      await _pump(tester, repo);

      expect(find.text('Could not load customer analytics.'), findsOneWidget);

      repo.personalError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Your pipeline'), findsOneWidget);
    });
  });
}
