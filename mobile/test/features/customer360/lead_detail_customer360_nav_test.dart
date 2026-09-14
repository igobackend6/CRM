import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
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

/// Verifies Phase 8 §8's Lead Detail -> Customer 360 integration point:
/// a "View Customer 360" action appears only when lead.isCustomer, and
/// navigates to /app/customers/{id}; a non-customer lead gets Phase 18's
/// "Convert to Customer" action instead (never a silent/broken link).
Future<void> _pumpLeadDetailScreen(
  WidgetTester tester, {
  required FakeLeadRepository leadRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
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
  testWidgets('a customer lead shows "View Customer 360" and navigates to it', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: true);

    await _pumpLeadDetailScreen(
      tester,
      leadRepository: leadRepo,
      extraRoutes: [
        GoRoute(path: '/app/customers/l1', builder: (context, state) => const Scaffold(body: Text('CUSTOMER_360_MARKER'))),
      ],
    );

    expect(find.text('View Customer 360'), findsOneWidget);

    await tester.tap(find.text('View Customer 360'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOMER_360_MARKER'), findsOneWidget);
  });

  testWidgets('a non-customer lead shows "Convert to Customer" instead of a link', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: false);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('Convert to Customer'), findsOneWidget);
    expect(find.text('View Customer 360'), findsNothing);
  });
}
