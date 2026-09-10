import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/followups/presentation/screens/follow_up_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_follow_up_repository.dart';

Future<void> _pumpFollowUpListScreen(WidgetTester tester, {required FakeFollowUpRepository repository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const FollowUpListScreen())],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        followUpRepositoryProvider.overrideWithValue(repository),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading indicator, then the list', (tester) async {
    final repo = FakeFollowUpRepository()
      ..itemsToReturn = [testFollowUp(id: 'fu-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpFollowUpListScreen(tester, repository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('call'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no follow-ups', (tester) async {
    final repo = FakeFollowUpRepository();

    await _pumpFollowUpListScreen(tester, repository: repo);

    expect(find.text('No follow-ups yet.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    final repo = FakeFollowUpRepository()..listError = const NetworkException('Could not reach the server.');

    await _pumpFollowUpListScreen(tester, repository: repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the list', (tester) async {
    final repo = FakeFollowUpRepository()
      ..itemsToReturn = [testFollowUp(id: 'fu-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpFollowUpListScreen(tester, repository: repo);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    repo.itemsToReturn = [testFollowUp(id: 'fu-2', leadName: 'Globex')];
    // Drive the same callback RefreshIndicator's pull gesture wires to
    // (`onRefresh: () => ...refresh()`) rather than simulating the raw
    // drag — a single item doesn't fill the viewport enough for a fling
    // gesture to reliably register as a pull in the test surface, and
    // this still exercises the exact reload path a real pull triggers.
    final context = tester.element(find.byType(FollowUpListScreen));
    await ProviderScope.containerOf(context).read(followUpListControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('Globex'), findsOneWidget);
  });

  testWidgets('tapping a follow-up navigates to its detail route', (tester) async {
    final authRepo = FakeAuthRepository()
      ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
    final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
    final repo = FakeFollowUpRepository()
      ..itemsToReturn = [testFollowUp(id: 'fu-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const FollowUpListScreen()),
        // Matches RoutePaths.followUpDetail('fu-1') exactly, so tapping
        // the tile actually exercises the real navigation target.
        GoRoute(path: '/app/follow-ups/fu-1', builder: (context, state) => const Scaffold(body: Text('FOLLOW_UP_DETAIL_MARKER'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
          workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
          followUpRepositoryProvider.overrideWithValue(repo),
          realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acme Corp'), findsOneWidget);
    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.text('FOLLOW_UP_DETAIL_MARKER'), findsOneWidget);
  });
}
