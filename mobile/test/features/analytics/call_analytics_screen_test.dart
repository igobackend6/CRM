import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/analytics/domain/call_analytics_period.dart';
import 'package:mobile/features/analytics/presentation/screens/call_analytics_screen.dart';
import 'package:mobile/features/reports/domain/entities/call_trends.dart';

import '../reports/fake_reports_repository.dart';
import 'analytics_test_helpers.dart';

Future<void> _pump(WidgetTester tester, FakeReportsRepository repo, {FakeFileSaver? saver}) =>
    pumpAnalytics(tester, screen: const CallAnalyticsScreen(), repository: repo, saver: saver);

FakeReportsRepository _repoWithCalls() => FakeReportsRepository()
  ..callTrendsToReturn = testCallTrends(callsByIndex: {9: 3, 10: 2}, uniqueLeads: 4, talkTimeSeconds: 190);

void main() {
  group('loading today by default', () {
    testWidgets('shows the totals and asks the backend for today, hourly, overall', (tester) async {
      final repo = _repoWithCalls();

      await _pump(tester, repo);

      expect(find.text('Total Calls'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Total Talk Time'), findsOneWidget);
      expect(find.text('3m 10s'), findsOneWidget);
      expect(find.text('CALL TRENDS'), findsOneWidget);

      final today = CallAnalyticsPeriod.today();
      expect(repo.lastTrendsSince, today.since);
      expect(repo.lastTrendsUntil, today.until);
      expect(repo.lastTrendsGranularity, CallTrendGranularity.hour);
      expect(repo.lastTrendsDirection, CallTrendDirection.all);
    });

    testWidgets('the period button reads "Today" and Overall is the selected direction', (tester) async {
      await _pump(tester, _repoWithCalls());

      expect(find.descendant(of: find.byKey(const Key('period-filter')), matching: find.text('Today')), findsOneWidget);
      final direction = tester.widget<SegmentedButton<CallTrendDirection>>(find.byKey(const Key('direction-filter')));
      expect(direction.selected, {CallTrendDirection.all});
    });

    testWidgets('shows the empty placeholder for both charts when there were no calls', (tester) async {
      await _pump(tester, FakeReportsRepository()..callTrendsToReturn = testCallTrends());

      expect(find.text('No data to display'), findsNWidgets(2));
      expect(find.byKey(const Key('expand-total-calls')), findsNothing);
    });

    testWidgets('shows an error with Retry, and Retry reloads', (tester) async {
      final repo = _repoWithCalls()..callTrendsError = const NetworkException('offline');

      await _pump(tester, repo);

      expect(find.text('Could not load your call analytics.'), findsOneWidget);

      repo.callTrendsError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Total Calls'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('choosing Outbound refetches with the outbound direction', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);
      expect(repo.trendsCallCount, 1);

      await tester.tap(find.descendant(of: find.byKey(const Key('direction-filter')), matching: find.text('Outbound')));
      await tester.pumpAndSettle();

      expect(repo.trendsCallCount, 2);
      expect(repo.lastTrendsDirection, CallTrendDirection.outbound);
    });

    testWidgets('choosing Inbound refetches with the inbound direction', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.descendant(of: find.byKey(const Key('direction-filter')), matching: find.text('Inbound')));
      await tester.pumpAndSettle();

      expect(repo.lastTrendsDirection, CallTrendDirection.inbound);
    });

    testWidgets('Unique swaps to distinct leads, explains talk time is unavailable, and does not refetch', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('counting-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unique').last);
      await tester.pumpAndSettle();

      expect(repo.trendsCallCount, 1, reason: 'All/Unique is client-side — the backend returns both');
      expect(find.text('Unique Leads Called'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // uniqueLeads, not totalCalls (5)
      expect(find.text('5'), findsNothing);
      expect(
        find.text('Talk time is unavailable for unique calls. Switch filter to “All” to view total talk time trends.'),
        findsOneWidget,
      );
      expect(find.text('3m 10s'), findsNothing);
    });

    testWidgets('switching back to All restores the totals and talk time', (tester) async {
      await _pump(tester, _repoWithCalls());

      await tester.tap(find.byKey(const Key('counting-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unique').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('counting-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();

      expect(find.text('Total Calls'), findsOneWidget);
      expect(find.text('3m 10s'), findsOneWidget);
    });
  });

  group('period sheet', () {
    testWidgets('opens with Day/Week/Month, and Cancel leaves the period alone', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('period-filter')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-kind')), findsOneWidget);
      await tester.tap(find.byKey(const Key('period-cancel')));
      await tester.pumpAndSettle();

      expect(repo.trendsCallCount, 1);
      expect(find.descendant(of: find.byKey(const Key('period-filter')), matching: find.text('Today')), findsOneWidget);
    });

    testWidgets('applying This month refetches per day for the whole month', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('period-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const Key('period-kind')), matching: find.text('Month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-apply')));
      await tester.pumpAndSettle();

      final month = CallAnalyticsPeriod.month(DateTime.now());
      expect(repo.lastTrendsSince, month.since);
      expect(repo.lastTrendsUntil, month.until);
      expect(repo.lastTrendsGranularity, CallTrendGranularity.day);
      expect(find.descendant(of: find.byKey(const Key('period-filter')), matching: find.text('This month')), findsOneWidget);
    });

    testWidgets('applying This week refetches per day, Monday to Monday', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('period-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const Key('period-kind')), matching: find.text('Week')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-apply')));
      await tester.pumpAndSettle();

      final week = CallAnalyticsPeriod.week(DateTime.now());
      expect(repo.lastTrendsSince, week.since);
      expect(repo.lastTrendsUntil, week.until);
      expect(repo.lastTrendsGranularity, CallTrendGranularity.day);
    });

    testWidgets('picking a day in the previous month refetches that single day hourly', (tester) async {
      final repo = _repoWithCalls();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('period-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-prev')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-day-10')));
      await tester.pumpAndSettle();
      // A six-row month pushes Apply below the fold on this short test
      // surface; the sheet scrolls, so scroll to it as a user would.
      await tester.ensureVisible(find.byKey(const Key('period-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-apply')));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final picked = CallAnalyticsPeriod.day(DateTime(now.year, now.month - 1, 10));
      expect(repo.lastTrendsSince, picked.since);
      expect(repo.lastTrendsUntil, picked.until);
      expect(repo.lastTrendsGranularity, CallTrendGranularity.hour);
      expect(find.descendant(of: find.byKey(const Key('period-filter')), matching: find.text(picked.label(now))), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('is disabled until there are calls to export', (tester) async {
      await _pump(tester, FakeReportsRepository()..callTrendsToReturn = testCallTrends());

      expect(tester.widget<IconButton>(find.byKey(const Key('export-call-trends'))).onPressed, isNull);
    });

    testWidgets('saves a CSV named after the period and confirms', (tester) async {
      final saver = FakeFileSaver();
      await _pump(tester, _repoWithCalls(), saver: saver);

      await tester.tap(find.byKey(const Key('export-call-trends')));
      await tester.pumpAndSettle();

      final start = CallAnalyticsPeriod.today().start;
      String pad(int n) => n.toString().padLeft(2, '0');
      expect(saver.lastMimeType, 'text/csv');
      expect(saver.lastFileName, 'call-trends-day-${start.year}-${pad(start.month)}-${pad(start.day)}.csv');
      expect(saver.lastText, startsWith('bucket_start,calls,unique_leads,talk_time_seconds\n'));
      expect(find.text('Call trends saved.'), findsOneWidget);
    });

    testWidgets('says nothing when the user cancels the save dialog', (tester) async {
      final saver = FakeFileSaver()..saved = false;
      await _pump(tester, _repoWithCalls(), saver: saver);

      await tester.tap(find.byKey(const Key('export-call-trends')));
      await tester.pumpAndSettle();

      expect(saver.callCount, 1);
      expect(find.text('Call trends saved.'), findsNothing);
      expect(find.text('Could not save the file.'), findsNothing);
    });

    testWidgets('reports a failure to save instead of crashing', (tester) async {
      final saver = FakeFileSaver()..error = Exception('disk full');
      await _pump(tester, _repoWithCalls(), saver: saver);

      await tester.tap(find.byKey(const Key('export-call-trends')));
      await tester.pumpAndSettle();

      expect(find.text('Could not save the file.'), findsOneWidget);
    });
  });

  group('expand', () {
    testWidgets('opens the chart full screen and closes again', (tester) async {
      await _pump(tester, _repoWithCalls());

      await tester.tap(find.byKey(const Key('expand-total-calls')));
      await tester.pumpAndSettle();

      // The card behind the dialog still shows its own title.
      expect(find.text('Total Calls'), findsNWidgets(2));
      expect(find.byType(CloseButton), findsOneWidget);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(find.text('Total Calls'), findsOneWidget);
    });
  });
}
