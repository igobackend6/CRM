import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/domain/call_recording.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/screens/call_sync_screen.dart';
import 'package:mobile/features/call_sync/presentation/widgets/lead_recordings_section.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';
import 'package:mobile/features/workspace/domain/entities/workspace.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../sim/sim_fakes.dart';
import '../workspace/fake_workspace_repository.dart';
import 'call_sync_fakes.dart';

final _t0 = DateTime.now().subtract(const Duration(hours: 2));

Future<ProviderContainer> _container({
  required FakeCallLogSource source,
  FakeCallSyncApi? api,
  FakeSimSelectionStorage? simStorage,
  FakeRecordingPlayer? player,
  FakeRecordingDownloader? downloader,
  bool withWorkspace = true,
}) async {
  final workspaceRepo = FakeWorkspaceRepository()
    ..membershipsToReturn = [WorkspaceMembership(memberId: 'm-1', workspace: testWorkspace('ws-1', 'Igo'), roleName: 'team_mate')];
  final container = ProviderContainer(
    overrides: [
      ...simOverrides(source: FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'airtel')]), storage: simStorage ?? FakeSimSelectionStorage()),
      ...callSyncOverrides(source: source, api: api, player: player, downloader: downloader),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      callSyncControllerProvider.overrideWith(
        (ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', withWorkspace ? 'ws-1' : null)..load(),
      ),
    ],
  );
  if (withWorkspace) await container.read(workspaceControllerProvider.notifier).loadForUser('user-1');
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container, Widget child) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: child)));
  await tester.pumpAndSettle();
}

Future<FakeSimSelectionStorage> _withBusinessSim() async {
  final storage = FakeSimSelectionStorage();
  await SimRepository(FakeSimPlatformSource(), storage).select('user-1', const SimCard(subscriptionId: 1, slotIndex: 0, carrierName: 'airtel'));
  return storage;
}

void main() {
  group('Sync Call History screen', () {
    testWidgets('explains what is needed when nothing is set up', (tester) async {
      final container = await _container(source: FakeCallLogSource(permission: 'notRequested'));
      await _pump(tester, container, const CallSyncScreen());

      expect(find.text('Call history access'), findsOneWidget);
      expect(find.byKey(const Key('call-sync-allow')), findsOneWidget);
      expect(find.text('Choose the SIM whose calls are synced.'), findsOneWidget);
      expect(find.textContaining('Choose the folder where call recordings are saved'), findsOneWidget);
      expect(find.byKey(const Key('call-sync-recorder')), findsOneWidget);
      expect(find.byKey(const Key('call-sync-never')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('call-sync-now'))).onPressed, isNull);
    });

    testWidgets('allowing the permission syncs right away and shows the result', (tester) async {
      final source = FakeCallLogSource(permission: 'notRequested', calls: [callRow(1, at: _t0)]);
      final api = FakeCallSyncApi();
      final container = await _container(source: source, api: api, simStorage: await _withBusinessSim());
      await _pump(tester, container, const CallSyncScreen());

      await tester.tap(find.byKey(const Key('call-sync-allow')));
      await tester.pumpAndSettle();

      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('1 call to leads synced'), findsOneWidget);
      expect(api.storedCalls, 1);
    });

    testWidgets('permanently denied: points to Android settings', (tester) async {
      final container = await _container(source: FakeCallLogSource(permission: 'permanentlyDenied'));
      await _pump(tester, container, const CallSyncScreen());
      expect(find.byKey(const Key('call-sync-open-settings')), findsOneWidget);
      expect(find.textContaining('Permissions > Call logs'), findsOneWidget);
    });

    testWidgets('choosing the recordings folder shows it', (tester) async {
      final container = await _container(source: FakeCallLogSource(), simStorage: await _withBusinessSim());
      await _pump(tester, container, const CallSyncScreen());

      await tester.tap(find.byKey(const Key('call-sync-choose-folder')));
      await tester.pumpAndSettle();

      expect(find.text('Music/Recordings/Call Recordings'), findsOneWidget);
    });

    testWidgets('a server failure is explained and the calls stay for next time', (tester) async {
      final api = FakeCallSyncApi()..syncError = const CallSyncApiException('server_error', 500);
      final container = await _container(source: FakeCallLogSource(calls: [callRow(1, at: _t0)]), api: api, simStorage: await _withBusinessSim());
      await _pump(tester, container, const CallSyncScreen());

      await tester.tap(find.byKey(const Key('call-sync-now')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-sync-error')), findsOneWidget);
      expect(find.textContaining('try again automatically'), findsOneWidget);
    });

    testWidgets('Sync now without a business SIM says to choose one', (tester) async {
      final container = await _container(source: FakeCallLogSource());
      await _pump(tester, container, const CallSyncScreen());
      // Button disabled without a SIM; the controller also refuses.
      expect(await container.read(callSyncControllerProvider.notifier).syncNow(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Choose your business SIM first.'), findsOneWidget);
    });
  });

  group('automatic sync', () {
    test('runs once, then waits before running again', () async {
      final source = FakeCallLogSource(calls: [callRow(1, at: _t0)]);
      final container = await _container(source: source, simStorage: await _withBusinessSim());
      addTearDown(container.dispose);
      final controller = container.read(callSyncControllerProvider.notifier);

      await controller.autoSync();
      await controller.autoSync();

      expect(source.sinceAsked, hasLength(1));
    });

    test('does nothing before the permission is allowed (no prompt)', () async {
      final source = FakeCallLogSource(permission: 'notRequested', calls: [callRow(1, at: _t0)]);
      final container = await _container(source: source, simStorage: await _withBusinessSim());
      addTearDown(container.dispose);
      await container.read(callSyncControllerProvider.notifier).autoSync();
      expect(source.sinceAsked, isEmpty);
    });

    test('does nothing without a workspace', () async {
      final source = FakeCallLogSource(calls: [callRow(1, at: _t0)]);
      final container = await _container(source: source, withWorkspace: false);
      addTearDown(container.dispose);
      await container.read(callSyncControllerProvider.notifier).autoSync();
      expect(source.sinceAsked, isEmpty);
    });
  });

  group('lead recordings', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('lead_rec'));
    tearDown(() async => tmp.delete(recursive: true));

    CallRecording rec(String id, DateTime at, {String direction = 'outbound'}) =>
        CallRecording(id: id, callId: 'call-$id', callStartedAt: at, direction: direction, durationSeconds: 75, originalFileName: '$id.m4a');

    testWidgets('lists every recording from the first call and saves them to the phone', (tester) async {
      final api = FakeCallSyncApi()..recordings = [rec('a', _t0.subtract(const Duration(days: 3))), rec('b', _t0, direction: 'inbound')];
      final downloader = FakeRecordingDownloader();
      final container = await _container(source: FakeCallLogSource(localDir: tmp.path), api: api, downloader: downloader);
      await tester.runAsync(() async {
        await _pump(tester, container, const Scaffold(body: SingleChildScrollView(child: LeadRecordingsSection(leadId: 'lead-1'))));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Call 1 ·'), findsOneWidget);
      expect(find.textContaining('Call 2 ·'), findsOneWidget);
      expect(find.textContaining('Incoming · 1:15'), findsOneWidget);
      expect(downloader.downloaded, hasLength(2));
      expect(find.textContaining('Saved on phone'), findsNWidgets(2));
      expect(File('${tmp.path}/call-a.m4a').existsSync(), isTrue);
    });

    testWidgets('tapping play plays the local copy; tapping again pauses', (tester) async {
      final api = FakeCallSyncApi()..recordings = [rec('a', _t0)];
      final player = FakeRecordingPlayer();
      final container = await _container(source: FakeCallLogSource(localDir: tmp.path), api: api, player: player);
      await tester.runAsync(() async {
        await _pump(tester, container, const Scaffold(body: SingleChildScrollView(child: LeadRecordingsSection(leadId: 'lead-1'))));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        await tester.tap(find.byKey(const Key('lead-recording-play-a')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(player.played, ['${tmp.path}/call-a.m4a']);
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byKey(const Key('lead-recording-play-a')));
      await tester.pump();
      expect(player.pauses, 1);
    });

    testWidgets('no recordings yet', (tester) async {
      final container = await _container(source: FakeCallLogSource(localDir: tmp.path));
      await _pump(tester, container, const Scaffold(body: LeadRecordingsSection(leadId: 'lead-1')));
      expect(find.byKey(const Key('lead-recordings-empty')), findsOneWidget);
    });

    testWidgets('a load failure offers Retry', (tester) async {
      final api = FakeCallSyncApi()..recordingsError = const CallSyncApiException('server_error');
      final container = await _container(source: FakeCallLogSource(localDir: tmp.path), api: api);
      await _pump(tester, container, const Scaffold(body: LeadRecordingsSection(leadId: 'lead-1')));
      expect(find.byKey(const Key('lead-recordings-error')), findsOneWidget);
    });
  });
}
