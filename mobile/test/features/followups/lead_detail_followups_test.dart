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
import '../calls/fake_call_repository.dart';
import '../documents/fake_document_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_follow_up_repository.dart';

/// Verifies Phase 7's integration point: Lead Detail shows a follow-up
/// section fed by [leadFollowUpsProvider] and can navigate to Create
/// Follow-Up and to an existing follow-up's detail screen — without
/// duplicating any lead state (Phase 7 §6).
Future<void> _pumpLeadDetailScreen(
  WidgetTester tester, {
  required FakeLeadRepository leadRepository,
  required FakeFollowUpRepository followUpRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // Lead Detail's ListView is long (info rows, tags, assignment history,
  // now follow-ups, activity) — the follow-up section sits well below
  // the default test surface's viewport+cache extent, so a fixed-size
  // ListView(children:) wouldn't build those far-down sliver children
  // without either scrolling or a taller surface. A taller surface is
  // simpler and doesn't depend on scroll-gesture timing.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
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
        followUpRepositoryProvider.overrideWithValue(followUpRepository),
        // Phase 9 added a Calls section to this same screen — override it
        // with an empty (not unconfigured/error) repository so this
        // pre-existing follow-ups test's assertions stay scoped to
        // follow-up state, not incidentally affected by the Calls
        // section's own load.
        callRepositoryProvider.overrideWithValue(FakeCallRepository()),
        aiInsightRepositoryProvider.overrideWithValue(FakeAiInsightRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the lead\'s follow-ups', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final followUpRepo = FakeFollowUpRepository()..leadFollowUpsToReturn = [testFollowUp(id: 'fu-1', type: 'meeting')];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, followUpRepository: followUpRepo);

    // Phase 15 also adds a "Follow-ups" activity-filter chip elsewhere on
    // this screen, so a bare find.text('Follow-ups') is no longer unique
    // — scope to the section header specifically.
    expect(find.widgetWithText(SectionHeader, 'Follow-ups'), findsOneWidget);
    expect(find.textContaining('meeting'), findsOneWidget);
  });

  testWidgets('shows "No follow-ups yet." when there are none', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final followUpRepo = FakeFollowUpRepository();

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, followUpRepository: followUpRepo);

    expect(find.text('No follow-ups yet.'), findsOneWidget);
  });

  testWidgets('"Add follow-up" navigates to the create form for this lead', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final followUpRepo = FakeFollowUpRepository();

    await _pumpLeadDetailScreen(
      tester,
      leadRepository: leadRepo,
      followUpRepository: followUpRepo,
      extraRoutes: [
        GoRoute(
          path: '/app/follow-ups/create',
          builder: (context, state) => Scaffold(body: Text('CREATE_MARKER leadId=${state.uri.queryParameters['leadId']}')),
        ),
      ],
    );

    await tester.tap(find.text('Add follow-up'));
    await tester.pumpAndSettle();

    expect(find.text('CREATE_MARKER leadId=l1'), findsOneWidget);
  });

  testWidgets('tapping a follow-up navigates to its detail route', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
    final followUpRepo = FakeFollowUpRepository()..leadFollowUpsToReturn = [testFollowUp(id: 'fu-1', leadName: 'Acme Corp')];

    await _pumpLeadDetailScreen(
      tester,
      leadRepository: leadRepo,
      followUpRepository: followUpRepo,
      extraRoutes: [
        GoRoute(path: '/app/follow-ups/fu-1', builder: (context, state) => const Scaffold(body: Text('DETAIL_MARKER'))),
      ],
    );

    // 'call' alone is now ambiguous (Phase 9's Calls section header also
    // has a "Log call" button) — the follow-up tile's own text is
    // "<type> • <date>", so match on that shape specifically.
    await tester.tap(find.textContaining('call •'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL_MARKER'), findsOneWidget);
  });

  testWidgets('a follow-up load failure does not block the rest of the lead detail screen', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
    final followUpRepo = FakeFollowUpRepository()..leadFollowUpsError = Exception('boom');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo, followUpRepository: followUpRepo);

    // The lead's own info still renders even though its follow-up
    // section failed independently.
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Could not load follow-ups.'), findsOneWidget);
  });
}
