import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/dashboard/domain/entities/leads_by_status_item.dart';
import 'package:mobile/features/dashboard/domain/entities/team_productivity_row.dart';
import 'package:mobile/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../followups/fake_follow_up_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_dashboard_repository.dart';

Future<void> _pumpDashboardScreen(
  WidgetTester tester, {
  required FakeDashboardRepository dashboardRepository,
  FakeFollowUpRepository? followUpRepository,
  FakeCallRepository? callRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // The dashboard is a genuinely long, real scrollable page (KPI grid +
  // three preview sections) — the default flutter_test surface
  // (800x600) is shorter than that, and a real (non-shrinkWrap)
  // ListView only builds what's within the viewport/cache extent, same
  // as the production app. Giving the test surface plenty of height
  // means every section is actually built and assertable without each
  // test having to scroll first.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: DashboardScreen())),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
        followUpRepositoryProvider.overrideWithValue(followUpRepository ?? FakeFollowUpRepository()),
        callRepositoryProvider.overrideWithValue(callRepository ?? FakeCallRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DashboardScreen', () {
    testWidgets('renders the KPI grid from the summary', (tester) async {
      final dashboardRepo = FakeDashboardRepository()..summaryToReturn = testSummary(totalActiveLeads: 7, newLeads: 6);

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('Active leads'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('New leads'), findsOneWidget);
    });

    testWidgets('shows an error state with retry when the summary fails to load', (tester) async {
      final dashboardRepo = FakeDashboardRepository()..summaryError = const NetworkException('Could not reach the server.');

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('Could not load your dashboard summary.'), findsOneWidget);
      // Four sections share dashboardSummaryProvider as of Phase 17
      // (Overview KPIs, period analytics, pipeline distribution, team
      // productivity) — a summary failure surfaces an AppRetryView (and
      // its own "Retry" button) in each of them independently.
      expect(find.text('Retry'), findsNWidgets(4));
    });

    testWidgets('splits pending follow-ups into overdue and upcoming previews', (tester) async {
      final followUpRepo = FakeFollowUpRepository()
        ..itemsToReturn = [
          testFollowUp(id: 'fu-1', leadName: 'Overdue Co', isOverdue: true),
          testFollowUp(id: 'fu-2', leadName: 'Upcoming Co', isOverdue: false),
        ]
        ..totalToReturn = 2;

      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository(), followUpRepository: followUpRepo);

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Overdue Co'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Upcoming Co'), findsOneWidget);
    });

    testWidgets('shows an empty state when there are no pending follow-ups', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      expect(find.text('No pending follow-ups.'), findsOneWidget);
    });

    testWidgets('renders the call summary preview', (tester) async {
      final callRepo = FakeCallRepository()
        ..itemsToReturn = [testCall(id: 'call-1', leadName: 'Globex')]
        ..totalToReturn = 1;

      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository(), callRepository: callRepo);

      expect(find.text('Globex'), findsOneWidget);
    });

    testWidgets('shows an empty state when there are no calls', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      expect(find.text('No calls logged yet.'), findsOneWidget);
    });

    testWidgets('renders recent activity items', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:call-1', summary: 'Outbound call — ended')]
        ..activityTotalToReturn = 1;

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('Outbound call — ended'), findsOneWidget);
    });

    testWidgets('shows an empty state when there is no recent activity', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      expect(find.text('No activity yet.'), findsOneWidget);
    });

    testWidgets('tapping a KPI card navigates to the existing leads route', (tester) async {
      final dashboardRepo = FakeDashboardRepository()..summaryToReturn = testSummary(totalActiveLeads: 7);

      await _pumpDashboardScreen(
        tester,
        dashboardRepository: dashboardRepo,
        extraRoutes: [GoRoute(path: '/app/leads', builder: (context, state) => const Scaffold(body: Text('LEADS_MARKER')))],
      );

      await tester.tap(find.text('Active leads'));
      await tester.pumpAndSettle();

      expect(find.text('LEADS_MARKER'), findsOneWidget);
    });

    testWidgets('tapping a follow-up preview navigates to its detail route', (tester) async {
      final followUpRepo = FakeFollowUpRepository()
        ..itemsToReturn = [testFollowUp(id: 'fu-1', leadName: 'Acme Corp')]
        ..totalToReturn = 1;

      await _pumpDashboardScreen(
        tester,
        dashboardRepository: FakeDashboardRepository(),
        followUpRepository: followUpRepo,
        extraRoutes: [
          GoRoute(path: '/app/follow-ups/fu-1', builder: (context, state) => const Scaffold(body: Text('FOLLOW_UP_DETAIL_MARKER'))),
        ],
      );

      await tester.tap(find.text('Acme Corp'));
      await tester.pumpAndSettle();

      expect(find.text('FOLLOW_UP_DETAIL_MARKER'), findsOneWidget);
    });

    testWidgets('tapping a resolvable recent-activity item navigates to its detail route', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:call-1', type: 'call', summary: 'Outbound call — ended')]
        ..activityTotalToReturn = 1;

      await _pumpDashboardScreen(
        tester,
        dashboardRepository: dashboardRepo,
        extraRoutes: [GoRoute(path: '/app/calls/call-1', builder: (context, state) => const Scaffold(body: Text('CALL_DETAIL_MARKER')))],
      );

      await tester.tap(find.text('Outbound call — ended'));
      await tester.pumpAndSettle();

      expect(find.text('CALL_DETAIL_MARKER'), findsOneWidget);
    });

    testWidgets('a non-navigable recent-activity item (e.g. a note) does not navigate on tap', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'interaction:i-1', type: 'note', summary: 'Left a voicemail')]
        ..activityTotalToReturn = 1;

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      await tester.tap(find.text('Left a voicemail'));
      await tester.pumpAndSettle();

      // Still on the dashboard — nothing to navigate to.
      expect(find.text('Left a voicemail'), findsOneWidget);
    });

    testWidgets('pull-to-refresh reloads the summary', (tester) async {
      final dashboardRepo = FakeDashboardRepository()..summaryToReturn = testSummary(totalActiveLeads: 1);

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);
      expect(find.text('1'), findsWidgets);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Same approach as call_list_screen_test.dart's pull-to-refresh
      // test: exercise the underlying invalidation directly through the
      // container rather than simulating RefreshIndicator's own drag
      // gesture, which is a Flutter-framework concern this app's code
      // doesn't need to re-prove.
      dashboardRepo.summaryToReturn = testSummary(totalActiveLeads: 9);
      final context = tester.element(find.byType(DashboardScreen));
      ProviderScope.containerOf(context).invalidate(dashboardSummaryProvider);
      await tester.pumpAndSettle();

      expect(find.text('9'), findsWidgets);
    });

    // ---- Phase 17: period analytics KPIs ----

    testWidgets('renders the period-analytics KPI tiles from the summary', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..summaryToReturn = testSummary(leadsCreatedInRange: 5, convertedLeadsInRange: 2, conversionRate: 0.4);

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('Leads created'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
      expect(find.text('Converted'), findsOneWidget);
      expect(find.text('Conversion rate'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
    });

    // ---- Phase 17: pipeline distribution ----

    testWidgets('renders the pipeline distribution from leads_by_status', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..summaryToReturn = testSummary(
          leadsByStatus: const [
            LeadsByStatusItem(
              status: LeadStatus(id: 's1', name: 'New', code: 'new', sortOrder: 10, stage: 'in_progress', isDefault: true),
              count: 4,
            ),
            LeadsByStatusItem(
              status: LeadStatus(id: 's2', name: 'Won', code: 'won', sortOrder: 20, stage: 'closed_won', isDefault: false),
              count: 1,
            ),
          ],
        );

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('New'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.text('Won'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('shows an empty state when the workspace has no lead statuses', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      expect(find.text('No pipeline stages configured yet.'), findsOneWidget);
    });

    // ---- Phase 17: team productivity ----

    testWidgets('renders team productivity rows from the summary', (tester) async {
      final dashboardRepo = FakeDashboardRepository()
        ..summaryToReturn = testSummary(
          teamProductivity: const [
            TeamProductivityRow(
              member: MemberSummary(id: 'm1', fullName: 'Jamie Rep'),
              leadsCount: 3,
              callsCount: 6,
              completedFollowUpsCount: 2,
            ),
          ],
        );

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);

      expect(find.text('Jamie Rep'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.text('6'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('shows an empty state when no member has activity in this period', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      expect(find.text('No team activity in this period yet.'), findsOneWidget);
    });

    // ---- Phase 17: date range filter ----

    testWidgets('selecting a date-range chip re-fetches the summary with that range', (tester) async {
      final dashboardRepo = FakeDashboardRepository();

      await _pumpDashboardScreen(tester, dashboardRepository: dashboardRepo);
      expect(dashboardRepo.lastRange, 'all');

      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();

      expect(dashboardRepo.lastRange, 'this_week');
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('the date-range chip row defaults to All time', (tester) async {
      await _pumpDashboardScreen(tester, dashboardRepository: FakeDashboardRepository());

      final chip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('All time'), matching: find.byType(ChoiceChip)),
      );
      expect(chip.selected, isTrue);
    });
  });
}
