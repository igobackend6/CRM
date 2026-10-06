import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/entities/auth_state.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';
import 'package:mobile/features/settings/presentation/widgets/app_lock_gate.dart';

import '../auth/fake_auth_repository.dart';
import 'settings_fakes.dart';

class _Harness {
  _Harness(this.container, this.authenticator, this.auth, this.clock);

  final ProviderContainer container;
  final FakeDeviceAuthenticator authenticator;
  final FakeAuthRepository auth;
  final _Clock clock;
}

class _Clock {
  DateTime now = DateTime(2026, 1, 1, 9);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool lockEnabled = true,
  bool signedIn = true,
  bool authSucceeds = false,
}) async {
  final auth = FakeAuthRepository();
  if (signedIn) auth.session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
  final authenticator = FakeDeviceAuthenticator(succeeds: authSucceeds);
  final container = settingsContainer(
    storage: FakeAppSettingsStorage(saved: AppSettings(appLockEnabled: lockEnabled).toJsonString()),
    authenticator: authenticator,
    authRepo: auth,
  );
  addTearDown(container.dispose);
  final clock = _Clock();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: AppLockGate(clock: () => clock.now, child: const Scaffold(body: Text('APP CONTENT')))),
    ),
  );
  await _settle(tester);
  return _Harness(container, authenticator, auth, clock);
}

Future<void> _leaveFor(WidgetTester tester, _Clock clock, Duration away) async {
  final binding = tester.binding;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  clock.now = clock.now.add(away);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _settle(tester);
}

void main() {
  group('shouldLockAfterAbsence', () {
    final t0 = DateTime(2026, 1, 1, 9);

    test('never left -> no lock', () => expect(shouldLockAfterAbsence(leftAt: null, now: t0), isFalse));

    test('a short trip away -> no lock', () {
      expect(shouldLockAfterAbsence(leftAt: t0, now: t0.add(const Duration(seconds: 59))), isFalse);
    });

    test('at or past the timeout -> lock', () {
      expect(shouldLockAfterAbsence(leftAt: t0, now: t0.add(kAppLockTimeout)), isTrue);
      expect(shouldLockAfterAbsence(leftAt: t0, now: t0.add(const Duration(hours: 2))), isTrue);
    });
  });

  group('AppLockGate', () {
    testWidgets('a session restored on start is locked behind the unlock screen', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);
      expect(find.text('Sales CRM is locked'), findsOneWidget);
    });

    testWidgets('the phone prompt opens by itself, and passing it reveals the app', (tester) async {
      final h = await _pump(tester, authSucceeds: true);

      expect(h.authenticator.reasons, ['Unlock Sales CRM']);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(find.text('APP CONTENT'), findsOneWidget);
    });

    testWidgets('failing the prompt keeps it locked; Unlock tries again', (tester) async {
      final h = await _pump(tester);
      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);

      h.authenticator.succeeds = true;
      await tester.tap(find.byKey(const Key('unlock-button')));
      await _settle(tester);

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
    });

    testWidgets('with App Security off nothing is ever locked', (tester) async {
      final h = await _pump(tester, lockEnabled: false);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);

      await _leaveFor(tester, h.clock, const Duration(hours: 1));

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(h.authenticator.reasons, isEmpty);
    });

    testWidgets('nobody signed in -> nothing to protect, no lock', (tester) async {
      await _pump(tester, signedIn: false);

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
    });

    testWidgets('a fresh sign-in does not lock (typing the password just proved who it is)', (tester) async {
      final h = await _pump(tester, signedIn: false);

      await h.container.read(authControllerProvider.notifier).signIn(phone: '+919876543210', password: 'pw');
      await _settle(tester);

      expect(h.container.read(authControllerProvider).status, AuthStatus.authenticated);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(h.authenticator.reasons, isEmpty);
    });

    testWidgets('coming back after a long absence locks again', (tester) async {
      final h = await _pump(tester, authSucceeds: true);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);

      h.authenticator.succeeds = false;
      await _leaveFor(tester, h.clock, const Duration(minutes: 5));

      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);
    });

    testWidgets('a quick trip to another app does not lock', (tester) async {
      final h = await _pump(tester, authSucceeds: true);
      h.authenticator.reasons.clear();

      await _leaveFor(tester, h.clock, const Duration(seconds: 20));

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(h.authenticator.reasons, isEmpty);
    });

    testWidgets('Sign out on the lock screen signs out and removes the lock', (tester) async {
      final h = await _pump(tester);

      await tester.tap(find.byKey(const Key('lock-sign-out')));
      await _settle(tester);

      expect(h.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
    });
  });
}
