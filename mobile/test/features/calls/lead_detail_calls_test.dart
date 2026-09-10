import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/core/widgets/widgets.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../documents/fake_document_repository.dart';
import '../followups/fake_follow_up_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

/// Verifies Phase 9 §6's integration point: Lead Detail shows a Calls
/// section fed by [leadCallsProvider] and can navigate to Log Call and
/// to an existing call's detail screen — without duplicating any call
/// state (§6/§10: reuses the same CallTile/providers the calls feature
/// itself uses).
Future<void> _pumpLeadDetailScreen(
  WidgetTester tester, {
  required FakeLeadRepository leadRepository,
  required FakeCallRepository callRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // Same reasoning as lead_detail_followups_test.dart: the Calls section
  // sits well below the default test surface's viewport+cache extent.
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
        callRepositoryProvider.overrideWithValue(callRepository),
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
  testWidgets('shows the lead\'s calls', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final callRepo = FakeCallRepository()..leadCallsToReturn = [testCall(id: 'call-1', direction: 'inbound')];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, callRepository: callRepo);

    // Phase 15 also adds a "Calls" activity-filter chip elsewhere on this
    // screen, so a bare find.text('Calls') is no longer unique — scope to
    // the section header specifically.
    expect(find.widgetWithText(SectionHeader, 'Calls'), findsOneWidget);
    expect(find.byIcon(Icons.call_received), findsOneWidget);
  });

  testWidgets('shows "No calls logged yet." when there are none', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final callRepo = FakeCallRepository();

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, callRepository: callRepo);

    expect(find.text('No calls logged yet.'), findsOneWidget);
  });

  testWidgets('"Log call" navigates to the create form for this lead', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final callRepo = FakeCallRepository();

    await _pumpLeadDetailScreen(
      tester,
      leadRepository: leadRepo,
      callRepository: callRepo,
      extraRoutes: [
        GoRoute(
          path: '/app/calls/create',
          builder: (context, state) => Scaffold(body: Text('CREATE_MARKER leadId=${state.uri.queryParameters['leadId']}')),
        ),
      ],
    );

    await tester.tap(find.text('Log call'));
    await tester.pumpAndSettle();

    expect(find.text('CREATE_MARKER leadId=l1'), findsOneWidget);
  });

  testWidgets('a call load failure does not block the rest of the lead detail screen', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
    final callRepo = FakeCallRepository()..leadCallsError = Exception('boom');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, callRepository: callRepo);

    // The lead's own info still renders even though its Calls section
    // failed independently.
    expect(find.text('Acme Corp'), findsAtLeastNWidgets(1));
    expect(find.text('Could not load calls.'), findsOneWidget);
  });
}
