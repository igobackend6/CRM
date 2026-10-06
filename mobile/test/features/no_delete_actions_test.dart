import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/documents/domain/entities/document.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/documents/presentation/widgets/documents_section.dart';
import 'package:mobile/features/leads/domain/entities/lead_bulk_action.dart';
import 'package:mobile/features/leads/domain/lead_list_mode.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_list_screen.dart';
import 'package:mobile/features/whatsapp/presentation/providers/whatsapp_providers.dart';
import 'package:mobile/features/whatsapp/presentation/screens/message_templates_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../core/realtime/fake_realtime_service.dart';
import '../services/api/fake_me_api_data_source.dart';
import 'auth/fake_auth_repository.dart';
import 'documents/fake_document_repository.dart';
import 'leads/fake_lead_repository.dart';
import 'whatsapp/fake_message_template_repository.dart';
import 'workspace/fake_workspace_repository.dart';

/// Deleting anything is an admin-only action, done in the admin web. The mobile app offers no delete
/// for leads, documents or message templates: no button, no menu entry, no code path.
Future<void> _pump(WidgetTester tester, Widget screen, List<Override> overrides) async {
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final router = GoRouter(initialLocation: '/', routes: [GoRoute(path: '/', builder: (context, state) => screen)]);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  // The screens load once a workspace is selected (as in the app, where the route guard guarantees it).
  container.read(workspaceControllerProvider);
  for (var i = 0; i < 20 && container.read(workspaceControllerProvider).selected == null; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(container.read(workspaceControllerProvider).selected, isNotNull, reason: 'test harness: workspace never selected');

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bulk actions menu offers Assign, Unassign and Change status, and no Delete', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp', isCustomer: true)]
      ..totalToReturn = 1;
    await _pump(tester, const LeadListScreen(mode: LeadListMode.customers), [leadRepositoryProvider.overrideWithValue(repo)]);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();

    for (final action in LeadBulkAction.values) {
      expect(find.text(action.label), findsOneWidget);
    }
    expect(LeadBulkAction.values.map((a) => a.label).toSet(), {'Assign', 'Unassign', 'Change status'});
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a lead\'s documents can be opened but not deleted', (tester) async {
    final repo = FakeDocumentRepository()
      ..documentsToReturn = [Document(id: 'd1', fileName: 'contract.pdf', createdAt: DateTime.utc(2026, 1, 1))]
      ..documentsTotalToReturn = 1;
    await _pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: DocumentsSection(leadId: 'l1'))),
      [documentRepositoryProvider.overrideWithValue(repo)],
    );

    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('message templates can be edited but not deleted', (tester) async {
    final repo = FakeMessageTemplateRepository()..templatesToReturn = [testTemplate(name: 'Follow-up')];
    await _pump(tester, const MessageTemplatesScreen(), [messageTemplateRepositoryProvider.overrideWithValue(repo)]);

    expect(find.text('Follow-up'), findsOneWidget);
    expect(find.byTooltip('New template'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
