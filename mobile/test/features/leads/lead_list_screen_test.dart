import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/leads/domain/entities/bulk_action_result.dart';
import 'package:mobile/features/leads/domain/entities/lead_bulk_action.dart';
import 'package:mobile/features/leads/domain/entities/lead_import_state.dart';
import 'package:mobile/features/leads/domain/entities/lead_source.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/tag.dart';
import 'package:mobile/features/leads/presentation/controllers/csv_file_picker.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_csv_file_picker.dart';
import 'fake_lead_filter_storage.dart';
import 'fake_lead_repository.dart';

Future<void> _pumpLeadListScreen(
  WidgetTester tester, {
  required FakeLeadRepository leadRepository,
  FakeCsvFilePicker? csvFilePicker,
  FakeLeadFilterStorage? leadFilterStorage,
}) async {
  // Phase 14's filter sheet is genuinely tall (eight filter sections plus
  // saved views) — taller than the default flutter_test surface
  // (800x600), which would put "Apply filters"/"Clear all" off-screen and
  // un-tappable. Same widening as dashboard_screen_test.dart/
  // pipeline_screen_test.dart, applied for every test in this file since
  // it doesn't affect any existing assertion here.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LeadListScreen()),
      GoRoute(path: '/app/leads/create', builder: (context, state) => const Scaffold(body: Text('Create Lead Stub'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(leadRepository),
        csvFilePickerProvider.overrideWithValue(csvFilePicker ?? FakeCsvFilePicker()),
        leadFilterStorageProvider.overrideWithValue(leadFilterStorage ?? FakeLeadFilterStorage()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  // The fakes resolve on microtasks (no real delays), and
  // LeadListController reactively refreshes once the workspace becomes
  // selected (see lead_list_controller.dart) — so plain pumpAndSettle is
  // enough to reach the final state, no manual polling needed.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders leads with their name, status and assigned member', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no leads', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.textContaining('No leads yet'), findsOneWidget);
  });

  testWidgets('tapping the add button navigates to the create route', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Create Lead Stub'), findsOneWidget);
  });

  // ---- Phase 13: bulk selection & actions ----

  testWidgets('the select icon enters selection mode, and select-all checks every visible lead', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp'), testLead(id: 'l2', name: 'Globex')]
      ..totalToReturn = 2;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Select leads'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('bulk delete requires confirmation; cancelling does not call the repository', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Select leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete these leads?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastBulkAction, isNull);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('confirming bulk delete calls the repository, exits selection mode, and shows a summary', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1
      ..bulkActionResultToReturn = const BulkActionResult(total: 1, succeeded: 1, failed: 0, items: []);

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Select leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastBulkAction, LeadBulkAction.delete);
    expect(leadRepo.lastBulkLeadIds, ['l1']);
    expect(find.text('Leads'), findsOneWidget);
    expect(find.textContaining('1 of 1 leads updated'), findsOneWidget);
  });

  testWidgets('bulk assign opens a member picker and applies the action', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1
      ..membersToReturn = [testMember('m2', 'Rep Two')]
      ..bulkActionResultToReturn = const BulkActionResult(total: 1, succeeded: 1, failed: 0, items: []);

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Select leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();

    expect(find.text('Rep Two'), findsOneWidget);
    await tester.tap(find.text('Rep Two'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastBulkAction, LeadBulkAction.assign);
    expect(leadRepo.lastBulkMemberId, 'm2');
  });

  testWidgets('bulk change status opens a status picker and applies the action', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1
      ..statusesToReturn = [
        const LeadStatus(id: 's2', name: 'Won', code: 'won', sortOrder: 20, stage: 'closed_won', isDefault: false),
      ]
      ..bulkActionResultToReturn = const BulkActionResult(total: 1, succeeded: 1, failed: 0, items: []);

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Select leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change status'));
    await tester.pumpAndSettle();

    expect(find.text('Won'), findsOneWidget);
    await tester.tap(find.text('Won'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastBulkAction, LeadBulkAction.changeStatus);
    expect(leadRepo.lastBulkStatusId, 's2');
  });

  // ---- Phase 13: CSV import ----

  testWidgets('CSV import: picking a file then importing shows the result summary and refreshes the list', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0
      ..importResultToReturn = const LeadImportResult(total: 1, created: 1, failed: 0, errors: []);
    final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\nAcme Corp\n');

    await _pumpLeadListScreen(tester, leadRepository: leadRepo, csvFilePicker: picker);

    await tester.tap(find.byTooltip('Import leads from CSV'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();

    expect(find.text('Selected file: leads.csv'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Imported 1 of 1 rows.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('CSV import with row-level failures displays them in the result sheet', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0
      ..importResultToReturn = const LeadImportResult(
        total: 2,
        created: 1,
        failed: 1,
        errors: [LeadImportRowError(row: 3, error: 'name is required.')],
      );
    final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\nAcme Corp\n,\n');

    await _pumpLeadListScreen(tester, leadRepository: leadRepo, csvFilePicker: picker);

    await tester.tap(find.byTooltip('Import leads from CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Imported 1 of 2 rows.'), findsOneWidget);
    expect(find.textContaining('Row 3: name is required.'), findsOneWidget);
  });

  // ---- Phase 14: advanced filters & saved views ----

  testWidgets('applying a priority filter sends it to the repository and shows the active-filter badge', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsNothing);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastPriority, 'urgent');
    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsOneWidget);
  });

  testWidgets('status, source, assignee, tag and customer selectors all reach the repository together', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1
      ..statusesToReturn = [
        const LeadStatus(id: 's2', name: 'Won', code: 'won', sortOrder: 20, stage: 'closed_won', isDefault: false),
      ]
      ..sourcesToReturn = [const LeadSource(id: 'src1', name: 'Referral', code: 'referral', isDefault: false)]
      ..membersToReturn = [testMember('m2', 'Rep Two')]
      ..tagsToReturn = [const Tag(id: 'tag1', name: 'VIP')];
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Won'));
    await tester.tap(find.text('Referral'));
    await tester.tap(find.text('Rep Two'));
    await tester.tap(find.text('VIP'));
    await tester.tap(find.text('Customers only'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastStatusId, 's2');
    expect(leadRepo.lastSourceId, 'src1');
    expect(leadRepo.lastFilterAssignedMemberId, 'm2');
    expect(leadRepo.lastTagId, 'tag1');
    expect(leadRepo.lastIsCustomer, isTrue);
  });

  testWidgets('Clear all resets an already-applied filter and removes the badge', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(leadRepo.lastPriority, 'urgent');

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastPriority, isNull);
    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsNothing);
  });

  testWidgets('search and an applied filter both survive a pull-to-refresh', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);
    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(leadRepo.lastPriority, 'urgent');
  });

  testWidgets('a previously saved view is listed in the filter sheet and loads its filters back', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    final storage = FakeLeadFilterStorage()
      ..stored = jsonEncode([
        {
          'id': 'v1',
          'name': 'Hot leads',
          'filters': {
            'status_id': null,
            'source_id': null,
            'assigned_member_id': null,
            'priority': 'urgent',
            'is_customer': null,
            'created_from': null,
            'created_to': null,
            'tag_id': null,
          },
        },
      ]);
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, leadFilterStorage: storage);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    expect(find.text('Hot leads'), findsOneWidget);

    await tester.tap(find.text('Hot leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastPriority, 'urgent');
  });

  testWidgets('saving current filters as a named view then deleting it works from the sheet', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    final storage = FakeLeadFilterStorage();
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, leadFilterStorage: storage);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent'));
    await tester.tap(find.text('Save current filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('save_view_name_field')), 'Hot leads');
    await tester.tap(find.byTooltip('Confirm save'));
    await tester.pumpAndSettle();

    expect(find.text('Hot leads'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Hot leads'), findsNothing);
  });
}
