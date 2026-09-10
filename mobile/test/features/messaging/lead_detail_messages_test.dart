import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../documents/fake_document_repository.dart';
import '../followups/fake_follow_up_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_messaging_repository.dart';

/// Verifies Phase 16 §"Lead/Customer entry": Lead Detail shows a simple
/// "Messages" entry point that resolves/creates the lead's conversation
/// and navigates to it — without redesigning the rest of the screen
/// (the existing Phase 5-15 sections stay unchanged, same mirrors as
/// lead_detail_calls_test.dart / lead_detail_followups_test.dart).
Future<void> _pumpLeadDetailScreen(
  WidgetTester tester, {
  required FakeLeadRepository leadRepository,
  required FakeMessagingRepository messagingRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LeadDetailScreen(leadId: 'l1')),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(leadRepository),
        followUpRepositoryProvider.overrideWithValue(FakeFollowUpRepository()),
        callRepositoryProvider.overrideWithValue(FakeCallRepository()),
        messagingRepositoryProvider.overrideWithValue(messagingRepository),
        aiInsightRepositoryProvider.overrideWithValue(FakeAiInsightRepository()),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a "Messages" entry point', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final messagingRepo = FakeMessagingRepository();

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, messagingRepository: messagingRepo);

    expect(find.text('Messages'), findsOneWidget);
  });

  testWidgets('tapping "Messages" resolves the conversation and navigates to it', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final messagingRepo = FakeMessagingRepository()..conversationToReturn = testConversation(id: 'conv-99', leadId: 'l1');

    await _pumpLeadDetailScreen(
      tester,
      leadRepository: leadRepo,
      messagingRepository: messagingRepo,
      extraRoutes: [
        GoRoute(path: '/app/messages/conv-99', builder: (context, state) => const Scaffold(body: Text('CONVERSATION_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();

    expect(messagingRepo.lastGetOrCreateLeadId, 'l1');
    expect(find.text('CONVERSATION_DETAIL_MARKER'), findsOneWidget);
  });
}
