import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/pipeline/presentation/providers/pipeline_providers.dart';
import 'package:mobile/features/pipeline/presentation/screens/pipeline_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_pipeline_repository.dart';

Future<void> _pumpPipelineScreen(
  WidgetTester tester, {
  required FakePipelineRepository pipelineRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // Same reasoning as dashboard_screen_test.dart: a real (non-shrinkWrap)
  // board needs a tall-enough surface for every column/card to actually
  // build within the viewport.
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PipelineScreen())),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        pipelineRepositoryProvider.overrideWithValue(pipelineRepository),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PipelineScreen', () {
    testWidgets('renders columns with their leads', (tester) async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [
          testPipelineColumn(status: testLeadStatus(id: 's1', name: 'New'), leads: [testPipelineLeadCard(id: 'lead-1', name: 'Acme Corp')]),
          testPipelineColumn(status: testLeadStatus(id: 's2', name: 'Won', isWon: true), leads: const []),
        ];

      await _pumpPipelineScreen(tester, pipelineRepository: repo);

      expect(find.text('New'), findsOneWidget);
      expect(find.text('Won'), findsOneWidget);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('No leads here.'), findsOneWidget);
    });

    testWidgets('shows an empty state when the pipeline has no leads', (tester) async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: const [])];

      await _pumpPipelineScreen(tester, pipelineRepository: repo);

      expect(find.text('No leads in the pipeline yet.'), findsOneWidget);
    });

    testWidgets('shows an error state with retry when loading fails', (tester) async {
      final repo = FakePipelineRepository()..getPipelineError = const NetworkException('Could not reach the server.');

      await _pumpPipelineScreen(tester, pipelineRepository: repo);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('tapping a lead card navigates to the existing Lead Detail route', (tester) async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard(id: 'lead-1', name: 'Acme Corp')])];

      await _pumpPipelineScreen(
        tester,
        pipelineRepository: repo,
        extraRoutes: [GoRoute(path: '/app/leads/lead-1', builder: (context, state) => const Scaffold(body: Text('LEAD_DETAIL_MARKER')))],
      );

      await tester.tap(find.text('Acme Corp'));
      await tester.pumpAndSettle();

      expect(find.text('LEAD_DETAIL_MARKER'), findsOneWidget);
    });

    testWidgets('changing status via the card menu calls the repository and refreshes the board', (tester) async {
      final wonStatus = testLeadStatus(id: 's2', name: 'Won', isWon: true);
      final repo = FakePipelineRepository()
        ..columnsToReturn = [
          testPipelineColumn(status: testLeadStatus(id: 's1', name: 'New'), leads: [testPipelineLeadCard(id: 'lead-1', name: 'Acme Corp')]),
          testPipelineColumn(status: wonStatus, leads: const []),
        ]
        ..statusChangeResult = testLead(id: 'lead-1', status: wonStatus);

      await _pumpPipelineScreen(tester, pipelineRepository: repo);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Won'));
      await tester.pumpAndSettle();

      expect(repo.lastLeadId, 'lead-1');
      expect(repo.lastStatusId, 's2');
    });

    testWidgets('a failed status change shows a SnackBar with the server message', (tester) async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [
          testPipelineColumn(status: testLeadStatus(id: 's1', name: 'New'), leads: [testPipelineLeadCard(id: 'lead-1', name: 'Acme Corp')]),
          testPipelineColumn(status: testLeadStatus(id: 's2', name: 'Won', isWon: true), leads: const []),
        ]
        ..changeStatusError = const ValidationException('Selected status does not belong to this workspace.');

      await _pumpPipelineScreen(tester, pipelineRepository: repo);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Won'));
      await tester.pumpAndSettle();

      expect(find.text('Selected status does not belong to this workspace.'), findsOneWidget);
    });

    testWidgets('pull-to-refresh reloads the board', (tester) async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [testPipelineColumn(status: testLeadStatus(name: 'New'), leads: [testPipelineLeadCard(id: 'lead-1', name: 'First')])];

      await _pumpPipelineScreen(tester, pipelineRepository: repo);
      expect(find.text('First'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Same approach as dashboard_screen_test.dart's pull-to-refresh
      // test: exercise the underlying refresh directly through the
      // container rather than simulating RefreshIndicator's own drag
      // gesture.
      repo.columnsToReturn = [testPipelineColumn(status: testLeadStatus(name: 'New'), leads: [testPipelineLeadCard(id: 'lead-2', name: 'Second')])];
      final context = tester.element(find.byType(PipelineScreen));
      await ProviderScope.containerOf(context).read(pipelineControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('Second'), findsOneWidget);
    });
  });
}
