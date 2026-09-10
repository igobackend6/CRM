import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

Future<void> _pumpCallDetailScreen(
  WidgetTester tester, {
  required FakeCallRepository repository,
  List<GoRoute> extraRoutes = const [],
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const CallDetailScreen(callId: 'call-1')), ...extraRoutes],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        callRepositoryProvider.overrideWithValue(repository),
        // Phase 20 — CallAiInsightSection is now part of this screen;
        // a fake keeps its own (unrelated to this file's tests) load
        // from making a real network call.
        aiInsightRepositoryProvider.overrideWithValue(FakeAiInsightRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the call\'s fields', (tester) async {
    final repo = FakeCallRepository()
      ..callToReturn = testCall(id: 'call-1', leadName: 'Acme Corp', direction: 'inbound', durationSeconds: 125);

    await _pumpCallDetailScreen(tester, repository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('inbound'), findsOneWidget);
    expect(find.text('2m 5s'), findsOneWidget);
  });

  testWidgets('shows a not-found message for a missing call', (tester) async {
    final repo = FakeCallRepository()..getError = const NotFoundException('Call not found.');

    await _pumpCallDetailScreen(tester, repository: repo);

    expect(find.text('This call could not be found.'), findsOneWidget);
  });

  testWidgets('"View lead" navigates to the related lead', (tester) async {
    final repo = FakeCallRepository()..callToReturn = testCall(id: 'call-1', leadId: 'l1', leadName: 'Acme Corp');

    await _pumpCallDetailScreen(
      tester,
      repository: repo,
      extraRoutes: [
        GoRoute(path: '/app/leads/l1', builder: (context, state) => const Scaffold(body: Text('LEAD_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('View lead'));
    await tester.pumpAndSettle();

    expect(find.text('LEAD_DETAIL_MARKER'), findsOneWidget);
  });
}
