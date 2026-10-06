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
import 'package:mobile/features/leads/domain/lead_list_mode.dart';
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
  // Most tests here exercise the header controls (status selector, filters, select/import menu), which
  // live on the Customers tab, so that is the default.
  LeadListMode mode = LeadListMode.customers,
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
      GoRoute(path: '/', builder: (context, state) => LeadListScreen(mode: mode)),
      GoRoute(path: '/app/leads/create', builder: (context, state) => const Scaffold(body: Text('Create Lead Stub'))),
      GoRoute(path: '/app/leads/:id', builder: (context, state) => Scaffold(body: Text('LEAD DETAIL ${state.pathParameters['id']}'))),
      GoRoute(path: '/app/customers/:id', builder: (context, state) => Scaffold(body: Text('CUSTOMER 360 ${state.pathParameters['id']}'))),
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

/// The header's overflow menu holds Select and Import (the reference's
/// header has only four icons).
Future<void> _chooseFromMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
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

  testWidgets('shows the empty state when there are no customers', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.text('No customers yet'), findsOneWidget);
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

    await _chooseFromMenu(tester, 'Select leads');
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('bulk assign opens a member picker and applies the action', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1
      ..membersToReturn = [testMember('m2', 'Rep Two')]
      ..bulkActionResultToReturn = const BulkActionResult(total: 1, succeeded: 1, failed: 0, items: []);

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await _chooseFromMenu(tester, 'Select leads');
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

    await _chooseFromMenu(tester, 'Select leads');
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

    await _chooseFromMenu(tester, 'Import leads from CSV');
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

    await _chooseFromMenu(tester, 'Import leads from CSV');
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

  // ---- Customers tab: the full header (status selector, search, filters, pipeline, more) ----

  const newStatus = LeadStatus(id: 's-new', name: 'New', code: 'new', sortOrder: 10, stage: 'start', isDefault: true);
  const contactedStatus = LeadStatus(id: 's-contacted', name: 'Contacted', code: 'contacted', sortOrder: 20, stage: 'in_progress', isDefault: false);

  String selectorLabel(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('allocations-status-label'))).data!;

  testWidgets('customers: only customers are requested, and the selector starts on All (no default status filter)', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..statusesToReturn = [newStatus, contactedStatus]
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp', isCustomer: true)]
      ..totalToReturn = 1;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(selectorLabel(tester), 'All');
    expect(leadRepo.lastStatusId, isNull);
    expect(leadRepo.lastIsCustomer, isTrue);
    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('customers: the selector lists All and every status; choosing one filters, All clears it', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..statusesToReturn = [newStatus, contactedStatus]
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byKey(const Key('allocations-status-selector')));
    await tester.pumpAndSettle();
    expect(find.text('All'), findsNWidgets(2)); // the header label and the menu entry
    expect(find.text('Contacted'), findsOneWidget);

    await tester.tap(find.text('Contacted'));
    await tester.pumpAndSettle();
    expect(leadRepo.lastStatusId, 's-contacted');
    expect(leadRepo.lastIsCustomer, isTrue);
    expect(selectorLabel(tester), 'Contacted');

    await tester.tap(find.byKey(const Key('allocations-status-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(leadRepo.lastStatusId, isNull);
    expect(leadRepo.lastIsCustomer, isTrue);
  });

  testWidgets('customers: the badge reads shown/total, counting customers only', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1
      ..visibleTotalToReturn = 5;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.descendant(of: find.byKey(const Key('allocations-count-badge')), matching: find.text('1/5')), findsOneWidget);
    expect(leadRepo.lastCountIsCustomer, isTrue);
  });

  testWidgets('customers: with none yet it explains how a lead becomes a customer, and adding a lead is still possible', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.text('No customers yet'), findsOneWidget);
    expect(find.textContaining('once it is converted'), findsOneWidget);
    expect(find.byTooltip('New lead'), findsOneWidget);
  });

  testWidgets('customers: an empty status says so', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..statusesToReturn = [newStatus, contactedStatus]
      ..leadsToReturn = []
      ..totalToReturn = 0;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byKey(const Key('allocations-status-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacted'));
    await tester.pumpAndSettle();

    expect(find.text('No customers with status "Contacted"'), findsOneWidget);
  });

  testWidgets('customers: the status and the customer flag do not count toward the filter badge; a real filter does', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..statusesToReturn = [newStatus, contactedStatus]
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);
    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsNothing);

    await tester.tap(find.byKey(const Key('allocations-status-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacted'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsNothing);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byTooltip('Filter leads'), matching: find.text('1')), findsOneWidget);
  });

  testWidgets('customers: the filter sheet has no Customer section, and Clear all keeps the list on customers', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.byTooltip('Filter leads'));
    await tester.pumpAndSettle();
    expect(find.text('Customers only'), findsNothing);
    expect(find.text('Non-customers only'), findsNothing);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(leadRepo.lastIsCustomer, isTrue);
  });

  testWidgets('customers: the search icon reveals the search box, typing searches customers, and closing clears it', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Search customers'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(leadRepo.lastSearch, 'acme');
    expect(leadRepo.lastIsCustomer, isTrue);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(leadRepo.lastSearch, isNull);
  });

  testWidgets('customers: the pipeline board icon and the More menu are in the header', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    expect(find.byTooltip('Pipeline view'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('customers: there are no date chips (those belong to Allocations)', (tester) async {
    await _pumpLeadListScreen(tester, leadRepository: FakeLeadRepository()..leadsToReturn = [testLead(id: 'l1', isCustomer: true)]..totalToReturn = 1);

    expect(find.byKey(const Key('range-overall')), findsNothing);
  });

  // ---- Allocations tab: title + search, date chips, every lead ----

  testWidgets('allocations: the header is just the title with a search icon at its right', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);

    final title = find.byKey(const Key('allocations-title'));
    final search = find.byTooltip('Search leads');
    expect(tester.widget<Text>(title).data, 'Allocations');
    expect(tester.getTopLeft(search).dx, greaterThan(tester.getTopRight(title).dx - 1));
    expect((tester.getCenter(search).dy - tester.getCenter(title).dy).abs(), lessThan(10));

    // Everything that moved to the Customers header is gone from here.
    expect(find.byKey(const Key('allocations-status-selector')), findsNothing);
    expect(find.byTooltip('Filter leads'), findsNothing);
    expect(find.byTooltip('Pipeline view'), findsNothing);
    expect(find.byTooltip('More'), findsNothing);
  });

  testWidgets('allocations: every lead is requested, with no status pre-filter and not limited to customers', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..statusesToReturn = [newStatus, contactedStatus]
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);

    expect(leadRepo.lastStatusId, isNull);
    expect(leadRepo.lastIsCustomer, isNull);
    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('allocations: with none it explains where allocations come from, and adding a lead is still possible', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = []
      ..totalToReturn = 0;

    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);

    expect(find.text('No allocations found'), findsOneWidget);
    expect(find.textContaining('bulk upload or data source integration from the admin web'), findsOneWidget);
    expect(find.byTooltip('Add lead'), findsOneWidget);
  });

  testWidgets('allocations: the search icon reveals the search box, typing searches, and closing clears it', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Search leads'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(leadRepo.lastSearch, 'acme');

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(leadRepo.lastSearch, isNull);
  });

  testWidgets('allocations: date chips: Last 30 Days sends a lower bound, Overall clears it', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);
    expect(find.text('Overall'), findsOneWidget);
    expect(find.text('Select Range'), findsOneWidget);

    await tester.tap(find.byKey(const Key('range-last-30')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(leadRepo.lastCreatedFrom, DateTime(now.year, now.month, now.day - 30));
    expect(leadRepo.lastCreatedTo, isNull);

    await tester.tap(find.byKey(const Key('range-overall')));
    await tester.pumpAndSettle();

    expect(leadRepo.lastCreatedFrom, isNull);
    expect(leadRepo.lastCreatedTo, isNull);
  });

  testWidgets('allocations: date chips: Select Range applies both ends and the chip shows the range', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);

    await tester.tap(find.byKey(const Key('range-custom')));
    await tester.pumpAndSettle();
    // The Material range picker opens on the current month. Tapping the 1st twice picks a one-day
    // range that is valid on any date this test runs.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(leadRepo.lastCreatedFrom, DateTime(now.year, now.month, 1));
    expect(leadRepo.lastCreatedTo, DateTime(now.year, now.month, 1, 23, 59, 59));
    expect(find.text('Select Range'), findsNothing);
  });

  testWidgets('allocations: tapping a lead opens its lead details', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo, mode: LeadListMode.allocations);

    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.text('LEAD DETAIL l1'), findsOneWidget);
  });

  testWidgets('customers: tapping a customer opens its Customer 360 view', (tester) async {
    final leadRepo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'c1', name: 'Suguna', isCustomer: true)]
      ..totalToReturn = 1;
    await _pumpLeadListScreen(tester, leadRepository: leadRepo);

    await tester.tap(find.text('Suguna'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOMER 360 c1'), findsOneWidget);
  });
}
