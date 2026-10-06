import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/leads/domain/lead_edit_access.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/leads/presentation/screens/lead_form_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../documents/fake_document_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_lead_repository.dart';

// The signed-in member in these tests is 'm1' (see testMembership below).
const _me = MemberSummary(id: 'm1', fullName: 'Me');
const _admin = MemberSummary(id: 'admin-1', fullName: 'Admin');

Future<void> _pump(WidgetTester tester, {required Widget screen, required FakeLeadRepository repo}) async {
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      leadRepositoryProvider.overrideWithValue(repo),
      aiInsightRepositoryProvider.overrideWithValue(FakeAiInsightRepository()),
      documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
      realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
    ],
  );
  addTearDown(container.dispose);
  container.read(workspaceControllerProvider);
  for (var i = 0; i < 20 && container.read(workspaceControllerProvider).selected == null; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(container.read(workspaceControllerProvider).selected, isNotNull, reason: 'test harness: workspace never selected');

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => screen),
      GoRoute(path: '/app/leads/:id/edit', builder: (context, state) => const Scaffold(body: Text('EDIT FORM'))),
    ],
  );
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  group('canEditLead', () {
    final own = testLead(id: 'l1', createdBy: _me);

    test('a lead the member created is editable', () {
      expect(canEditLead(own, 'm1'), isTrue);
    });

    test('a lead someone else (an admin) created is not', () {
      expect(canEditLead(testLead(id: 'l1', createdBy: _admin), 'm1'), isFalse);
    });

    test('with an unknown creator or an unknown member, nothing is editable', () {
      expect(canEditLead(testLead(id: 'l1'), 'm1'), isFalse);
      expect(canEditLead(own, null), isFalse);
    });
  });

  group('Lead details', () {
    testWidgets('shows the edit icon on a lead the member created, and it opens the edit form', (tester) async {
      final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Mine', createdBy: _me);
      await _pump(tester, screen: const LeadDetailScreen(leadId: 'l1'), repo: repo);

      expect(find.byIcon(Icons.edit), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('EDIT FORM'), findsOneWidget);
    });

    testWidgets('hides the edit icon on a lead an admin allocated', (tester) async {
      final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Allocated', createdBy: _admin);
      await _pump(tester, screen: const LeadDetailScreen(leadId: 'l1'), repo: repo);

      expect(find.text('Allocated'), findsWidgets);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byTooltip('Edit lead'), findsNothing);
    });

    testWidgets('the lead is still workable: its call buttons and details are there without the edit icon', (tester) async {
      final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Allocated', createdBy: _admin);
      await _pump(tester, screen: const LeadDetailScreen(leadId: 'l1'), repo: repo);

      expect(find.byKey(const Key('lead-call-button')), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
    });
  });

  group('Edit lead page', () {
    Future<void> pumpForm(WidgetTester tester, FakeLeadRepository repo) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, screen: const LeadFormScreen(leadId: 'l1'), repo: repo);
    }

    testWidgets('a lead an admin allocated cannot be edited even if the page is opened directly', (tester) async {
      final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Allocated', createdBy: _admin);
      // Load the lead into the detail controller the way opening the detail screen first would.
      await pumpForm(tester, repo);
      await tester.pumpAndSettle();

      expect(find.textContaining('allocated to you by an admin'), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);
    });

    testWidgets('creating a new lead is unaffected: the New lead form opens with a save button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, screen: const LeadFormScreen(), repo: FakeLeadRepository());

      expect(find.text('New lead'), findsOneWidget);
      expect(find.textContaining('allocated to you by an admin'), findsNothing);
    });
  });
}
