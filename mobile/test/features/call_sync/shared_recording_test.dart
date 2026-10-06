import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/domain/recording_match.dart';
import 'package:mobile/features/call_sync/domain/shared_audio.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/controllers/recording_import_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/screens/import_recording_screen.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';

import '../settings/settings_fakes.dart';
import '../sim/sim_fakes.dart';
import 'call_sync_fakes.dart';

/// Real file reads/writes happen off the test's fake clock, and each one needs a pump before the
/// next step continues: alternate real waiting and pumping until the work is done.
Future<void> _settleFileIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

PendingRecording _call(String id, DateTime at, int seconds, {String phone = '8925829917'}) =>
    PendingRecording(callId: id, startMillis: at.millisecondsSinceEpoch, durationSeconds: seconds, phoneKey: phone);

SharedAudio _audio(String path, {int seconds = 47, String name = 'Recording.m4a'}) =>
    SharedAudio(path: path, name: name, mimeType: 'audio/*', sizeBytes: 5, durationMillis: seconds * 1000);

void main() {
  final now = DateTime(2026, 10, 2, 18, 30);
  late Directory tmp;
  late FakeCallLogSource source;
  late FakeCallSyncApi api;
  late FakeCallSyncStorage storage;
  late File sharedFile;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shared_recording_test');
    source = FakeCallLogSource(localDir: '${tmp.path}/app')..sharedAudio = null;
    await Directory('${tmp.path}/app').create();
    api = FakeCallSyncApi();
    storage = FakeCallSyncStorage();
    sharedFile = await File('${tmp.path}/shared_1.m4a').writeAsBytes([1, 2, 3, 4, 5]);
  });

  tearDown(() async {
    // Windows can still be finishing a file write; a leftover temp folder is harmless.
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });

  CallSyncRepository repo() => CallSyncRepository(
        source: source,
        api: api,
        store: CallSyncStore(storage),
        sims: SimRepository(FakeSimPlatformSource(), FakeSimSelectionStorage()),
        downloader: FakeRecordingDownloader(),
        clock: () => now,
      );

  Future<void> waiting(List<PendingRecording> calls) =>
      CallSyncStore(storage).save('user-1', 'ws-1', CallSyncProgress(pending: calls));

  group('which call is the shared recording', () {
    test('the most recent call the recording fits comes first and is the likely one', () {
      final ranked = rankCandidates(
        [_call('a', now.subtract(const Duration(hours: 3)), 120), _call('b', now.subtract(const Duration(minutes: 20)), 50), _call('c', now.subtract(const Duration(hours: 1)), 31)],
        _audio('x', seconds: 47),
        now: now,
      );
      // 'c' (31 s) is shorter than the 47 s recording, so it cannot be the call.
      expect(ranked.map((c) => c.call.callId), ['b', 'a', 'c']);
      expect(ranked.first.likely, isTrue);
      expect(ranked.skip(1).any((c) => c.likely), isFalse);
      expect(ranked.first.differenceSeconds, 3);
    });

    test('a recording longer than every call is not guessed', () {
      final ranked = rankCandidates([_call('a', now, 20), _call('b', now, 30)], _audio('x', seconds: 47), now: now);
      expect(ranked.any((c) => c.likely), isFalse);
      expect(ranked, hasLength(2));
    });

    test('a recording shorter than its call (recording started late) goes to the latest call, not an old same-length one', () {
      final ranked = rankCandidates(
        [_call('old', now.subtract(const Duration(days: 2)), 35), _call('today', now.subtract(const Duration(minutes: 20)), 59)],
        _audio('x', seconds: 35),
        now: now,
      );
      expect(ranked.first.call.callId, 'today');
      expect(ranked.first.likely, isTrue);
    });

    test('Google Phone file names carry the call start time, and that picks the call exactly', () {
      final started = now.subtract(const Duration(minutes: 30));
      SharedAudio named(int millis) => SharedAudio(path: 'x', name: 'record-$millis.wav', mimeType: 'audio/wav', sizeBytes: 1, durationMillis: 36000);
      final audio = named(started.millisecondsSinceEpoch);
      expect(audio.recordedAt, started);
      // The 18:33-style call (41 s) is older than the call just made (36 s); the time decides, not length.
      final ranked = rankCandidates(
        [_call('earlier', started.subtract(const Duration(minutes: 20)), 41), _call('this', started.add(const Duration(seconds: 2)), 36)],
        audio,
        now: now,
      );
      expect(ranked.first.call.callId, 'this');
      expect(ranked.first.likely, isTrue);
    });

    test('when no waiting call started at the recorded time nothing is guessed', () {
      final started = now.subtract(const Duration(minutes: 5));
      final audio = SharedAudio(path: 'x', name: 'record-${started.millisecondsSinceEpoch}.wav', mimeType: 'audio/wav', sizeBytes: 1, durationMillis: 36000);
      final ranked = rankCandidates([_call('older', now.subtract(const Duration(minutes: 30)), 41)], audio, now: now);
      expect(ranked.any((c) => c.likely), isFalse);
    });

    test('nothing is pre-selected when the latest fitting call is old', () {
      final ranked = rankCandidates([_call('a', now.subtract(const Duration(days: 2)), 50)], _audio('x', seconds: 47), now: now);
      expect(ranked.first.likely, isFalse);
    });

    test('calls with no talk time are never offered, and an unknown length falls back to recency', () {
      final ranked = rankCandidates(
        [_call('old', now.subtract(const Duration(hours: 5)), 30), _call('none', now, 0), _call('new', now.subtract(const Duration(hours: 1)), 30)],
        const SharedAudio(path: 'x', name: 'x.m4a', mimeType: 'audio/mp4', sizeBytes: 1),
        now: now,
      );
      expect(ranked.map((c) => c.call.callId), ['new', 'old']);
      expect(ranked.any((c) => c.likely), isFalse);
    });

    test('mime types are taken from the file name, and a wildcard becomes a real type', () {
      expect(audioMimeFor('Recording.m4a', 'audio/*'), 'audio/mp4');
      expect(audioMimeFor('x.AMR', 'audio/x-thing'), 'audio/amr');
      expect(audioMimeFor('noext', 'audio/ogg'), 'audio/ogg');
      expect(audioMimeFor('noext', 'audio/*'), 'audio/mp4');
    });

    test('a shared file is read from what the phone sends, and junk is ignored', () {
      final audio = SharedAudio.fromPlatform({'path': '/c/x.m4a', 'name': 'r.m4a', 'mimeType': 'audio/mp4', 'size': 2048, 'durationMillis': 46500})!;
      expect(audio.durationSeconds, 47);
      expect(SharedAudio.fromPlatform({'name': 'x'}), isNull);
      expect(SharedAudio.fromPlatform(null), isNull);
    });
  });

  group('attaching a shared recording', () {
    test('uploads it for the chosen call, keeps a copy on the phone, and stops that call waiting', () async {
      await waiting([_call('call-1', now.subtract(const Duration(minutes: 20)), 50), _call('call-2', now.subtract(const Duration(hours: 4)), 90)]);

      await repo().attachSharedRecording(profileId: 'user-1', workspaceId: 'ws-1', callId: 'call-1', audio: _audio(sharedFile.path));

      expect(api.completed, ['call-1']);
      expect(File('${tmp.path}/app/call-1.m4a').existsSync(), isTrue);
      final progress = await CallSyncStore(storage).load('user-1', 'ws-1');
      expect(progress.pending.map((p) => p.callId), ['call-2']);
      expect(progress.uploaded, {'call-1'});
      expect(sharedFile.existsSync(), isFalse); // the cache copy is removed
    });

    test('a recording the server already has is not uploaded twice, but the call stops waiting', () async {
      await waiting([_call('call-1', now, 50)]);
      api.alreadyUploaded.add('call-1');

      await repo().attachSharedRecording(profileId: 'user-1', workspaceId: 'ws-1', callId: 'call-1', audio: _audio(sharedFile.path));

      expect(api.uploadedPaths, isEmpty);
      expect((await CallSyncStore(storage).load('user-1', 'ws-1')).pending, isEmpty);
    });

    test('a failed upload changes nothing, so it can be tried again', () async {
      await waiting([_call('call-1', now, 50)]);
      api.uploadError = const CallSyncApiException('upload_failed');

      await expectLater(
        repo().attachSharedRecording(profileId: 'user-1', workspaceId: 'ws-1', callId: 'call-1', audio: _audio(sharedFile.path)),
        throwsA(isA<CallSyncApiException>()),
      );

      expect((await CallSyncStore(storage).load('user-1', 'ws-1')).pending, hasLength(1));
      expect(sharedFile.existsSync(), isTrue);
      expect(File('${tmp.path}/app/call-1.m4a').existsSync(), isFalse);
    });

    test('what the phone hands over is returned once', () async {
      source.sharedAudio = {'path': sharedFile.path, 'name': 'r.m4a', 'mimeType': 'audio/mp4', 'size': 5, 'durationMillis': 47000};
      expect((await repo().takeSharedAudio())!.path, sharedFile.path);
      expect(await repo().takeSharedAudio(), isNull);
    });
  });

  group('Add call recording screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, SharedAudio audio, List<PendingRecording> calls) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await waiting(calls);
      final container = settingsContainer(
        simSource: FakeSimPlatformSource(),
        callSyncSource: source,
        authRepo: signedInAuthRepository(),
        extraOverrides: [
          callSyncStorageProvider.overrideWithValue(storage),
          callSyncApiProvider.overrideWithValue(api),
          callSyncControllerProvider.overrideWith((ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', 'ws-1')..load()),
          recordingImportControllerProvider.overrideWith((ref, audio) {
            final controller = RecordingImportController(
              ref.watch(callSyncRepositoryProvider),
              'user-1',
              'ws-1',
              audio,
              syncFirst: () async {},
            );
            controller.load();
            return controller;
          }),
          pendingSharedAudioProvider.overrideWith((ref) => audio),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ImportRecordingScreen())));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the recording and preselects the best-matching call', (tester) async {
      await pump(tester, _audio(sharedFile.path, seconds: 47), [_call('call-1', DateTime.now().subtract(const Duration(minutes: 20)), 50), _call('call-2', DateTime.now().subtract(const Duration(hours: 4)), 120)]);

      expect(find.text('Recording.m4a'), findsOneWidget);
      expect(find.text('Best match'), findsOneWidget);
      expect(find.textContaining('number ending 9917'), findsNWidgets(2));
      expect(tester.widget<FilledButton>(find.byKey(const Key('import-attach'))).onPressed, isNotNull);
    });

    testWidgets('Add recording uploads it and says it is done', (tester) async {
      await pump(tester, _audio(sharedFile.path), [_call('call-1', DateTime.now().subtract(const Duration(minutes: 20)), 50)]);

      await tester.tap(find.byKey(const Key('import-attach')));
      await _settleFileIo(tester);

      expect(api.completed, ['call-1']);
      expect(find.byKey(const Key('import-done')), findsOneWidget);
      expect(find.text('Recording added'), findsOneWidget);
    });

    testWidgets('with no obvious match nothing is preselected and the member chooses', (tester) async {
      await pump(tester, _audio(sharedFile.path, seconds: 400), [_call('call-1', DateTime.now(), 120), _call('call-2', DateTime.now().subtract(const Duration(hours: 2)), 300)]);

      expect(find.text('Best match'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import-attach'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('import-call-call-2')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('import-attach'))).onPressed, isNotNull);
    });

    testWidgets('when no call is waiting it explains what to check', (tester) async {
      await pump(tester, _audio(sharedFile.path), const []);
      expect(find.byKey(const Key('import-no-calls')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import-attach'))).onPressed, isNull);
    });

    testWidgets('a failed upload shows a friendly message and lets the member retry', (tester) async {
      await pump(tester, _audio(sharedFile.path), [_call('call-1', DateTime.now(), 50)]);
      api.uploadError = const CallSyncApiException('upload_failed');

      await tester.tap(find.byKey(const Key('import-attach')));
      await _settleFileIo(tester);

      expect(find.byKey(const Key('import-error')), findsOneWidget);
      expect(find.byKey(const Key('import-done')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import-attach'))).onPressed, isNotNull);
    });
  });
}
