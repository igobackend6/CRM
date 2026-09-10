import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/reports/presentation/providers/reports_providers.dart';
import 'package:mobile/features/reports/presentation/screens/reports_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_reports_repository.dart';

Future<void> _pumpReportsScreen(WidgetTester tester, {required FakeReportsRepository repository, String role = 'manager'}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'), role: role)];

  final router = GoRouter(initialLocation: '/', routes: [GoRoute(path: '/', builder: (context, state) => const ReportsScreen())]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        reportsRepositoryProvider.overrideWithValue(repository),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the personal report KPIs by default', (tester) async {
    final repo = FakeReportsRepository()..personalReportToReturn = testPersonalReport(totalCalls: 42);

    await _pumpReportsScreen(tester, repository: repo);

    expect(find.text('42'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Pipeline'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on a personal report failure', (tester) async {
    final repo = FakeReportsRepository()..personalError = const NetworkException('Could not reach the server.');

    await _pumpReportsScreen(tester, repository: repo);

    expect(find.text('Could not load your personal report.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('switching to the Team tab shows member rows and totals for a manager', (tester) async {
    final repo = FakeReportsRepository()
      ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(fullName: 'Jamie Rep')], total: 1);

    await _pumpReportsScreen(tester, repository: repo, role: 'manager');
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    // skipOffstage:false — this content sits inside a scrollable
    // DataTable/ListView; Flutter's default text finder only considers
    // what's currently painted within the viewport, and this row can
    // land outside that even though it's fully built.
    expect(find.text('Jamie Rep', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('By member', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the Team tab shows a manager-access message for a team_mate, never fetching it', (tester) async {
    final repo = FakeReportsRepository()..teamReportToReturn = testTeamReportPage(items: [testTeamRow()], total: 1);

    await _pumpReportsScreen(tester, repository: repo, role: 'team_mate');
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    expect(find.text('Manager access is required to view this report.'), findsOneWidget);
    expect(find.text('Jamie Rep'), findsNothing);
  });

  testWidgets('the Pipeline tab shows a manager-access message for a team_mate', (tester) async {
    final repo = FakeReportsRepository();

    await _pumpReportsScreen(tester, repository: repo, role: 'team_mate');
    await tester.tap(find.text('Pipeline'));
    await tester.pumpAndSettle();

    expect(find.text('Manager access is required to view this report.'), findsOneWidget);
  });

  testWidgets('switching to the Pipeline tab shows status/source/priority breakdowns for a manager', (tester) async {
    final repo = FakeReportsRepository()..pipelineReportToReturn = testPipelineReport();

    await _pumpReportsScreen(tester, repository: repo, role: 'admin');
    await tester.tap(find.text('Pipeline'));
    await tester.pumpAndSettle();

    expect(find.text('Status distribution'), findsOneWidget);
    expect(find.text('Source performance'), findsOneWidget);
    // skipOffstage:false — this section header lands below the
    // Source-performance DataTable, outside the ListView's initial
    // painted viewport (see the Team-tab test's own note above).
    expect(find.text('Priority distribution', skipOffstage: false), findsOneWidget);
  });

  testWidgets('selecting a different date-range chip re-fetches the personal report', (tester) async {
    final repo = FakeReportsRepository();

    await _pumpReportsScreen(tester, repository: repo);
    expect(repo.lastRange, 'all_time');

    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();

    expect(repo.lastRange, 'this_week');
  });
}
