import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/ai/domain/entities/ai_assistant_answer.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../documents/fake_document_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_ai_insight_repository.dart';

/// Phase 20 — proves `LeadAiSection` (Lead Insights + AI Assistant) is
/// genuinely wired into the existing Lead Detail screen (§"Customer
/// 360/Lead Activity integration"), not just a standalone widget, and
/// that the assistant's honest "unavailable" state (this environment's
/// real state — no AI provider configured) renders correctly alongside
/// the rest of the (unmodified — §"Do not redesign Customer 360")
/// screen.
Future<void> _pumpLeadDetailScreen(WidgetTester tester, {required FakeAiInsightRepository aiInsightRepository}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const LeadDetailScreen(leadId: 'l1'))],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(leadRepo),
        aiInsightRepositoryProvider.overrideWithValue(aiInsightRepository),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when the lead has no analyzed calls', (tester) async {
    final repo = FakeAiInsightRepository()..leadInsightsToReturn = [];

    await _pumpLeadDetailScreen(tester, aiInsightRepository: repo);

    expect(find.text('Lead Insights'), findsOneWidget);
    expect(find.text('No AI call insights yet.'), findsOneWidget);
    // The rest of the (unmodified) screen is still there alongside it.
    expect(find.text('Acme Corp'), findsWidgets);
  });

  testWidgets('renders a completed insight\'s sentiment and summary', (tester) async {
    final repo = FakeAiInsightRepository()
      ..leadInsightsToReturn = [testAiCallInsight(summary: 'Wants a callback tomorrow.', sentiment: 'positive')];

    await _pumpLeadDetailScreen(tester, aiInsightRepository: repo);

    expect(find.text('Wants a callback tomorrow.'), findsOneWidget);
    expect(find.text('positive'), findsOneWidget);
  });

  testWidgets('asking the assistant shows the honest unavailable message when no provider is configured', (tester) async {
    final repo = FakeAiInsightRepository()
      ..askResult = const AiAssistantAnswer(available: false, message: 'The AI assistant is not available yet.');

    await _pumpLeadDetailScreen(tester, aiInsightRepository: repo);
    await tester.enterText(find.widgetWithText(TextField, 'Ask about this lead…'), 'What does this customer need?');
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(find.text('The AI assistant is not available yet.'), findsOneWidget);
    expect(repo.lastAskedQuestion, 'What does this customer need?');
  });

  testWidgets('asking the assistant shows its answer when available', (tester) async {
    final repo = FakeAiInsightRepository()
      ..askResult = const AiAssistantAnswer(available: true, answer: 'They want a quote by Friday.');

    await _pumpLeadDetailScreen(tester, aiInsightRepository: repo);
    await tester.enterText(find.widgetWithText(TextField, 'Ask about this lead…'), 'What do they need?');
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(find.text('They want a quote by Friday.'), findsOneWidget);
  });
}
