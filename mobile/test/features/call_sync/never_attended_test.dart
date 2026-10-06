import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/call_sync/data/call_back_follow_ups.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/domain/device_call.dart';
import 'package:mobile/features/call_sync/domain/unattended_calls.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/screens/never_attended_screen.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';

import '../followups/fake_follow_up_repository.dart';
import '../settings/settings_fakes.dart';
import '../sim/sim_fakes.dart';
import 'call_sync_fakes.dart';

void main() {
  final now = DateTime(2026, 10, 2, 15);
  final enabledAt = now.subtract(const Duration(hours: 2));

  late FakeCallLogSource source;
  late FakeCallSyncApi api;
  late FakeCallSyncStorage storage;
  late FakeSimPlatformSource simSource;
  late FakeSimSelectionStorage simStorage;
  late FakeCallBackFollowUps followUps;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('never_attended_test');
    source = FakeCallLogSource(localDir: tmp.path);
    api = FakeCallSyncApi();
    storage = FakeCallSyncStorage();
    simSource = FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'airtel')]);
    simStorage = FakeSimSelectionStorage();
    followUps = FakeCallBackFollowUps();
  });

  tearDown(() => tmp.delete(recursive: true));

  CallSyncRepository repo({DateTime? at}) => CallSyncRepository(
        source: source,
        api: api,
        store: CallSyncStore(storage),
        sims: SimRepository(simSource, simStorage),
        downloader: FakeRecordingDownloader(),
        callBackFollowUps: followUps,
        clock: () => at ?? now,
      );

  Future<void> chooseSim() =>
      SimRepository(simSource, simStorage).select('user-1', const SimCard(subscriptionId: 1, slotIndex: 0, carrierName: 'airtel'));

  Future<void> turnOn({DateTime? since}) async {
    await chooseSim();
    await CallSyncStore(storage).save(
      'user-1',
      'ws-1',
      CallSyncProgress(neverAttendedOn: true, neverAttendedSince: (since ?? enabledAt).millisecondsSinceEpoch),
    );
  }

  Future<CallSyncSummary> sync({bool fromStart = false, CallSyncRepository? r}) =>
      (r ?? repo()).sync(profileId: 'user-1', workspaceId: 'ws-1', fromStart: fromStart);

  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

  group('which calls need a call back', () {
    SyncedDeviceCall call(String id, String lead, int type, DateTime at, {int duration = 0}) => SyncedDeviceCall(
          callId: id,
          leadId: lead,
          call: DeviceCall(id: id.hashCode, type: type, dateMillis: at.millisecondsSinceEpoch, durationSeconds: duration, number: '+919800000001'),
        );

    CallBackPlan plan(List<SyncedDeviceCall> calls, {DateTime? since, Set<String> handled = const {}, int maxLeads = 20}) =>
        planCallBacks(calls: calls, sinceMillis: (since ?? DateTime(2026)).millisecondsSinceEpoch, handled: handled, maxLeads: maxLeads);

    test('a missed call, a rejected call and an outgoing call nobody picked up all count', () {
      final p = plan([
        call('a', 'l1', DeviceCall.typeMissed, ago(60)),
        call('b', 'l2', DeviceCall.typeRejected, ago(50)),
        call('c', 'l3', DeviceCall.typeOutgoing, ago(40)),
      ]);
      expect(p.callBacks.map((c) => c.leadId).toSet(), {'l1', 'l2', 'l3'});
    });

    test('a call that connected, or a blocked one, does not', () {
      final p = plan([
        call('a', 'l1', DeviceCall.typeIncoming, ago(60), duration: 45),
        call('b', 'l2', DeviceCall.typeOutgoing, ago(50), duration: 20),
        call('c', 'l3', DeviceCall.typeBlocked, ago(40)),
      ]);
      expect(p.callBacks, isEmpty);
    });

    test('an unanswered call followed by one that connected needs no reminder', () {
      final p = plan([
        call('a', 'l1', DeviceCall.typeMissed, ago(60)),
        call('b', 'l1', DeviceCall.typeOutgoing, ago(30), duration: 90), // they called back
      ]);
      expect(p.callBacks, isEmpty);
      expect(p.answeredLeadIds, {'l1'});
    });

    test('a connected call BEFORE the unanswered one does not cancel the reminder', () {
      final p = plan([
        call('a', 'l1', DeviceCall.typeOutgoing, ago(60), duration: 90),
        call('b', 'l1', DeviceCall.typeMissed, ago(10)),
      ]);
      expect(p.callBacks.single.leadId, 'l1');
      expect(p.answeredLeadIds, isEmpty);
    });

    test('several unanswered calls to one lead give one reminder, about the latest', () {
      final p = plan([
        call('a', 'l1', DeviceCall.typeMissed, ago(90)),
        call('b', 'l1', DeviceCall.typeMissed, ago(30)),
      ]);
      expect(p.callBacks, hasLength(1));
      expect(p.callBacks.single.latest.callId, 'b');
      expect(p.callBacks.single.callIds, {'a', 'b'});
    });

    test('calls from before the reminder was turned on, and ones already handled, are ignored', () {
      final p = plan(
        [call('old', 'l1', DeviceCall.typeMissed, ago(300)), call('done', 'l2', DeviceCall.typeMissed, ago(30)), call('new', 'l3', DeviceCall.typeMissed, ago(20))],
        since: ago(120),
        handled: {'done'},
      );
      expect(p.callBacks.map((c) => c.leadId), ['l3']);
      expect(p.consideredCallIds, {'new'});
    });

    test('only the most recent leads are reminded in one go; the rest are left for next time', () {
      final p = plan([for (var i = 0; i < 5; i++) call('c$i', 'l$i', DeviceCall.typeMissed, ago(100 - i * 10))], maxLeads: 2);
      expect(p.callBacks.map((c) => c.leadId), ['l4', 'l3']);
      expect(p.consideredCallIds, {'c3', 'c4'});
    });
  });

  group('reminders after a sync', () {
    test('a missed call creates a call-back follow-up and a phone alert at its due time', () async {
      await turnOn();
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];

      final summary = await sync();

      expect(summary.callBacksScheduled, 1);
      final made = followUps.created.single;
      expect(made.leadId, 'lead-1');
      expect(made.notes, startsWith('Missed call at '));
      expect(made.notes, endsWith('Call back.'));
      // Half an hour after the call had passed already, so: a few minutes from now.
      expect(made.dueAt, now.add(CallSyncRepository.callBackMinimumLead));
      final alert = source.callBackAlerts['lead-1']!;
      expect(alert.title, 'Call back Suguna');
      expect(alert.triggerAtMillis, made.dueAt.millisecondsSinceEpoch);
    });

    test('a call that only just ended is reminded half an hour after it', () async {
      await turnOn();
      source.calls = [callRow(1, at: ago(2), type: DeviceCall.typeMissed, duration: 0)];

      await sync();

      expect(followUps.created.single.dueAt, ago(2).add(CallSyncRepository.callBackDelay));
    });

    test('rejected and not-answered calls say so in the follow-up note', () async {
      await turnOn();
      api.leads['9800000002'] = 'lead-2';
      source.calls = [
        callRow(1, at: ago(40), type: DeviceCall.typeRejected, duration: 0),
        callRow(2, number: '+919800000002', at: ago(30), type: DeviceCall.typeOutgoing, duration: 0),
      ];

      await sync();

      final notes = {for (final c in followUps.created) c.leadId: c.notes};
      expect(notes['lead-1'], startsWith('Declined call at '));
      expect(notes['lead-2'], startsWith('Call not answered at '));
    });

    test('nothing happens while the reminder is off', () async {
      await chooseSim();
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      final summary = await sync();
      expect(summary.callBacksScheduled, 0);
      expect(followUps.created, isEmpty);
    });

    test('calls from before it was turned on never get a reminder', () async {
      await turnOn(since: ago(10));
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      await sync();
      expect(followUps.created, isEmpty);
    });

    test('only calls to leads are considered: other numbers are never sent, so never reminded', () async {
      await turnOn();
      source.calls = [callRow(1, number: '+919999999999', at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      await sync();
      expect(followUps.created, isEmpty);
    });

    test('a call answered afterwards needs no reminder, and removes a waiting alert', () async {
      await turnOn();
      source.callBackAlerts['lead-1'] = (triggerAtMillis: 1, title: 'Call back Suguna', text: 'x');
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0), callRow(2, at: ago(20), duration: 120)];

      await sync();

      expect(followUps.created, isEmpty);
      expect(source.cancelledCallBacks, contains('lead-1'));
    });

    test('a lead who already has a pending follow-up is not given another or a second alert', () async {
      await turnOn();
      followUps.leadsWithPending.add('lead-1');
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];

      final summary = await sync();

      expect(summary.callBacksScheduled, 0);
      expect(source.callBackAlerts, isEmpty);
    });

    test('the same call never gets a second reminder, not even on Re-sync', () async {
      await turnOn();
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      await sync();
      await sync(fromStart: true);
      await sync();
      expect(followUps.created, hasLength(1));
    });

    test('a failed follow-up is tried again on the next sync and sync itself still succeeds', () async {
      await turnOn();
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      followUps.error = const CallSyncApiException('server_error', 500);

      final first = await sync();
      expect(first.callsSynced, 1);
      expect(first.callBacksScheduled, 0);

      followUps.error = null;
      expect((await sync(fromStart: true)).callBacksScheduled, 1);
    });

    test('turning it on starts from now; turning it off removes the phone alerts', () async {
      await chooseSim();
      await repo().setNeverAttendedReminder('user-1', 'ws-1', true);
      final progress = await repo().progress('user-1', 'ws-1');
      expect(progress.neverAttendedOn, isTrue);
      expect(progress.neverAttendedSince, now.millisecondsSinceEpoch);

      await repo().setNeverAttendedReminder('user-1', 'ws-1', false);
      expect((await repo().progress('user-1', 'ws-1')).neverAttendedOn, isFalse);
      expect(source.cancelledAllCallBacks, 1);
    });

    test('turning it on again while on keeps the original start', () async {
      await turnOn();
      await repo().setNeverAttendedReminder('user-1', 'ws-1', true);
      expect((await repo().progress('user-1', 'ws-1')).neverAttendedSince, enabledAt.millisecondsSinceEpoch);
    });

    test('the lead a tapped notification asked for is handed over once', () async {
      source.launchLead = 'lead-1';
      expect(await repo().takeLaunchLead(), 'lead-1');
      expect(await repo().takeLaunchLead(), isNull);
    });

    test('logs never contain phone numbers or lead names', () async {
      AppLogger.capture = true;
      addTearDown(() {
        AppLogger.capture = false;
        AppLogger.clearBuffer();
      });
      await turnOn();
      source.calls = [callRow(1, at: ago(40), type: DeviceCall.typeMissed, duration: 0)];
      followUps.error = Exception('boom');
      await sync();
      followUps.error = null;
      await sync(fromStart: true);

      final log = AppLogger.bufferedLines.join(' | ');
      expect(log, contains('call-back reminder'));
      expect(log, isNot(contains('9800000001')));
      expect(log, isNot(contains('Suguna')));
    });
  });

  group('the follow-up creator', () {
    test('creates a call follow-up through the existing service, unless one is pending', () async {
      final repository = FakeFollowUpRepository();
      final creator = ApiCallBackFollowUps(repository, () => 'token');
      final due = DateTime(2026, 10, 2, 16);

      final made = await creator.schedule(workspaceId: 'ws-1', leadId: 'l9', dueAt: due, notes: 'Missed call at 3:10 PM. Call back.');
      expect(made!.dueAt, due);
      expect(repository.lastCreateLeadId, 'l9');
      expect(repository.lastCreateDraft!.type, 'call');
      expect(repository.lastCreateDraft!.notes, 'Missed call at 3:10 PM. Call back.');

      repository
        ..lastCreateLeadId = null
        ..leadFollowUpsToReturn = [testFollowUp(status: 'pending')];
      expect(await creator.schedule(workspaceId: 'ws-1', leadId: 'l9', dueAt: due, notes: 'x'), isNull);
      expect(repository.lastCreateLeadId, isNull);
    });

    test('a completed or cancelled follow-up does not count as pending', () async {
      final repository = FakeFollowUpRepository()..leadFollowUpsToReturn = [testFollowUp(status: 'completed'), testFollowUp(id: 'b', status: 'cancelled')];
      final creator = ApiCallBackFollowUps(repository, () => 'token');
      expect(await creator.schedule(workspaceId: 'ws-1', leadId: 'l9', dueAt: DateTime(2026, 10, 2, 16), notes: 'x'), isNotNull);
    });

    test('without a signed-in session nothing is created', () async {
      final repository = FakeFollowUpRepository();
      final creator = ApiCallBackFollowUps(repository, () => null);
      await expectLater(
        creator.schedule(workspaceId: 'ws-1', leadId: 'l9', dueAt: DateTime(2026), notes: 'x'),
        throwsA(isA<CallSyncApiException>()),
      );
      expect(repository.lastCreateLeadId, isNull);
    });
  });

  group('Never Attended Call Reminder screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, {bool withSim = true}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (withSim) await chooseSim();
      final container = settingsContainer(
        simStorage: simStorage,
        simSource: simSource,
        callSyncSource: source,
        authRepo: signedInAuthRepository(),
        extraOverrides: [
          callSyncStorageProvider.overrideWithValue(storage),
          callSyncApiProvider.overrideWithValue(api),
          callBackFollowUpsProvider.overrideWithValue(followUps),
          callSyncControllerProvider.overrideWith(
            (ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', 'ws-1')..load(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: NeverAttendedScreen())));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('starts off, with a Remind Me switch', (tester) async {
      await pump(tester);
      expect(find.text('Remind Me'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('never-attended-switch'))).value, isFalse);
      expect(find.text('Turn this on to be reminded to call back leads you missed.'), findsOneWidget);
    });

    testWidgets('the info button explains what the reminder does', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('never-attended-info')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('never-attended-info-dialog')), findsOneWidget);
      expect(find.text(kNeverAttendedInfo), findsOneWidget);
    });

    testWidgets('turning Remind Me on saves it for this employee, starting from now', (tester) async {
      final container = await pump(tester);

      await tester.tap(find.byKey(const Key('never-attended-switch')));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(find.byKey(const Key('never-attended-switch'))).value, isTrue);
      expect(container.read(callSyncControllerProvider).neverAttendedOn, isTrue);
      expect(find.textContaining('adds a "call back" follow-up'), findsOneWidget);

      await tester.tap(find.byKey(const Key('never-attended-switch')));
      await tester.pumpAndSettle();
      expect(container.read(callSyncControllerProvider).neverAttendedOn, isFalse);
      expect(source.cancelledAllCallBacks, 1);
    });

    testWidgets('says sync has to be set up first when it is not', (tester) async {
      source.permission = 'notRequested';
      await pump(tester, withSim: false);
      expect(find.byKey(const Key('never-attended-needs-setup')), findsOneWidget);
    });

    testWidgets('no setup notice once call history is allowed and a SIM is chosen', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('never-attended-needs-setup')), findsNothing);
    });

    testWidgets('turning it on while Android blocks notifications asks, and warns if still blocked', (tester) async {
      source
        ..notificationsOn = false
        ..grantNotificationsOnRequest = false;
      await pump(tester);

      await tester.tap(find.byKey(const Key('never-attended-switch')));
      await tester.pumpAndSettle();

      expect(source.notificationRequests, 1);
      expect(find.byKey(const Key('never-attended-notifications-off')), findsOneWidget);
    });
  });
}
