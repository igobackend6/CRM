import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/domain/recorder_status.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/screens/call_sync_screen.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';

import '../sim/sim_fakes.dart';
import 'call_sync_fakes.dart';

void main() {
  late FakeCallLogSource source;
  late FakeSimSelectionStorage simStorage;
  late FakeCallSyncStorage storage;
  late CallSyncRepository repo;

  setUp(() async {
    source = FakeCallLogSource();
    simStorage = FakeSimSelectionStorage();
    storage = FakeCallSyncStorage();
    repo = CallSyncRepository(
      source: source,
      api: FakeCallSyncApi(),
      store: CallSyncStore(storage),
      sims: SimRepository(FakeSimPlatformSource(sims: [simMap(1, slot: 0)]), simStorage),
      downloader: FakeRecordingDownloader(),
    );
  });

  Future<void> chooseSim() =>
      SimRepository(FakeSimPlatformSource(), simStorage).select('user-1', const SimCard(subscriptionId: 1, slotIndex: 0, carrierName: 'airtel'));

  group('RecorderStatus', () {
    test('ready only when microphone, accessibility and a writable folder are all in place', () {
      expect(RecorderStatus.fromPlatform({'microphone': true, 'accessibility': true, 'folderWritable': true}).ready, isTrue);
      expect(RecorderStatus.fromPlatform({'microphone': true, 'accessibility': false, 'folderWritable': true}).ready, isFalse);
      expect(RecorderStatus.fromPlatform(null).supported, isFalse);
    });

    test('microphone refused for good is recognised', () {
      final s = RecorderStatus.fromPlatform({'microphone': false, 'microphoneAskedBefore': true, 'microphoneRationale': false});
      expect(s.microphonePermanentlyDenied, isTrue);
      expect(RecorderStatus.fromPlatform({'microphone': false, 'microphoneAskedBefore': false}).microphonePermanentlyDenied, isFalse);
    });
  });

  group('recorder configuration', () {
    test('records the business SIM into the chosen folder once turned on', () async {
      await chooseSim();
      await repo.pickRecordingFolder('user-1', 'ws-1');

      await repo.setRecordCalls('user-1', 'ws-1', true);

      expect(source.recorderConfigs.last, {'enabled': true, 'subscriptionId': 1, 'folderUri': 'content://tree/rec', 'speaker': true});
      expect((await repo.progress('user-1', 'ws-1')).recordCalls, isTrue);
    });

    test('stays off without a business SIM or a folder, even when turned on', () async {
      await repo.setRecordCalls('user-1', 'ws-1', true);
      expect(source.recorderConfigs.last['enabled'], isFalse);

      await chooseSim();
      await repo.applyRecorderConfig('user-1', 'ws-1');
      expect(source.recorderConfigs.last['enabled'], isFalse); // still no folder
    });

    test('Auto speaker is on by default, and the choice is passed to the recorder and kept', () async {
      await chooseSim();
      await repo.pickRecordingFolder('user-1', 'ws-1');
      expect((await repo.progress('user-1', 'ws-1')).recordOnSpeaker, isTrue);

      await repo.setRecordCalls('user-1', 'ws-1', true);
      expect(source.recorderConfigs.last['speaker'], isTrue);

      await repo.setRecordOnSpeaker('user-1', 'ws-1', false);
      expect(source.recorderConfigs.last['speaker'], isFalse);
      expect(source.recorderConfigs.last['enabled'], isTrue);
      expect((await repo.progress('user-1', 'ws-1')).recordOnSpeaker, isFalse);
    });

    test('a save from before the option existed still means Auto speaker on', () {
      final progress = CallSyncProgress.fromJson({'recordCalls': true});
      expect(progress.recordOnSpeaker, isTrue);
      expect(CallSyncProgress.fromJson({'recordOnSpeaker': false}).recordOnSpeaker, isFalse);
    });

    test('turning it off tells the recorder to stop', () async {
      await chooseSim();
      await repo.pickRecordingFolder('user-1', 'ws-1');
      await repo.setRecordCalls('user-1', 'ws-1', true);
      await repo.setRecordCalls('user-1', 'ws-1', false);
      expect(source.recorderConfigs.last['enabled'], isFalse);
    });
  });

  group('Record calls card', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          ...simOverrides(source: FakeSimPlatformSource(sims: [simMap(1, slot: 0)]), storage: simStorage),
          ...callSyncOverrides(source: source, storage: storage),
          callSyncControllerProvider.overrideWith((ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', 'ws-1')..load()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: CallSyncScreen())));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('turning on lists what is still needed, and Allow grants the microphone', (tester) async {
      await chooseSim();
      await pump(tester);

      await tester.tap(find.byKey(const Key('call-sync-record-switch')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-sync-mic')), findsOneWidget);
      expect(find.byKey(const Key('call-sync-accessibility')), findsOneWidget);
      expect(find.byKey(const Key('call-sync-restricted')), findsOneWidget);
      expect(find.byKey(const Key('call-sync-recorder-folder')), findsOneWidget);

      await tester.tap(find.byKey(const Key('call-sync-mic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-sync-mic')), findsNothing);

      await tester.tap(find.byKey(const Key('call-sync-accessibility')));
      await tester.pumpAndSettle();
      expect(source.accessibilityOpens, 1);
    });

    testWidgets('Auto speaker switch explains itself and changes the setting', (tester) async {
      await chooseSim();
      final container = await pump(tester);
      expect(tester.widget<Switch>(find.byKey(const Key('call-sync-speaker-switch'))).value, isTrue);
      expect(find.textContaining('captured as well as yours'), findsOneWidget);

      await tester.tap(find.byKey(const Key('call-sync-speaker-switch')));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byKey(const Key('call-sync-speaker-switch'))).value, isFalse);
      expect(container.read(callSyncControllerProvider).recordOnSpeaker, isFalse);
      expect(find.textContaining('only your own voice'), findsOneWidget);
    });

    testWidgets('when everything is in place it says it is on', (tester) async {
      await chooseSim();
      source.recorder = {'microphone': true, 'accessibility': true, 'folderWritable': true};
      await repo.pickRecordingFolder('user-1', 'ws-1');
      await repo.setRecordCalls('user-1', 'ws-1', true);
      await pump(tester);

      expect(find.textContaining('On. Business-SIM calls are recorded'), findsOneWidget);
      expect(find.byKey(const Key('call-sync-mic')), findsNothing);
      expect(find.byKey(const Key('call-sync-accessibility')), findsNothing);
    });
  });
}
