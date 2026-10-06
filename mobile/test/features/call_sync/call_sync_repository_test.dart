import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/domain/call_recording.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';

import '../sim/sim_fakes.dart';
import 'call_sync_fakes.dart';

void main() {
  final now = DateTime(2026, 10, 1, 12);
  final t0 = DateTime(2026, 10, 1, 10);
  final weekAgo = now.subtract(CallSyncRepository.syncWindow).millisecondsSinceEpoch;

  late FakeCallLogSource source;
  late FakeCallSyncApi api;
  late FakeCallSyncStorage storage;
  late FakeSimPlatformSource simSource;
  late FakeSimSelectionStorage simStorage;
  late FakeRecordingDownloader downloader;
  late CallSyncRepository repo;
  late Directory tmp;

  Future<void> chooseSim(int subscriptionId) => SimRepository(simSource, simStorage).select(
        'user-1',
        SimCard(subscriptionId: subscriptionId, slotIndex: subscriptionId - 1, carrierName: 'airtel'),
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('call_sync_test');
    source = FakeCallLogSource(localDir: tmp.path);
    api = FakeCallSyncApi();
    storage = FakeCallSyncStorage();
    simSource = FakeSimPlatformSource(sims: [simMap(1, slot: 0), simMap(2, slot: 1)]);
    simStorage = FakeSimSelectionStorage();
    downloader = FakeRecordingDownloader();
    repo = CallSyncRepository(
      source: source,
      api: api,
      store: CallSyncStore(storage),
      sims: SimRepository(simSource, simStorage),
      downloader: downloader,
      clock: () => now,
    );
    await chooseSim(1);
  });

  tearDown(() async {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
    await tmp.delete(recursive: true);
  });

  Future<CallSyncProgress> progress() => repo.progress('user-1', 'ws-1');

  group('blocked', () {
    test('without a business SIM', () async {
      simStorage.saved = null;
      expect(
        () => repo.sync(profileId: 'user-1', workspaceId: 'ws-1'),
        throwsA(isA<CallSyncBlockedException>().having((e) => e.blocker, 'blocker', CallSyncBlocker.noBusinessSim)),
      );
    });

    test('without call-log permission (nothing is read)', () async {
      source.permission = 'denied';
      await expectLater(
        repo.sync(profileId: 'user-1', workspaceId: 'ws-1'),
        throwsA(isA<CallSyncBlockedException>().having((e) => e.blocker, 'blocker', CallSyncBlocker.permissionNeeded)),
      );
      expect(source.sinceAsked, isEmpty);
    });

    test('when the permission is revoked mid-way', () async {
      source.readCallLogError = PlatformException(code: 'permission_denied');
      expect(
        () => repo.sync(profileId: 'user-1', workspaceId: 'ws-1'),
        throwsA(isA<CallSyncBlockedException>().having((e) => e.blocker, 'blocker', CallSyncBlocker.permissionNeeded)),
      );
    });
  });

  group('call sync', () {
    test('sends only business-SIM calls; the server keeps only lead numbers', () async {
      source.calls = [
        callRow(1, at: t0, sub: 1), // lead, business SIM
        callRow(2, at: t0.add(const Duration(minutes: 5)), sub: 2), // other SIM: never sent
        callRow(3, number: '+919999999999', at: t0.add(const Duration(minutes: 10)), sub: 1), // not a lead
        callRow(4, number: null, at: t0.add(const Duration(minutes: 15)), sub: 1), // hidden number
      ];

      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');

      final sent = api.syncBatches.expand((b) => b).toList();
      expect(sent.map((e) => (e['key']! as String).split(':').last), ['1', '3']);
      expect(summary.callsRead, 3);
      expect(summary.callsSynced, 1);
      expect(summary.callsSkipped, 2);
      expect(api.storedCalls, 1);
    });

    test('remembers where it got to, and a second run only reads newer calls', () async {
      source.calls = [callRow(1, at: t0)];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect((await progress()).lastCallMillis, t0.millisecondsSinceEpoch);

      source.calls.add(callRow(2, at: t0.add(const Duration(hours: 1))));
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');

      expect(source.sinceAsked, [weekAgo, t0.millisecondsSinceEpoch]);
      expect(api.storedCalls, 2);
    });

    test('only the past 7 days are synced, however long ago the last sync was', () async {
      source.calls = [
        callRow(1, at: now.subtract(const Duration(days: 30))),
        callRow(2, at: now.subtract(const Duration(days: 8))),
        callRow(3, at: now.subtract(const Duration(days: 6))),
        callRow(4, at: t0),
      ];

      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');

      expect(source.sinceAsked.single, weekAgo);
      expect(api.syncBatches.expand((b) => b).map((e) => (e['key']! as String).split(':').last), ['3', '4']);
      expect(summary.callsSynced, 2);
    });

    test('after a long gap, a sync starts from a week ago — not from the last synced call', () async {
      source.calls = [callRow(1, at: now.subtract(const Duration(days: 20)))];
      // Pretend the last sync was 20 days ago.
      await CallSyncStore(storage).save(
        'user-1',
        'ws-1',
        CallSyncProgress(lastCallMillis: now.subtract(const Duration(days: 20)).millisecondsSinceEpoch),
      );
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(source.sinceAsked.single, weekAgo);
    });

    test('Re-sync reads the whole call log again without duplicating calls', () async {
      source.calls = [callRow(1, at: t0), callRow(2, at: t0.add(const Duration(minutes: 1)))];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1', fromStart: true);

      expect(source.sinceAsked.last, weekAgo);
      expect(api.storedCalls, 2);
    });

    test('on a single-SIM phone, calls Android could not tie to a SIM still count', () async {
      simSource.sims = [simMap(1, slot: 0)];
      source.calls = [callRow(1, at: t0, sub: null)];
      expect((await repo.sync(profileId: 'user-1', workspaceId: 'ws-1')).callsSynced, 1);
    });

    test('on a dual-SIM phone, a call with no SIM is not assumed to be business', () async {
      source.calls = [callRow(1, at: t0, sub: null)];
      expect((await repo.sync(profileId: 'user-1', workspaceId: 'ws-1')).callsRead, 0);
    });

    test('a server failure marks nothing as done, so the calls are retried', () async {
      source.calls = [callRow(1, at: t0)];
      api.syncError = const CallSyncApiException('server_error', 500);
      await expectLater(repo.sync(profileId: 'user-1', workspaceId: 'ws-1'), throwsA(isA<CallSyncApiException>()));
      expect((await progress()).lastCallMillis, 0);

      api.syncError = null;
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(api.storedCalls, 1);
    });

    test('every employee/workspace keeps its own progress', () async {
      source.calls = [callRow(1, at: t0)];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect((await repo.progress('user-1', 'ws-2')).lastCallMillis, 0);
    });

    test('logs counts only — never phone numbers', () async {
      AppLogger.capture = true;
      source.calls = [callRow(1, at: t0)];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(AppLogger.bufferedLines.join('\n'), isNot(contains('9800000001')));
    });
  });

  group('recordings', () {
    Future<void> setFolder() async {
      await repo.pickRecordingFolder('user-1', 'ws-1');
    }

    test('without a folder, connected calls wait for their recording', () async {
      source.calls = [callRow(1, at: t0, duration: 90), callRow(2, at: t0.add(const Duration(minutes: 5)), duration: 0)];
      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(summary.recordingsWaiting, 1); // the 0-second call has nothing to record
      expect(api.uploadedPaths, isEmpty);
    });

    test('uploads the matching file, registers it, and keeps a copy on the phone', () async {
      await setFolder();
      source.calls = [callRow(1, at: t0, duration: 90)];
      source.files = [fileRow('Call_rec.m4a', modified: t0.add(const Duration(seconds: 92)))];

      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');

      expect(summary.recordingsUploaded, 1);
      expect(summary.recordingsWaiting, 0);
      expect(api.completed, ['call-1']);
      expect(File('${tmp.path}/call-1.m4a').existsSync(), isTrue);
      expect((await progress()).uploaded, {'call-1'});
    });

    test('a recording that appears later is picked up on the next sync', () async {
      await setFolder();
      source.calls = [callRow(1, at: t0, duration: 90)];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(api.completed, isEmpty);

      source.files = [fileRow('late.m4a', modified: t0.add(const Duration(seconds: 95)))];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(api.completed, ['call-1']);
    });

    test('never uploads the same call twice', () async {
      await setFolder();
      source.calls = [callRow(1, at: t0, duration: 90)];
      source.files = [fileRow('a.m4a', modified: t0.add(const Duration(seconds: 92)))];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1', fromStart: true);
      expect(api.uploadedPaths, hasLength(1));
    });

    test('one already on the server (e.g. from a reinstall) is not uploaded again', () async {
      await setFolder();
      api.alreadyUploaded.add('call-1');
      source.calls = [callRow(1, at: t0, duration: 90)];
      source.files = [fileRow('a.m4a', modified: t0.add(const Duration(seconds: 92)))];
      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(api.uploadedPaths, isEmpty);
      expect(summary.recordingsWaiting, 0);
    });

    test('a failed upload stays pending, and the calls are still saved', () async {
      await setFolder();
      api.uploadError = const CallSyncApiException('upload_failed');
      source.calls = [callRow(1, at: t0, duration: 90)];
      source.files = [fileRow('a.m4a', modified: t0.add(const Duration(seconds: 92)))];

      final summary = await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');

      expect(summary.callsSynced, 1);
      expect(summary.recordingsWaiting, 1);
      expect((await progress()).lastCallMillis, t0.millisecondsSinceEpoch);
    });

    test('folder access lost: nothing is read from it', () async {
      await setFolder();
      source.folderAccess = false;
      source.calls = [callRow(1, at: t0, duration: 90)];
      source.files = [fileRow('a.m4a', modified: t0.add(const Duration(seconds: 92)))];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(source.filesRead, isEmpty);
    });

    test('a call that leaves the 7-day window without a recording stops waiting', () async {
      source.calls = [callRow(1, at: t0, duration: 90)];
      await repo.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect((await progress()).pending, hasLength(1));

      final later = CallSyncRepository(
        source: source,
        api: api,
        store: CallSyncStore(storage),
        sims: SimRepository(simSource, simStorage),
        downloader: downloader,
        clock: () => now.add(const Duration(days: 8)),
      );
      final summary = await later.sync(profileId: 'user-1', workspaceId: 'ws-1');
      expect(summary.recordingsWaiting, 0);
    });

    test('the chosen folder is remembered', () async {
      await setFolder();
      expect((await progress()).folder!.name, 'Music/Recordings/Call Recordings');
      expect(jsonDecode(storage.saved!), isA<Map<String, Object?>>());
    });
  });

  group('lead recordings on this phone', () {
    final recording = CallRecording(
      id: 'r1',
      callId: 'call-9',
      callStartedAt: t0,
      direction: 'outbound',
      originalFileName: 'Call.m4a',
    );

    test('downloads once into the app folder, then plays from there', () async {
      final first = await repo.localRecording('ws-1', recording);
      final second = await repo.localRecording('ws-1', recording);

      expect(first.path, '${tmp.path}/call-9.m4a');
      expect(second.existsSync(), isTrue);
      expect(api.urlCalls, 1);
      expect(downloader.downloaded, hasLength(1));
    });

    test('a failed download leaves no broken file behind', () async {
      downloader.fail = true;
      await expectLater(repo.localRecording('ws-1', recording), throwsException);
      expect(File('${tmp.path}/call-9.m4a').existsSync(), isFalse);
    });
  });
}
