import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/setup/presentation/widgets/permission_gate.dart';

import '../call_sync/call_sync_fakes.dart';
import '../settings/settings_fakes.dart';
import '../sim/sim_fakes.dart';

void main() {
  late FakeCallLogSource source;
  late FakeSimPlatformSource sims;
  late FakeSimSelectionStorage simStorage;
  late FakeCallSyncApi api;
  late FakeCallSyncStorage storage;

  setUp(() {
    source = FakeCallLogSource(permission: 'notRequested')..notificationsOn = false;
    sims = FakeSimPlatformSource(permission: 'granted', sims: [simMap(1, slot: 0, carrier: 'Jio'), simMap(2, slot: 1, carrier: 'Airtel')]);
    simStorage = FakeSimSelectionStorage();
    api = FakeCallSyncApi();
    storage = FakeCallSyncStorage();
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = settingsContainer(
      simSource: sims,
      simStorage: simStorage,
      callSyncSource: source,
      authRepo: signedInAuthRepository(),
      extraOverrides: [
        callSyncStorageProvider.overrideWithValue(storage),
        callSyncApiProvider.overrideWithValue(api),
        callSyncControllerProvider.overrideWith((ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', 'ws-1')..load()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SetupScreen(key: Key('setup-screen')))),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('lists what must be allowed, with nothing done yet', (tester) async {
    final container = await pump(tester);

    expect(find.byKey(const Key('setup-title')), findsOneWidget);
    for (final key in const ['setup-phone', 'setup-folder', 'setup-notifications', 'setup-sim']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('setup-done')), findsNothing);
    expect(container.read(setupChecklistProvider).complete, isFalse);
    expect(find.text('0 of 4 done'), findsOneWidget);
  });

  testWidgets('each step is ticked as it is allowed, and the checklist completes', (tester) async {
    source.afterRequest = 'granted';
    source.grantNotificationsOnRequest = true;
    final container = await pump(tester);

    await tester.tap(find.descendant(of: find.byKey(const Key('setup-phone')), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).phone, isTrue);

    await tester.tap(find.descendant(of: find.byKey(const Key('setup-folder')), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).folder, isTrue);
    expect(find.textContaining('Call Recordings'), findsWidgets);

    await tester.tap(find.descendant(of: find.byKey(const Key('setup-notifications')), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).notifications, isTrue);

    expect(container.read(setupChecklistProvider).complete, isFalse); // no business SIM yet
    await tester.tap(find.byKey(const Key('setup-sim-2')));
    await tester.pumpAndSettle();
    // This SIM has no number saved yet: it is asked for before the SIM can be chosen.
    expect(find.byKey(const Key('setup-sim-number')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup-sim-number')), 'abc');
    await tester.tap(find.byKey(const Key('setup-sim-save')));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).sim, isFalse);
    await tester.enterText(find.byKey(const Key('setup-sim-number')), '9876543210');
    await tester.tap(find.byKey(const Key('setup-sim-save')));
    await tester.pumpAndSettle();
    final done = container.read(setupChecklistProvider);
    expect(done.sim, isTrue);
    expect(done.complete, isTrue);
  });

  testWidgets('a refused phone permission stays unticked', (tester) async {
    source.afterRequest = 'denied';
    final container = await pump(tester);

    await tester.tap(find.descendant(of: find.byKey(const Key('setup-phone')), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).phone, isFalse);
    expect(find.byKey(const Key('setup-phone')), findsOneWidget);
  });

  testWidgets('with one SIM it is picked for the member, who only gives its number', (tester) async {
    sims.sims = [simMap(1, slot: 0, carrier: 'Airtel')];
    source.permission = 'granted';
    final container = await pump(tester);

    expect(find.byKey(const Key('setup-sim-number')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup-sim-number')), '9876543210');
    await tester.tap(find.byKey(const Key('setup-sim-save')));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).sim, isTrue);
  });

  testWidgets('no SIM found offers to check again instead of a dead end', (tester) async {
    sims.sims = [];
    source.permission = 'granted';
    await pump(tester);
    expect(find.textContaining('No active SIM found'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('setup-sim')), matching: find.text('Check again')), findsOneWidget);
  });

  testWidgets('call log allowed but phone state not: the step stays open until both are allowed', (tester) async {
    source.permission = 'granted';
    sims.permission = 'notRequested';
    final container = await pump(tester);
    expect(container.read(setupChecklistProvider).phone, isFalse);

    await tester.tap(find.descendant(of: find.byKey(const Key('setup-phone')), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(container.read(setupChecklistProvider).phone, isTrue);
  });

  testWidgets('a phone without telephony is not blocked', (tester) async {
    source.permission = 'unavailable';
    final container = await pump(tester);
    expect(container.read(setupChecklistProvider).complete, isTrue);
  });
}
