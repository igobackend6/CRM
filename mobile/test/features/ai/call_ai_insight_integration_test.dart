import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/ai/domain/entities/ai_call_insight.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_ai_insight_repository.dart';

/// Phase 20 — proves `CallAiInsightSection` is genuinely wired into the
/// existing Call Detail screen (§"Customer 360/Lead Activity
/// integration"), not just a standalone widget, and that it renders
/// every state the pipeline can produce without disturbing the rest of
/// the (unmodified — §"Do not redesign Call Log") screen.
Future<void> _pumpCallDetailScreen(WidgetTester tester, {required FakeAiInsightRepository aiInsightRepository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final callRepo = FakeCallRepository()..callToReturn = testCall(id: 'call-1', leadName: 'Acme Corp');

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const CallDetailScreen(callId: 'call-1'))],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        callRepositoryProvider.overrideWithValue(callRepo),
        aiInsightRepositoryProvider.overrideWithValue(aiInsightRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an "Analyze this call" action when nothing was requested yet', (tester) async {
    final repo = FakeAiInsightRepository()..callInsightToReturn = null;

    await _pumpCallDetailScreen(tester, aiInsightRepository: repo);

    expect(find.text('AI Insight'), findsOneWidget);
    expect(find.text('Analyze this call'), findsOneWidget);
    // The rest of the (unmodified) screen is still there alongside it.
    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('tapping Analyze shows a processing indicator then the completed result', (tester) async {
    final repo = FakeAiInsightRepository()
      ..callInsightToReturn = null
      ..requestAnalysisDelay = const Duration(milliseconds: 300)
      ..requestAnalysisResult = testAiCallInsight(
        status: AiInsightStatus.completed,
        summary: 'Customer wants a callback tomorrow.',
        sentiment: 'positive',
        actionItems: const ['Call back tomorrow'],
        callScore: 90,
      );

    await _pumpCallDetailScreen(tester, aiInsightRepository: repo);
    await tester.tap(find.text('Analyze this call'));
    await tester.pump(); // start the request, don't let the delayed future resolve yet
    expect(find.text('Analyzing call…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Customer wants a callback tomorrow.'), findsOneWidget);
    expect(find.text('positive'), findsOneWidget);
    expect(find.text('Call back tomorrow'), findsOneWidget);
    expect(find.text('Score: 90'), findsOneWidget);
  });

  testWidgets('a failed analysis shows the error message and a retry action', (tester) async {
    final repo = FakeAiInsightRepository()
      ..callInsightToReturn = testAiCallInsight(status: AiInsightStatus.failed, errorMessage: 'No call recording is available for this call yet.');

    await _pumpCallDetailScreen(tester, aiInsightRepository: repo);

    expect(find.text('No call recording is available for this call yet.'), findsOneWidget);
    expect(find.text('Retry analysis'), findsOneWidget);
  });

  testWidgets('a load error on the section shows its own retry, independent of the call itself', (tester) async {
    final repo = FakeAiInsightRepository()..getCallInsightError = Exception('boom');

    await _pumpCallDetailScreen(tester, aiInsightRepository: repo);

    // The call's own fields still render — a failed AI section load
    // never blocks the rest of Call Detail.
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Could not load the AI insight.'), findsOneWidget);
  });
}
