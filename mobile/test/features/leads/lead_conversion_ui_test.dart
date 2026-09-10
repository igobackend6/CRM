import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/domain/entities/lead.dart';
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

/// Phase 18 — "Convert to Customer" (Lead Detail's `_CustomerBanner`).
/// Same pumping helper/shape as lead_assignment_ui_test.dart, which
/// exercises the same screen's assignment action.
Future<void> _pumpLeadDetailScreen(WidgetTester tester, {required FakeLeadRepository leadRepository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LeadDetailScreen(leadId: 'l1')),
      GoRoute(path: '/app/customers/:id', builder: (context, state) => Text('Customer 360: ${state.pathParameters['id']}')),
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
  testWidgets('shows "Convert to Customer" for a non-customer lead, not the Customer 360 link', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: false);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('Convert to Customer'), findsOneWidget);
    expect(find.text('View Customer 360'), findsNothing);
  });

  testWidgets('shows "View Customer 360" for an already-converted lead, not the convert action', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: true);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('View Customer 360'), findsOneWidget);
    expect(find.text('Convert to Customer'), findsNothing);
  });

  testWidgets('tapping convert opens a confirmation dialog; dismissing it converts nothing', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: false);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Convert to Customer'));
    await tester.pumpAndSettle();

    expect(find.text('Convert to customer?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastConvertCalled, isFalse);
    expect(find.text('Convert to Customer'), findsOneWidget); // still not converted
  });

  testWidgets('shows a loading indicator while the conversion request is in flight', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1', isCustomer: false)
      ..convertDelay = const Duration(milliseconds: 300);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Convert to Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert').last); // the dialog's confirm button
    await tester.pump(); // start the request, don't let the delayed future resolve yet

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('a successful conversion swaps the button for Customer 360 and shows confirmation', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: false);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Convert to Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert').last);
    await tester.pumpAndSettle();

    expect(leadRepo.lastConvertCalled, isTrue);
    expect(find.text('Lead converted to customer.'), findsOneWidget); // success SnackBar
    expect(find.text('View Customer 360'), findsOneWidget); // button swapped
    expect(find.text('Convert to Customer'), findsNothing);
  });

  testWidgets('tapping View Customer 360 after conversion navigates to Customer 360', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: true);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('View Customer 360'));
    await tester.pumpAndSettle();

    expect(find.text('Customer 360: l1'), findsOneWidget);
  });

  testWidgets('a conversion failure shows an error message and keeps the convert action available', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1', isCustomer: false)
      ..convertError = const ConflictException('This lead has already been converted to a customer.');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.text('Convert to Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert').last);
    await tester.pumpAndSettle();

    expect(find.text('This lead has already been converted to a customer.'), findsOneWidget);
    expect(find.text('Convert to Customer'), findsOneWidget); // conversion did not go through
    expect(find.text('View Customer 360'), findsNothing);
  });

  testWidgets('the rest of Lead Detail is unaffected by the conversion action', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = Lead(
        id: 'l1',
        workspaceId: 'w1',
        name: 'Acme Corp',
        priority: 'medium',
        isCustomer: false,
        assignedMember: testMember('m1', 'Rep One'),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    // Existing Lead Detail behavior (assignment row) is still present
    // alongside the new conversion action — no redesign.
    expect(find.text('Rep One'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Convert to Customer'), findsOneWidget);

    // The delete action further down the screen is untouched too.
    await tester.dragUntilVisible(find.text('Delete lead'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('Delete lead'), findsOneWidget);
  });
}
