import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../documents/fake_document_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_lead_repository.dart';

Future<void> _pumpLeadDetailScreen(WidgetTester tester, {required FakeLeadRepository leadRepository}) async {
  // The activity section (composer + filter chips + tiles) is genuinely
  // tall — same widening as Phase 14's filter sheet tests.
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
      GoRoute(path: '/', builder: (context, state) => const LeadDetailScreen(leadId: 'l1')),
      GoRoute(path: '/app/calls/:id', builder: (context, state) => Scaffold(body: Text('Call Detail Stub ${state.pathParameters['id']}'))),
      GoRoute(
        path: '/app/follow-ups/:id',
        builder: (context, state) => Scaffold(body: Text('Follow-Up Detail Stub ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(leadRepository),
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
  testWidgets('renders the unified activity feed for the lead', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..activityItemsToReturn = [testTimelineItem(id: 'call:c1', type: 'call', summary: 'Outbound call — ended')]
      ..activityTotalToReturn = 1;

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('Outbound call — ended'), findsOneWidget);
  });

  testWidgets('shows the empty state when there is no activity yet', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('No activity recorded yet.'), findsOneWidget);
  });

  testWidgets('adding a note via the composer prepends it to the activity feed', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..noteToReturn = testTimelineItem(id: 'note:new', type: 'note', summary: 'Called back');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    expect(find.text('No activity recorded yet.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Add a note…'), 'Called back');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastNoteText, 'Called back');
    expect(find.text('Called back'), findsOneWidget);
  });

  testWidgets('filter chips narrow the visible activity to the selected type', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..activityItemsToReturn = [
        testTimelineItem(id: 'call:c1', type: 'call', summary: 'Outbound call — ended'),
        testTimelineItem(id: 'note:n1', type: 'note', summary: 'A quick note'),
      ]
      ..activityTotalToReturn = 2;

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    expect(find.text('Outbound call — ended'), findsOneWidget);
    expect(find.text('A quick note'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Calls'));
    await tester.pumpAndSettle();

    expect(find.text('Outbound call — ended'), findsOneWidget);
    expect(find.text('A quick note'), findsNothing);
  });

  testWidgets('tapping a call activity navigates to the existing Call Detail screen', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..activityItemsToReturn = [testTimelineItem(id: 'call:c1', type: 'call', summary: 'Outbound call — ended')]
      ..activityTotalToReturn = 1;

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Outbound call — ended'));
    await tester.pumpAndSettle();

    expect(find.text('Call Detail Stub c1'), findsOneWidget);
  });

  testWidgets('tapping a follow-up activity navigates to the existing Follow-Up Detail screen', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..activityItemsToReturn = [testTimelineItem(id: 'follow_up:f1', type: 'follow_up', summary: 'Follow-up scheduled (call) — pending')]
      ..activityTotalToReturn = 1;

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Follow-up scheduled (call) — pending'));
    await tester.pumpAndSettle();

    expect(find.text('Follow-Up Detail Stub f1'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the activity feed', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..activityItemsToReturn = [testTimelineItem(id: 'call:c1', type: 'call', summary: 'Outbound call — ended')]
      ..activityTotalToReturn = 1;

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(leadRepo.lastActivityOffset, 0);
  });
}
