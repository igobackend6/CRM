import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/call_sync/domain/call_recording.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/calls/presentation/screens/call_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../call_sync/call_sync_fakes.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

CallRecording _recording(String callId) => CallRecording(
      id: 'rec-$callId',
      callId: callId,
      callStartedAt: DateTime.utc(2026, 1, 1, 9),
      direction: 'outbound',
      durationSeconds: 47,
      originalFileName: 'r.wav',
    );

Future<void> _pump(
  WidgetTester tester, {
  required FakeCallRepository repository,
  FakeCallSyncApi? api,
  FakeRecordingPlayer? player,
  FakeRecordingDownloader? downloader,
  required Directory dir,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final router = GoRouter(initialLocation: '/', routes: [GoRoute(path: '/', builder: (context, state) => const CallListScreen())]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        callRepositoryProvider.overrideWithValue(repository),
        ...callSyncOverrides(
          source: FakeCallLogSource(localDir: dir.path),
          api: api,
          player: player,
          downloader: downloader,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('call_list_rec'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });

  FakeCallRepository calls() => FakeCallRepository()
    ..itemsToReturn = [
      testCall(id: 'in-ok', leadName: 'Answered In', direction: 'inbound', state: 'ENDED'),
      testCall(id: 'in-missed', leadName: 'Missed In', direction: 'inbound', state: 'MISSED'),
      testCall(id: 'in-rejected', leadName: 'Rejected In', direction: 'inbound', state: 'CANCELLED'),
      testCall(id: 'out-ok', leadName: 'Answered Out', direction: 'outbound', state: 'ENDED'),
      testCall(id: 'out-noanswer', leadName: 'No Pickup Out', direction: 'outbound', state: 'CANCELLED'),
    ]
    ..totalToReturn = 5;

  Future<void> choose(WidgetTester tester, CallFilter filter) async {
    final chip = find.byKey(Key('call-filter-${filter.name}'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('offers the Callyzer filter tabs, with All Calls first', (tester) async {
    await _pump(tester, repository: calls(), dir: dir);
    expect(find.text('Answered In'), findsOneWidget);
    for (final f in CallFilter.values) {
      expect(find.byKey(Key('call-filter-${f.name}')), findsOneWidget, reason: f.label);
    }
    // All five are listed under All Calls.
    expect(find.byType(CallTile), findsNWidgets(5));
  });

  testWidgets('Incoming, Outgoing, Missed, Rejected, Never Attended and Not Pickup by Client each show the right calls', (tester) async {
    await _pump(tester, repository: calls(), dir: dir);

    Future<void> expectOnly(CallFilter f, Set<String> names) async {
      await choose(tester, f);
      final shown = {
        for (final n in ['Answered In', 'Missed In', 'Rejected In', 'Answered Out', 'No Pickup Out'])
          if (find.text(n).evaluate().isNotEmpty) n,
      };
      expect(shown, names, reason: f.label);
    }

    await expectOnly(CallFilter.incoming, {'Answered In', 'Missed In', 'Rejected In'});
    await expectOnly(CallFilter.outgoing, {'Answered Out', 'No Pickup Out'});
    await expectOnly(CallFilter.missed, {'Missed In'});
    await expectOnly(CallFilter.rejected, {'Rejected In'});
    await expectOnly(CallFilter.neverAttended, {'Missed In', 'Rejected In'});
    await expectOnly(CallFilter.notPickedUp, {'No Pickup Out'});
    await expectOnly(CallFilter.all, {'Answered In', 'Missed In', 'Rejected In', 'Answered Out', 'No Pickup Out'});
  });

  testWidgets('a filter with nothing in it says so', (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'a', leadName: 'Only Answered', direction: 'inbound', state: 'ENDED')]
      ..totalToReturn = 1;
    await _pump(tester, repository: repo, dir: dir);

    await choose(tester, CallFilter.missed);

    expect(find.byKey(const Key('call-filter-empty')), findsOneWidget);
    expect(find.text('No missed yet.'), findsOneWidget);
  });

  testWidgets('only calls that have a recording show a play button', (tester) async {
    final api = FakeCallSyncApi()..recordingsByCallId = {'out-ok': _recording('out-ok')};
    await _pump(tester, repository: calls(), api: api, dir: dir);

    expect(find.byKey(const Key('call-recording-play-out-ok')), findsOneWidget);
    expect(find.byKey(const Key('call-recording-play-in-ok')), findsNothing);
  });

  testWidgets('tapping play downloads the recording to the phone and plays it; tapping again pauses', (tester) async {
    final api = FakeCallSyncApi()..recordingsByCallId = {'out-ok': _recording('out-ok')};
    final player = FakeRecordingPlayer();
    final downloader = FakeRecordingDownloader();
    await _pump(tester, repository: calls(), api: api, player: player, downloader: downloader, dir: dir);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('call-recording-play-out-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump();

    expect(downloader.downloaded, ['https://example.test/rec-out-ok']);
    expect(player.played, ['${dir.path}/out-ok.wav']);

    await tester.tap(find.byKey(const Key('call-recording-play-out-ok')));
    await tester.pump();
    expect(player.pauses, 1);
  });

  testWidgets('without a connection the list still works, just without play buttons', (tester) async {
    final api = FakeCallSyncApi()..recordingsError = Exception('offline');
    await _pump(tester, repository: calls(), api: api, dir: dir);
    expect(find.byType(CallTile), findsNWidgets(5));
    expect(find.byKey(const Key('call-recording-play-out-ok')), findsNothing);
  });
}
