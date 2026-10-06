import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/activity/domain/entities/activity_summary.dart';
import 'package:mobile/features/activity/presentation/controllers/activity_controller.dart';
import 'package:mobile/features/activity/presentation/providers/activity_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/workspace/domain/entities/workspace_state.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_activity_repository.dart';

const _interval = Duration(milliseconds: 40);

class _Harness {
  _Harness({required this.auth, required this.workspaces, required this.activity, required this.container});

  final FakeAuthRepository auth;
  final FakeWorkspaceRepository workspaces;
  final FakeActivityRepository activity;
  final ProviderContainer container;

  ActivityController get controller => container.read(activityControllerProvider.notifier);
}

_Harness _build({bool signedIn = true, int offset = 330}) {
  final auth = FakeAuthRepository();
  if (signedIn) auth.session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaces = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final activity = FakeActivityRepository();

  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
    workspaceRepositoryProvider.overrideWithValue(workspaces),
    activityRepositoryProvider.overrideWithValue(activity),
    activityControllerProvider.overrideWith((ref) => ActivityController(activity, ref, interval: _interval, utcOffsetMinutes: () => offset)),
  ]);
  addTearDown(() {
    container.dispose();
    auth.dispose();
  });
  return _Harness(auth: auth, workspaces: workspaces, activity: activity, container: container);
}

/// Boots the controller the way the app does, with the workspace resolved.
Future<_Harness> _signedInAndTracking() async {
  final h = _build();
  h.container.read(workspaceControllerProvider);
  await waitUntil(() => h.container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);
  h.container.read(activityControllerProvider);
  await waitUntil(() => h.activity.count('heartbeat') >= 1);
  return h;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('heartbeat loop', () {
    test('starts once a user is signed in with a workspace, sending the token, workspace and UTC offset', () async {
      final h = await _signedInAndTracking();

      final first = h.activity.of('heartbeat').first;
      expect(first.accessToken, 'token-1');
      expect(first.workspaceId, 'w1');
      expect(first.utcOffsetMinutes, 330);
      expect(h.controller.isTracking, isTrue);
    });

    test('keeps beating on the interval', () async {
      final h = await _signedInAndTracking();

      await waitUntil(() => h.activity.count('heartbeat') >= 3);
    });

    test('does nothing while signed out', () async {
      final h = _build(signedIn: false);
      h.container.read(workspaceControllerProvider);
      h.container.read(activityControllerProvider);

      await Future<void>.delayed(_interval * 3);

      expect(h.activity.calls, isEmpty);
      expect(h.controller.isTracking, isFalse);
    });

    test('adopts the on-break status the backend reports', () async {
      final h = _build();
      h.activity.heartbeatStatus = ActivityStatus(onBreak: true, breakStartedAt: DateTime.utc(2026, 9, 24, 8, 30));
      h.container.read(workspaceControllerProvider);
      await waitUntil(() => h.container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);

      h.container.read(activityControllerProvider);
      await waitUntil(() => h.container.read(activityControllerProvider).onBreak);

      expect(h.container.read(activityControllerProvider).breakStartedAt, DateTime.utc(2026, 9, 24, 8, 30));
    });

    test('a failed heartbeat is swallowed and the loop carries on', () async {
      final h = _build();
      h.activity.heartbeatError = const NetworkException('offline');
      h.container.read(workspaceControllerProvider);
      await waitUntil(() => h.container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);

      h.container.read(activityControllerProvider);
      await waitUntil(() => h.activity.count('heartbeat') >= 2);

      expect(h.controller.isTracking, isTrue);
      expect(h.container.read(activityControllerProvider).onBreak, isFalse);
    });
  });

  group('lifecycle', () {
    // The fake records a call synchronously when it is invoked, so these
    // compare counts with no await between (the 40ms timer cannot fire).
    test('beats immediately when the app is backgrounded and when it comes back', () async {
      final h = await _signedInAndTracking();
      final before = h.activity.count('heartbeat');

      h.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(h.activity.count('heartbeat'), before + 1);

      h.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(h.activity.count('heartbeat'), before + 2);
    });

    test('inactive and detached do not beat by themselves', () async {
      final h = await _signedInAndTracking();
      final before = h.activity.count('heartbeat');

      h.controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      h.controller.didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(h.activity.count('heartbeat'), before);
    });
  });

  group('signing out', () {
    test('stops beating and sends a best-effort sign-out with the last credentials', () async {
      final h = await _signedInAndTracking();

      await h.auth.signOut();
      await waitUntil(() => h.activity.count('signOut') == 1);

      final report = h.activity.of('signOut').single;
      expect(report.accessToken, 'token-1');
      expect(report.workspaceId, 'w1');
      expect(h.controller.isTracking, isFalse);

      final afterSignOut = h.activity.count('heartbeat');
      await Future<void>.delayed(_interval * 3);
      expect(h.activity.count('heartbeat'), afterSignOut);
    });

    test('resets the break status', () async {
      final h = _build();
      h.activity.heartbeatStatus = ActivityStatus(onBreak: true, breakStartedAt: DateTime.utc(2026, 9, 24, 8, 30));
      h.container.read(workspaceControllerProvider);
      await waitUntil(() => h.container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);
      h.container.read(activityControllerProvider);
      await waitUntil(() => h.container.read(activityControllerProvider).onBreak);

      await h.auth.signOut();
      await waitUntil(() => !h.container.read(activityControllerProvider).onBreak);
    });

    test('a failing sign-out report does not throw', () async {
      final h = await _signedInAndTracking();
      h.activity.signOutError = const NetworkException('offline');

      await h.auth.signOut();
      await waitUntil(() => h.activity.count('signOut') == 1);

      expect(h.controller.isTracking, isFalse);
    });
  });

  group('breaks', () {
    test('startBreak calls the backend and adopts the returned status', () async {
      final h = await _signedInAndTracking();

      await h.controller.startBreak();

      expect(h.activity.count('startBreak'), 1);
      expect(h.container.read(activityControllerProvider).onBreak, isTrue);
      expect(h.container.read(activityControllerProvider).breakStartedAt, DateTime.utc(2026, 9, 24, 8, 30));
    });

    test('endBreak clears the on-break status', () async {
      final h = await _signedInAndTracking();
      await h.controller.startBreak();

      await h.controller.endBreak();

      expect(h.activity.count('endBreak'), 1);
      expect(h.container.read(activityControllerProvider).onBreak, isFalse);
    });

    test('a failed startBreak throws and leaves the status alone', () async {
      final h = await _signedInAndTracking();
      h.activity.breakError = const NetworkException('offline');

      await expectLater(h.controller.startBreak(), throwsA(isA<NetworkException>()));

      expect(h.container.read(activityControllerProvider).onBreak, isFalse);
    });

    test('break actions send the device offset', () async {
      final h = _build(offset: -300);
      h.container.read(workspaceControllerProvider);
      await waitUntil(() => h.container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);
      h.container.read(activityControllerProvider);
      await waitUntil(() => h.activity.count('heartbeat') >= 1);

      await h.controller.startBreak();

      expect(h.activity.of('startBreak').single.utcOffsetMinutes, -300);
    });
  });

  group('activitySummaryProvider', () {
    test('asks for today by default and returns the backend totals', () async {
      final h = await _signedInAndTracking();

      final summary = await h.container.read(activitySummaryProvider.future);

      expect(summary.loginSeconds, 254);
      expect(h.activity.summaryCallCount, 1);
      expect(h.activity.lastUntil!.difference(h.activity.lastSince!), lessThanOrEqualTo(const Duration(hours: 25)));
    });

    test('is empty without a signed-in workspace', () async {
      final h = _build(signedIn: false);

      final summary = await h.container.read(activitySummaryProvider.future);

      expect(summary.loginSeconds, 0);
      expect(h.activity.summaryCallCount, 0);
    });
  });
}
