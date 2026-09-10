import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/pipeline/presentation/providers/pipeline_providers.dart';
import 'package:mobile/features/rechurn/presentation/providers/rechurn_providers.dart';
import 'package:mobile/features/rechurn/presentation/screens/rechurn_queue_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../pipeline/fake_pipeline_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_rechurn_repository.dart';

Future<void> _pumpRechurnScreen(
  WidgetTester tester, {
  required FakeRechurnRepository rechurnRepository,
  FakePipelineRepository? pipelineRepository,
  FakeLeadRepository? leadRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // Same widening as lead_list_screen_test.dart's filter sheet — this
  // screen's own filter sheet is similarly tall.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const RechurnQueueScreen()),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        rechurnRepositoryProvider.overrideWithValue(rechurnRepository),
        pipelineRepositoryProvider.overrideWithValue(pipelineRepository ?? FakePipelineRepository()),
        leadRepositoryProvider.overrideWithValue(leadRepository ?? FakeLeadRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders queue cards with name, status, priority, and assignee', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [
        testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp', assignedMember: const MemberSummary(id: 'm1', fullName: 'Rep One')),
      ]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(tester, rechurnRepository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Rep One'), findsOneWidget);
  });

  testWidgets('shows the empty state when no leads need re-engagement', (tester) async {
    final repo = FakeRechurnRepository();

    await _pumpRechurnScreen(tester, rechurnRepository: repo);

    expect(find.text('No leads need re-engagement right now.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when loading fails', (tester) async {
    final repo = FakeRechurnRepository()..getQueueError = const NetworkException('Could not reach the server.');

    await _pumpRechurnScreen(tester, rechurnRepository: repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping the Inactive segment chip filters the queue', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard()]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(tester, rechurnRepository: repo);
    await tester.tap(find.text('Inactive'));
    await tester.pumpAndSettle();

    expect(repo.lastSegment, 'inactive');
  });

  testWidgets('pull-to-refresh reloads the queue', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'First')]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(tester, rechurnRepository: repo);
    expect(find.text('First'), findsOneWidget);

    repo.itemsToReturn = [testRechurnLeadCard(id: 'lead-2', name: 'Second')];
    final context = tester.element(find.byType(RechurnQueueScreen));
    await ProviderScope.containerOf(context).read(rechurnListControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('tapping Call navigates to the existing call-create-for-lead route', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(
      tester,
      rechurnRepository: repo,
      extraRoutes: [GoRoute(path: '/app/calls/create', builder: (context, state) => const Scaffold(body: Text('CALL_FORM_MARKER')))],
    );

    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();

    expect(find.text('CALL_FORM_MARKER'), findsOneWidget);
  });

  testWidgets('tapping Follow-up navigates to the existing follow-up-create-for-lead route', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(
      tester,
      rechurnRepository: repo,
      extraRoutes: [GoRoute(path: '/app/follow-ups/create', builder: (context, state) => const Scaffold(body: Text('FOLLOW_UP_FORM_MARKER')))],
    );

    await tester.tap(find.text('Follow-up'));
    await tester.pumpAndSettle();

    expect(find.text('FOLLOW_UP_FORM_MARKER'), findsOneWidget);
  });

  testWidgets('tapping the lead card navigates to the existing Lead Detail route', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(
      tester,
      rechurnRepository: repo,
      extraRoutes: [GoRoute(path: '/app/leads/lead-1', builder: (context, state) => const Scaffold(body: Text('LEAD_DETAIL_MARKER')))],
    );

    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.text('LEAD_DETAIL_MARKER'), findsOneWidget);
  });

  testWidgets('a customer lead shows a Customer 360 action that navigates there', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp', isCustomer: true)]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(
      tester,
      rechurnRepository: repo,
      extraRoutes: [GoRoute(path: '/app/customers/lead-1', builder: (context, state) => const Scaffold(body: Text('CUSTOMER_360_MARKER')))],
    );

    expect(find.text('Customer 360'), findsOneWidget);
    await tester.tap(find.text('Customer 360'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOMER_360_MARKER'), findsOneWidget);
  });

  testWidgets('a non-customer lead does not show a Customer 360 action', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp', isCustomer: false)]
      ..totalToReturn = 1;

    await _pumpRechurnScreen(tester, rechurnRepository: repo);

    expect(find.text('Customer 360'), findsNothing);
  });

  testWidgets('the Status action opens a picker and applies a status change', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
      ..totalToReturn = 1;
    final pipelineRepo = FakePipelineRepository();
    final leadRepo = FakeLeadRepository()..statusesToReturn = [testRechurnStatus(id: 's2', name: 'Contacted')];

    await _pumpRechurnScreen(tester, rechurnRepository: repo, pipelineRepository: pipelineRepo, leadRepository: leadRepo);

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Change status to'), findsOneWidget);

    await tester.tap(find.text('Contacted'));
    await tester.pumpAndSettle();

    expect(pipelineRepo.lastLeadId, 'lead-1');
    expect(pipelineRepo.lastStatusId, 's2');
  });

  testWidgets('a failed status change shows a SnackBar with the server message', (tester) async {
    final repo = FakeRechurnRepository()
      ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
      ..totalToReturn = 1;
    final pipelineRepo = FakePipelineRepository()
      ..changeStatusError = const ValidationException('Selected status does not belong to this workspace.');
    final leadRepo = FakeLeadRepository()..statusesToReturn = [testRechurnStatus(id: 's2', name: 'Contacted')];

    await _pumpRechurnScreen(tester, rechurnRepository: repo, pipelineRepository: pipelineRepo, leadRepository: leadRepo);

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacted'));
    await tester.pumpAndSettle();

    expect(find.text('Selected status does not belong to this workspace.'), findsOneWidget);
  });
}
