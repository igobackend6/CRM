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

Future<void> _pumpLeadDetailScreen(WidgetTester tester, {required FakeLeadRepository leadRepository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

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
  testWidgets('displays the current assignee (unassigned by default)', (tester) async {
    final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('Assign'), findsOneWidget); // no assignee yet -> button reads "Assign"
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('displays an already-assigned lead\'s assignee', (tester) async {
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

    expect(find.text('Rep One'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget); // already assigned -> button reads "Change"
  });

  testWidgets('assignment picker opens and the member list loads', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersToReturn = [testMember('m1', 'Rep One'), testMember('m2', 'Rep Two')];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();

    expect(find.text('Assign lead'), findsOneWidget);
    expect(find.text('Rep One'), findsOneWidget);
    expect(find.text('Rep Two'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while the member list is loading', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersToReturn = [testMember('m1', 'Rep One')]
      ..membersDelay = const Duration(milliseconds: 300);

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pump(); // open the sheet, don't let the delayed future resolve yet

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Rep One'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no active members', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersToReturn = [];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();

    expect(find.text('No active workspace members found.'), findsOneWidget);
  });

  testWidgets('shows a network error state when the member list fails to load', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersError = const NetworkException('Could not reach the server.');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load workspace members.'), findsOneWidget);
  });

  testWidgets('a successful assignment refreshes the lead detail screen', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersToReturn = [testMember('m2', 'Rep Two')];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rep Two'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastAssignedMemberId, 'm2');
    expect(find.text('Rep Two'), findsOneWidget); // now shown as the assignee on the detail screen
    expect(find.text('Change'), findsOneWidget); // button label flips once assigned
  });

  testWidgets('reassignment replaces the previous assignee', (tester) async {
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
      )
      ..membersToReturn = [testMember('m1', 'Rep One'), testMember('m2', 'Rep Two')];

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    expect(find.text('Change'), findsOneWidget); // already assigned -> "Change", not "Assign"

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget); // current assignee marked in the picker

    await tester.tap(find.text('Rep Two'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastAssignedMemberId, 'm2');
  });

  testWidgets('unassigning clears the assignee', (tester) async {
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

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassign'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastAssignedMemberId, isNull);
    expect(leadRepo.lastAssignCalled, isTrue);
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('a permission-denied assignment failure shows an error message, keeps the prior assignee', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadToReturn = testLead(id: 'l1')
      ..membersToReturn = [testMember('m2', 'Rep Two')]
      ..assignError = const PermissionDeniedException('Missing permission: leads.assign');

    await _pumpLeadDetailScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rep Two'));
    await tester.pumpAndSettle();

    expect(find.text('Missing permission: leads.assign'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget); // assignment did not go through
  });
}
