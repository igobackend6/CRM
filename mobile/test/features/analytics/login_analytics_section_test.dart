import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/activity/domain/entities/activity_summary.dart';
import 'package:mobile/features/analytics/presentation/screens/call_analytics_screen.dart';
import 'package:mobile/features/analytics/presentation/widgets/login_analytics_section.dart';

import '../activity/fake_activity_repository.dart';
import '../reports/fake_reports_repository.dart';
import 'analytics_test_helpers.dart';

Widget _screen() => Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: const [LoginAnalyticsSection()]));

Future<void> _pump(WidgetTester tester, FakeActivityRepository activity) => pumpAnalytics(tester, screen: _screen(), activity: activity);

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('summary tiles', () {
    testWidgets('shows the header and the five figures from the backend', (tester) async {
      await _pump(tester, FakeActivityRepository());

      expect(find.text('LOGIN ANALYTICS'), findsOneWidget);
      expect(find.text('Login Duration'), findsOneWidget);
      expect(find.text('Wrap up Time'), findsOneWidget);
      expect(find.text('Break Time'), findsOneWidget);
      expect(find.text('Idle Time'), findsOneWidget);
      expect(find.text('Total Talk Time'), findsOneWidget);

      expect(_text(tester, 'login-duration'), '4m 14s');
      expect(_text(tester, 'wrap-up-time'), '0m 30s');
      expect(_text(tester, 'break-time'), '0m 0s');
      expect(_text(tester, 'idle-time'), '2m 44s');
      expect(_text(tester, 'talk-time'), '1m 0s');
    });

    testWidgets('long durations switch to hours and minutes', (tester) async {
      final activity = FakeActivityRepository()
        ..summaryToReturn = const ActivitySummary(
          loginSeconds: 8 * 3600 + 5 * 60,
          talkSeconds: 2 * 3600,
          wrapUpSeconds: 600,
          breakSeconds: 3600,
          idleSeconds: 3600,
        );

      await _pump(tester, activity);

      expect(_text(tester, 'login-duration'), '8h 5m');
      expect(_text(tester, 'talk-time'), '2h 0m');
      expect(_text(tester, 'break-time'), '1h 0m');
    });

    testWidgets('asks for today first', (tester) async {
      final activity = FakeActivityRepository();

      await _pump(tester, activity);

      expect(activity.summaryCallCount, 1);
      expect(activity.lastUntil!.isAfter(activity.lastSince!), isTrue);
      expect(find.descendant(of: find.byKey(const Key('login-range-filter')), matching: find.text('Today')), findsOneWidget);
    });

    testWidgets('choosing another range refetches for that window', (tester) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);
      final todaySince = activity.lastSince;

      await tester.tap(find.byKey(const Key('login-range-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This month').last);
      await tester.pumpAndSettle();

      expect(activity.summaryCallCount, 2);
      expect(activity.lastSince, isNot(todaySince));
      expect(activity.lastUntil!.difference(activity.lastSince!), greaterThan(const Duration(days: 27)));
    });

    testWidgets('shows an error with Retry, and Retry reloads', (tester) async {
      final activity = FakeActivityRepository()..summaryError = const NetworkException('offline');

      await _pump(tester, activity);

      expect(find.text('Could not load your login analytics.'), findsOneWidget);

      activity.summaryError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your login analytics.'), findsNothing);
      expect(_text(tester, 'login-duration'), '4m 14s');
    });
  });

  group('break control', () {
    testWidgets('offers "Take a break" when not on a break', (tester) async {
      await _pump(tester, FakeActivityRepository());

      expect(find.byKey(const Key('take-break')), findsOneWidget);
      expect(find.byKey(const Key('end-break')), findsNothing);
    });

    testWidgets('tapping it starts a break, shows the banner, and reloads the totals', (tester) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);

      await tester.tap(find.byKey(const Key('take-break')));
      await tester.pumpAndSettle();

      expect(activity.count('startBreak'), 1);
      expect(find.byKey(const Key('take-break')), findsNothing);
      expect(find.byKey(const Key('end-break')), findsOneWidget);
      expect(find.byKey(const Key('on-break-label')), findsOneWidget);
      expect(activity.summaryCallCount, 2);
    });

    testWidgets('"End break" ends it and brings back "Take a break"', (tester) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);
      await tester.tap(find.byKey(const Key('take-break')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('end-break')));
      await tester.pumpAndSettle();

      expect(activity.count('endBreak'), 1);
      expect(find.byKey(const Key('take-break')), findsOneWidget);
      expect(find.byKey(const Key('end-break')), findsNothing);
    });

    testWidgets('a break the backend already knows about shows the banner on first load', (tester) async {
      final activity = FakeActivityRepository()..heartbeatStatus = ActivityStatus(onBreak: true, breakStartedAt: DateTime.now());

      await _pump(tester, activity);

      expect(find.byKey(const Key('end-break')), findsOneWidget);
      expect(find.textContaining('On a break since'), findsOneWidget);
    });

    testWidgets('a failed start shows a message and stays off break', (tester) async {
      final activity = FakeActivityRepository()..breakError = const NetworkException('offline');
      await _pump(tester, activity);

      await tester.tap(find.byKey(const Key('take-break')));
      await tester.pumpAndSettle();

      expect(find.text('offline'), findsOneWidget);
      expect(find.byKey(const Key('take-break')), findsOneWidget);
      expect(find.byKey(const Key('end-break')), findsNothing);
    });
  });

  group('inside Call Analytics', () {
    testWidgets('the screen includes the Login Analytics section below the call trends', (tester) async {
      await pumpAnalytics(tester, screen: const CallAnalyticsScreen(), repository: FakeReportsRepository()..callTrendsToReturn = testCallTrends());
      await tester.scrollUntilVisible(find.text('LOGIN ANALYTICS'), 300, scrollable: find.byType(Scrollable).first);

      expect(find.text('LOGIN ANALYTICS'), findsOneWidget);
      expect(find.text('Login Duration'), findsOneWidget);
    });
  });
}
