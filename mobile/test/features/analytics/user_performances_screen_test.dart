import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/analytics/presentation/screens/user_performances_screen.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/reports/domain/entities/team_report.dart';

import '../reports/fake_reports_repository.dart';
import 'analytics_test_helpers.dart';

Future<void> _pump(WidgetTester tester, FakeReportsRepository repo, {String role = 'manager'}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpAnalytics(tester, screen: const UserPerformancesScreen(), repository: repo, role: role);
}

void main() {
  group('access', () {
    testWidgets('a team_mate gets an explanation and no request is made', (tester) async {
      final repo = FakeReportsRepository();

      await _pump(tester, repo, role: 'team_mate');

      expect(find.text('Manager access is required to view user performances.'), findsOneWidget);
      expect(repo.callCount, 0);
    });

    for (final role in ['manager', 'admin', 'ceo']) {
      testWidgets('a $role sees the ranking', (tester) async {
        final repo = FakeReportsRepository()
          ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(fullName: 'Jamie Rep')], total: 1);

        await _pump(tester, repo, role: role);

        expect(find.text('Jamie Rep'), findsOneWidget);
      });
    }
  });

  group('ranking', () {
    testWidgets('lists agents in the order the backend ranked them, numbered from 1', (tester) async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(
          items: [
            testTeamRow(memberId: 'a', fullName: 'Avery Top', leadsConverted: 5),
            testTeamRow(memberId: 'b', fullName: 'Blake Mid', leadsConverted: 2),
            testTeamRow(memberId: 'c', fullName: 'Casey Low', leadsConverted: 0),
          ],
          total: 3,
        );

      await _pump(tester, repo);

      expect(find.text('Ranking (3)'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      final firstY = tester.getTopLeft(find.text('Avery Top')).dy;
      final secondY = tester.getTopLeft(find.text('Blake Mid')).dy;
      final thirdY = tester.getTopLeft(find.text('Casey Low')).dy;
      expect(firstY, lessThan(secondY));
      expect(secondY, lessThan(thirdY));
    });

    testWidgets("shows each agent's calls, connected calls, talk time and conversions", (tester) async {
      // testTeamRow: 5 calls, 3 connected, 300s talk, 3 assigned, `leadsConverted` converted.
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(fullName: 'Jamie Rep', leadsConverted: 1)], total: 1);

      await _pump(tester, repo);

      expect(find.text('5 calls · 3 connected · 5m 0s'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // converted count
      expect(find.text('33% conv.'), findsOneWidget); // 1 of 3
    });

    testWidgets('shows the team totals above the ranking', (tester) async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(
          items: [testTeamRow(memberId: 'a', fullName: 'A'), testTeamRow(memberId: 'b', fullName: 'B')],
          total: 2,
        );

      await _pump(tester, repo);

      // Two agents x (5 calls, 3 connected, 300s) = 10 calls, 6 connected, 10m talk.
      expect(find.text('10'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('10m 0s'), findsOneWidget);
      expect(find.text('Talk time'), findsOneWidget);
    });

    testWidgets('an agent with no name is shown as Unknown', (tester) async {
      final named = testTeamRow(memberId: 'x');
      final nameless = TeamMemberReportRow(
        member: const MemberSummary(id: 'x'),
        leadsAssigned: named.leadsAssigned,
        leadsConverted: named.leadsConverted,
        conversionRate: named.conversionRate,
        calls: named.calls,
        connectedCalls: named.connectedCalls,
        talkTimeSeconds: named.talkTimeSeconds,
        completedFollowUps: named.completedFollowUps,
        pendingFollowUps: named.pendingFollowUps,
      );
      final repo = FakeReportsRepository()..teamReportToReturn = testTeamReportPage(items: [nameless], total: 1);

      await _pump(tester, repo);

      expect(find.text('Unknown'), findsOneWidget);
    });
  });

  group('pagination', () {
    testWidgets('offers Load more while there are more agents than shown, and asks for the next page', (tester) async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(
          items: [for (var i = 0; i < 20; i++) testTeamRow(memberId: 'm$i', fullName: 'Agent $i')],
          total: 25,
        );
      await _pump(tester, repo);

      expect(find.byKey(const Key('load-more-agents')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('load-more-agents')));
      await tester.tap(find.byKey(const Key('load-more-agents')));
      await tester.pumpAndSettle();

      expect(repo.lastTeamOffset, 20);
    });

    testWidgets('no Load more when everyone is already shown', (tester) async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow()], total: 1);

      await _pump(tester, repo);

      expect(find.byKey(const Key('load-more-agents')), findsNothing);
    });
  });

  group('states', () {
    testWidgets('an empty team shows a message', (tester) async {
      await _pump(tester, FakeReportsRepository());

      expect(find.text('No team activity in this period yet.'), findsOneWidget);
    });

    testWidgets('an error shows Retry, and Retry reloads', (tester) async {
      final repo = FakeReportsRepository()..teamError = const NetworkException('offline');
      await _pump(tester, repo);

      expect(find.text('Retry'), findsOneWidget);

      repo
        ..teamError = null
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(fullName: 'Jamie Rep')], total: 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Jamie Rep'), findsOneWidget);
    });

    testWidgets('choosing a date range chip refetches for it', (tester) async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow()], total: 1);
      await _pump(tester, repo);

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      expect(repo.lastRange, 'this_month');
    });
  });
}
