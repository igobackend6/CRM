import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/dialer/presentation/providers/native_dialer_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/call_outcome/domain/interested_in_field.dart';
import 'package:mobile/features/call_outcome/domain/pending_call_outcome.dart';
import 'package:mobile/features/call_outcome/presentation/providers/call_outcome_providers.dart';
import 'package:mobile/features/call_outcome/presentation/widgets/call_outcome_listener.dart';
import 'package:mobile/features/custom_fields/domain/entities/custom_field.dart';
import 'package:mobile/features/custom_fields/domain/repositories/custom_field_repository.dart';
import 'package:mobile/features/custom_fields/presentation/providers/custom_field_providers.dart';
import 'package:mobile/features/leads/domain/entities/lead.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/widgets/lead_contact_actions.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';
import 'package:mobile/features/settings/presentation/providers/settings_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../settings/settings_fakes.dart' show FakeAppSettingsStorage;
import '../workspace/fake_workspace_repository.dart';
import '../dialer/fake_native_dialer_service.dart';

const _statusNew = LeadStatus(id: 's-new', name: 'New', code: 'new', sortOrder: 10, stage: 'start', isDefault: true);
const _statusFollowUp = LeadStatus(id: 's-follow', name: 'Follow Up', code: 'follow_up', sortOrder: 20, stage: 'in_progress', isDefault: false);
const _statusConverted = LeadStatus(id: 's-conv', name: 'Converted', code: 'converted', sortOrder: 30, stage: 'closed_won', isDefault: false);

CustomField _interestedIn({List<CustomFieldOption>? options}) => CustomField(
      id: 'cf1',
      name: 'Interested In',
      code: 'interested_in',
      fieldType: 'options',
      options: options ??
          const [
            CustomFieldOption(code: 'nursery', label: 'Nursery', sortOrder: 1),
            CustomFieldOption(code: 'polyhouse', label: 'Polyhouse', sortOrder: 2),
            CustomFieldOption(code: 'joint_venture', label: 'Joint venture', sortOrder: 3),
          ],
      autoFill: true,
      isFilterable: false,
      isReadonly: false,
      isMandatory: false,
      sortOrder: 0,
    );

class _FakeCustomFieldRepository implements CustomFieldRepository {
  List<CustomField> fields = [];
  Object? error;

  @override
  Future<List<CustomField>> listFields({required String accessToken, required String workspaceId}) async {
    if (error != null) throw error!;
    return fields;
  }
}

class _RecordingLauncher implements ExternalUrlLauncher {
  final List<Uri> launched = [];
  bool result = true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return result;
  }
}

Lead _lead({LeadStatus? status, Map<String, dynamic> customFields = const {}}) => Lead(
      id: 'l1',
      workspaceId: 'w1',
      name: 'Suguna',
      phone: '8925958929',
      priority: 'high',
      isCustomer: false,
      status: status,
      customFields: customFields,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class _Harness {
  _Harness(this.container, this.leads, this.fields, this.launcher);

  final ProviderContainer container;
  final FakeLeadRepository leads;
  final _FakeCustomFieldRepository fields;
  final _RecordingLauncher launcher;
}

/// Pumps a screen with the call buttons for lead "Suguna" under the real app-wide listener, on a router
/// that uses the root navigator key (as the app does), so the pop-up opens over the page.
Future<_Harness> _pumpApp(WidgetTester tester, {FakeLeadRepository? leads, List<CustomField>? fields}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final leadRepo = leads ??
      (FakeLeadRepository()
        ..leadToReturn = _lead(status: _statusNew)
        ..statusesToReturn = [_statusNew, _statusFollowUp, _statusConverted]);
  final fieldRepo = _FakeCustomFieldRepository()..fields = fields ?? [_interestedIn()];
  final launcher = _RecordingLauncher();
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      leadRepositoryProvider.overrideWithValue(leadRepo),
      customFieldRepositoryProvider.overrideWithValue(fieldRepo),
      leadContactLauncherProvider.overrideWithValue(launcher),
      nativeDialerServiceProvider.overrideWithValue(FakeNativeDialerService()),
      realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      appSettingsStorageProvider.overrideWithValue(FakeAppSettingsStorage()),
    ],
  );
  addTearDown(container.dispose);
  container.read(workspaceControllerProvider);
  for (var i = 0; i < 20 && container.read(workspaceControllerProvider).selected == null; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(container.read(workspaceControllerProvider).selected, isNotNull, reason: 'test harness: workspace never selected');

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: LeadContactActions(phone: '8925958929', leadId: 'l1', leadName: 'Suguna')),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, builder: (context, child) => CallOutcomeListener(child: child ?? const SizedBox.shrink())),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container, leadRepo, fieldRepo, launcher);
}

/// What the phone does around a call: the app goes to the background, then comes back.
Future<void> _leaveAndReturn(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  group('findInterestedInField / optionForStoredValue', () {
    test('finds the single-choice field by its code', () {
      expect(findInterestedInField([_interestedIn()])?.code, 'interested_in');
    });

    test('finds it by its name too, ignoring case and spaces', () {
      final field = CustomField(
        id: 'x', name: '  interested IN ', code: 'project_type', fieldType: 'options', options: const [],
        autoFill: true, isFilterable: false, isReadonly: false, isMandatory: false, sortOrder: 0,
      );
      expect(findInterestedInField([field])?.code, 'project_type');
    });

    test('is null when the admin has not created it, or it is not a single-choice field', () {
      expect(findInterestedInField(const []), isNull);
      final text = CustomField(
        id: 'x', name: 'Interested In', code: 'interested_in', fieldType: 'text',
        autoFill: true, isFilterable: false, isReadonly: false, isMandatory: false, sortOrder: 0,
      );
      expect(findInterestedInField([text]), isNull);
    });

    test('a stored value matches an option by code, or by label when stored as plain text', () {
      final field = _interestedIn();
      expect(optionForStoredValue(field, 'polyhouse')?.label, 'Polyhouse');
      expect(optionForStoredValue(field, 'joint venture')?.code, 'joint_venture');
      expect(optionForStoredValue(field, 'jointventure'), isNull);
      expect(optionForStoredValue(field, ' JOINT VENTURE ')?.code, 'joint_venture');
      expect(optionForStoredValue(field, null), isNull);
      expect(optionForStoredValue(field, 42), isNull);
    });
  });

  group('starting a call', () {
    testWidgets('Call opens the dialer and marks that lead as awaiting its result', (tester) async {
      final h = await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(h.launcher.launched.single.scheme, 'tel');
      final pending = h.container.read(pendingCallOutcomeProvider);
      expect(pending?.leadId, 'l1');
      expect(pending?.leadName, 'Suguna');
    });

    testWidgets('WhatsApp call does the same', (tester) async {
      final h = await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      expect(h.launcher.launched.single.host, 'wa.me');
      expect(h.container.read(pendingCallOutcomeProvider)?.leadId, 'l1');
    });

    testWidgets('if the dialer cannot be opened, nothing is left waiting for a result', (tester) async {
      final h = await _pumpApp(tester);
      h.launcher.result = false;

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });

    testWidgets('buttons not tied to a lead never start the pop-up flow', (tester) async {
      final h = await _pumpApp(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(home: Scaffold(body: Center(child: LeadContactActions(phone: '8925958929')))),
        ),
      );

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });
  });

  group('after the call', () {
    testWidgets('coming back to the app opens the pop-up with Interested In, Status and Submit', (tester) async {
      final h = await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
      expect(find.text('Call summary'), findsOneWidget);
      expect(find.text('Suguna'), findsWidgets);
      expect(find.byKey(const Key('call-outcome-interested-in')), findsOneWidget);
      expect(find.byKey(const Key('call-outcome-status')), findsOneWidget);
      expect(find.byKey(const Key('call-outcome-submit')), findsOneWidget);
      expect(h.leads.lastOutcomeLeadId, isNull, reason: 'nothing is saved until Submit');
    });

    testWidgets('the same happens after a WhatsApp call', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
    });

    testWidgets('it does not open the instant the button is tapped, only once the app has been left and returned to', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);

      // Resuming without having gone to the background first (e.g. a permission sheet) is not "back from a call".
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
    });

    testWidgets('Enable Note Dialog = Never: no pop-up, and the call is forgotten', (tester) async {
      final h = await _pumpApp(tester);
      await h.container.read(appSettingsControllerProvider.notifier).setNoteDialogMode(NoteDialogMode.never);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });

    testWidgets('Enable Note Dialog = Only for leads: still opens for a lead', (tester) async {
      final h = await _pumpApp(tester);
      await h.container.read(appSettingsControllerProvider.notifier).setNoteDialogMode(NoteDialogMode.onlyForLeads);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
    });

    testWidgets('Enable Note Dialog = Only for leads: skipped when the person is already a customer', (tester) async {
      final h = await _pumpApp(tester);
      await h.container.read(appSettingsControllerProvider.notifier).setNoteDialogMode(NoteDialogMode.onlyForLeads);
      h.container.read(pendingCallOutcomeProvider.notifier).state =
          const PendingCallOutcome(leadId: 'l1', leadName: 'Suguna', isCustomer: true);

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });

    testWidgets('Enable Note Dialog = All calls (the default): opens for a customer too', (tester) async {
      final h = await _pumpApp(tester);
      h.container.read(pendingCallOutcomeProvider.notifier).state =
          const PendingCallOutcome(leadId: 'l1', leadName: 'Suguna', isCustomer: true);

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
    });

    testWidgets('with no call started, returning to the app shows nothing', (tester) async {
      await _pumpApp(tester);

      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
    });

    testWidgets('the dropdowns list the admin\'s project types and statuses, starting on the lead\'s current values', (tester) async {
      await _pumpApp(
        tester,
        leads: FakeLeadRepository()
          ..leadToReturn = _lead(status: _statusFollowUp, customFields: {'interested_in': 'polyhouse'})
          ..statusesToReturn = [_statusNew, _statusFollowUp, _statusConverted],
      );
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      // Current values are pre-selected.
      expect(find.descendant(of: find.byKey(const Key('call-outcome-status')), matching: find.text('Follow Up')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('call-outcome-interested-in')), matching: find.text('Polyhouse')), findsOneWidget);

      await tester.tap(find.byKey(const Key('call-outcome-interested-in')));
      await tester.pumpAndSettle();
      for (final label in ['Nursery', 'Polyhouse', 'Joint venture']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('Joint venture').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('call-outcome-status')));
      await tester.pumpAndSettle();
      for (final label in ['New', 'Follow Up', 'Converted']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('Submit updates that lead with the chosen status and Interested In, then closes the pop-up', (tester) async {
      final h = await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      await tester.tap(find.byKey(const Key('call-outcome-interested-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nursery').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call-outcome-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Converted').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call-outcome-submit')));
      await tester.pumpAndSettle();

      expect(h.leads.lastOutcomeLeadId, 'l1');
      expect(h.leads.lastOutcomeStatusId, 's-conv');
      expect(h.leads.lastOutcomeCustomFields, {'interested_in': 'nursery'});
      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
      expect(find.text('Suguna updated.'), findsOneWidget);
      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });

    testWidgets('the pop-up cannot be dismissed by tapping outside or with the back button', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
    });

    testWidgets('Interested In is a disabled placeholder until the admin adds project types; Status still works', (tester) async {
      final h = await _pumpApp(tester, fields: const []);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      expect(find.text('No project types added yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('call-outcome-interested-in')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Nursery'), findsNothing);

      await tester.tap(find.byKey(const Key('call-outcome-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow Up').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call-outcome-submit')));
      await tester.pumpAndSettle();

      expect(h.leads.lastOutcomeStatusId, 's-follow');
      expect(h.leads.lastOutcomeCustomFields, isNull);
    });

    testWidgets('a failure to read custom fields does not stop the status being recorded', (tester) async {
      final h = await _pumpApp(tester);
      h.fields.error = const NetworkException('offline');
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      expect(find.byKey(const Key('call-outcome-status')), findsOneWidget);
      expect(find.text('No project types added yet'), findsOneWidget);
    });

    testWidgets('Submit is disabled until a status is chosen', (tester) async {
      await _pumpApp(tester, leads: FakeLeadRepository()..leadToReturn = _lead()..statusesToReturn = [_statusNew, _statusFollowUp]);
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      expect(tester.widget<FilledButton>(find.byKey(const Key('call-outcome-submit'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('call-outcome-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New').last);
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.byKey(const Key('call-outcome-submit'))).onPressed, isNotNull);
    });

    testWidgets('a save failure shows the message and keeps the pop-up open so it can be retried', (tester) async {
      final h = await _pumpApp(tester);
      h.leads.outcomeError = const NetworkException('Could not reach the server.');
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      await tester.tap(find.byKey(const Key('call-outcome-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.byKey(const Key('call-outcome-dialog')), findsOneWidget);
      expect(h.container.read(pendingCallOutcomeProvider), isNotNull);

      h.leads.outcomeError = null;
      await tester.tap(find.byKey(const Key('call-outcome-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
      expect(h.leads.lastOutcomeLeadId, 'l1');
    });

    testWidgets('if the lead cannot be loaded there is a Retry and a Close, so the member is never stuck', (tester) async {
      final h = await _pumpApp(tester);
      h.leads.getError = const NetworkException('offline');
      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();
      await _leaveAndReturn(tester);

      expect(find.text('offline'), findsOneWidget);

      await tester.tap(find.byKey(const Key('call-outcome-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-outcome-dialog')), findsNothing);
      expect(h.container.read(pendingCallOutcomeProvider), isNull);
    });

    testWidgets('a second call replaces the first as the one awaiting a result', (tester) async {
      final h = await _pumpApp(tester);
      h.container.read(pendingCallOutcomeProvider.notifier).state = const PendingCallOutcome(leadId: 'old', leadName: 'Old');

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(h.container.read(pendingCallOutcomeProvider)?.leadId, 'l1');
    });
  });
}
