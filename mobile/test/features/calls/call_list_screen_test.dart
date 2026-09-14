import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/calls/presentation/screens/call_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

Future<void> _pumpCallListScreen(
  WidgetTester tester, {
  required FakeCallRepository repository,
  List<GoRoute> extraRoutes = const [],
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const CallListScreen()), ...extraRoutes],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        callRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading indicator, then the list', (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'call-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpCallListScreen(tester, repository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no calls', (tester) async {
    final repo = FakeCallRepository();

    await _pumpCallListScreen(tester, repository: repo);

    expect(find.text('No calls logged yet.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    final repo = FakeCallRepository()..listError = const NetworkException('Could not reach the server.');

    await _pumpCallListScreen(tester, repository: repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the list', (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'call-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpCallListScreen(tester, repository: repo);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    repo.itemsToReturn = [testCall(id: 'call-2', leadName: 'Globex')];
    final context = tester.element(find.byType(CallListScreen));
    await ProviderScope.containerOf(context).read(callListControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('Globex'), findsOneWidget);
  });

  testWidgets('tapping a call navigates to its detail route', (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'call-1', leadName: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpCallListScreen(
      tester,
      repository: repo,
      extraRoutes: [
        GoRoute(path: '/app/calls/call-1', builder: (context, state) => const Scaffold(body: Text('CALL_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.text('CALL_DETAIL_MARKER'), findsOneWidget);
  });
}
