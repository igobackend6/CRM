import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/sim/domain/business_sim_selection.dart';
import 'package:mobile/features/sim/presentation/providers/sim_providers.dart';
import 'package:mobile/features/sim/presentation/screens/connected_sim_screen.dart';

import 'sim_fakes.dart';

String _savedSelection(int subscriptionId, {String carrier = 'Jio', int slot = 0, String profileId = 'user-1'}) => jsonEncode({
      'installId': 'abc123',
      'selections': {
        profileId: BusinessSimSelection(
          subscriptionId: subscriptionId,
          deviceInstallId: 'abc123',
          selectedAt: DateTime(2026, 9, 30),
          slotIndex: slot,
          carrierName: carrier,
        ).toJson(),
      },
    });

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeSimPlatformSource source,
  FakeSimSelectionStorage? storage,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: simOverrides(source: source, storage: storage ?? FakeSimSelectionStorage()));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ConnectedSimScreen())));
  if (settle) await tester.pumpAndSettle();
  return container;
}

Finder _inCard(int subscriptionId, String text) =>
    find.descendant(of: find.byKey(Key('sim-card-$subscriptionId')), matching: find.text(text));

void main() {
  final dual = [
    simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001'),
    simMap(2, slot: 1, carrier: 'Airtel', number: '+919800000002'),
  ];

  testWidgets('shows "Detecting SIM cards..." while reading', (tester) async {
    final source = FakeSimPlatformSource(sims: dual)..detectGate = Completer<void>();
    await _pump(tester, source: source, settle: false);
    await tester.pump();

    expect(find.text('Detecting SIM cards...'), findsOneWidget);

    source.detectGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Detecting SIM cards...'), findsNothing);
    expect(find.byKey(const Key('sim-card-1')), findsOneWidget);
  });

  testWidgets('dual SIM: lists both with carrier, slot and number, none selected yet', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(sims: dual));

    expect(find.text('Connected SIM'), findsOneWidget);
    expect(_inCard(1, 'SIM 1'), findsOneWidget);
    expect(_inCard(1, 'Jio'), findsOneWidget);
    expect(_inCard(1, 'Slot 1'), findsOneWidget);
    expect(_inCard(1, '+919800000001'), findsOneWidget);
    expect(_inCard(2, 'SIM 2'), findsOneWidget);
    expect(_inCard(2, 'Airtel'), findsOneWidget);
    expect(_inCard(2, 'Slot 2'), findsOneWidget);
    expect(find.text('Select'), findsNWidgets(2));
    expect(find.text('Selected'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('sim-selected-summary')), matching: find.text('None selected')), findsOneWidget);
    expect(find.byKey(const Key('sim-last-detected')), findsOneWidget);
    expect(find.textContaining('Today, '), findsOneWidget);
  });

  testWidgets('single SIM: shown and can be selected; the choice is saved', (tester) async {
    final storage = FakeSimSelectionStorage();
    final container = await _pump(
      tester,
      source: FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001')]),
      storage: storage,
    );

    expect(find.byKey(const Key('sim-card-1')), findsOneWidget);
    expect(find.byKey(const Key('sim-card-2')), findsNothing);

    await tester.tap(selectLabel(1));
    await tester.pumpAndSettle();

    expect(_inCard(1, 'Selected'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('sim-selected-summary')), matching: find.text('Jio • SIM 1 (+919800000001)')),
      findsOneWidget,
    );
    expect(storage.writes, 1);
    expect((await container.read(simRepositoryProvider).loadSelection('user-1'))!.subscriptionId, 1);
  });

  testWidgets('selecting the other SIM moves the selection — only one is ever selected', (tester) async {
    final storage = FakeSimSelectionStorage(saved: _savedSelection(1));
    await _pump(tester, source: FakeSimPlatformSource(sims: dual), storage: storage);
    expect(_inCard(1, 'Selected'), findsOneWidget);

    await tester.tap(selectLabel(2));
    await tester.pumpAndSettle();

    expect(_inCard(2, 'Selected'), findsOneWidget);
    expect(_inCard(1, 'Select'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    // The other SIM is still listed.
    expect(_inCard(1, 'Jio'), findsOneWidget);
  });

  testWidgets('switching SIM updates the value Settings shows once the save is done', (tester) async {
    final storage = FakeSimSelectionStorage(saved: _savedSelection(1), writeDelay: const Duration(milliseconds: 50));
    final container = await _pump(tester, source: FakeSimPlatformSource(sims: dual), storage: storage);
    final sub = container.listen(businessSimSelectionProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.pumpAndSettle();
    expect(container.read(businessSimSelectionProvider).valueOrNull?.subscriptionId, 1);

    await tester.tap(selectLabel(2));
    await tester.pumpAndSettle();

    expect(container.read(businessSimSelectionProvider).valueOrNull?.subscriptionId, 2);
  });

  testWidgets('a saved selection is shown when the screen opens again', (tester) async {
    final storage = FakeSimSelectionStorage(saved: _savedSelection(2, carrier: 'Airtel', slot: 1));
    await _pump(tester, source: FakeSimPlatformSource(sims: dual), storage: storage);

    expect(_inCard(2, 'Selected'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('sim-selected-summary')), matching: find.textContaining('Airtel • SIM 2')),
      findsOneWidget,
    );
  });

  testWidgets('another employee\'s choice on this phone is not shown as mine', (tester) async {
    final storage = FakeSimSelectionStorage(saved: _savedSelection(1, profileId: 'someone-else'));
    await _pump(tester, source: FakeSimPlatformSource(sims: dual), storage: storage);

    expect(find.text('Selected'), findsNothing);
  });

  testWidgets('missing details say "unavailable" instead of being invented', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(sims: [simMap(4, state: null)]));

    expect(_inCard(4, 'SIM'), findsOneWidget);
    expect(_inCard(4, 'Carrier unavailable'), findsOneWidget);
    expect(_inCard(4, 'Slot unavailable'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('sim-card-4')), matching: find.textContaining('Phone number unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sim-number-4')), findsOneWidget);
  });

  testWidgets('a SIM that needs its PIN is flagged', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'Jio', state: 'pinRequired')]));
    expect(_inCard(1, 'SIM PIN required'), findsOneWidget);
  });

  testWidgets('no SIM: says no active SIM was detected', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(sims: []));

    expect(find.text('No active SIM detected.'), findsOneWidget);
    expect(find.byKey(const Key('sim-refresh')), findsOneWidget);
  });

  testWidgets('permission not yet asked: explains why, then Allow detects the SIMs', (tester) async {
    final source = FakeSimPlatformSource(permission: 'notRequested', sims: dual);
    await _pump(tester, source: source);

    expect(find.text('Phone permission is required to detect SIM details.'), findsOneWidget);
    expect(find.textContaining('doesn\'t read your calls, messages or contacts'), findsOneWidget);
    expect(source.detectCalls, 0);

    await tester.tap(find.byKey(const Key('sim-allow-permission')));
    await tester.pumpAndSettle();

    expect(source.requestCalls, 1);
    expect(find.byKey(const Key('sim-card-1')), findsOneWidget);
    expect(find.byKey(const Key('sim-card-2')), findsOneWidget);
  });

  testWidgets('permission denied: stays on the explanation and can ask again — no crash', (tester) async {
    final source = FakeSimPlatformSource(permission: 'denied', afterRequest: 'denied');
    await _pump(tester, source: source);

    expect(find.byKey(const Key('sim-permission-required')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sim-allow-permission')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sim-permission-required')), findsOneWidget);
    expect(source.detectCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission permanently denied: offers Android app settings', (tester) async {
    final source = FakeSimPlatformSource(permission: 'notRequested', afterRequest: 'permanentlyDenied');
    await _pump(tester, source: source);

    await tester.tap(find.byKey(const Key('sim-allow-permission')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sim-permission-permanently-denied')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sim-open-settings')));
    await tester.pumpAndSettle();
    expect(source.openSettingsCalls, 1);
  });

  testWidgets('coming back from Android Settings with the permission allowed shows the SIMs', (tester) async {
    final source = FakeSimPlatformSource(permission: 'permanentlyDenied', sims: dual);
    await _pump(tester, source: source);
    expect(find.byKey(const Key('sim-permission-permanently-denied')), findsOneWidget);

    source.permission = 'granted';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sim-card-1')), findsOneWidget);
  });

  testWidgets('previously selected SIM removed: warns and requires a new choice', (tester) async {
    final storage = FakeSimSelectionStorage(saved: _savedSelection(9, carrier: 'Vi', slot: 1));
    await _pump(
      tester,
      source: FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001')]),
      storage: storage,
    );

    expect(find.text('Selected SIM unavailable'), findsOneWidget);
    expect(find.textContaining('previously selected SIM (Vi • SIM 2) is no longer available'), findsOneWidget);
    expect(find.text('Selected'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('sim-selected-summary')), matching: find.text('None selected')), findsOneWidget);

    await tester.tap(selectLabel(1));
    await tester.pumpAndSettle();

    expect(find.text('Selected SIM unavailable'), findsNothing);
    expect(_inCard(1, 'Selected'), findsOneWidget);
  });

  testWidgets('refresh re-reads the SIMs and keeps a selection that still exists', (tester) async {
    final source = FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'Jio')]);
    final storage = FakeSimSelectionStorage(saved: _savedSelection(1));
    await _pump(tester, source: source, storage: storage);
    final callsBefore = source.detectCalls;
    expect(find.byKey(const Key('sim-card-2')), findsNothing);

    source.sims = dual; // a second SIM was inserted
    await tester.tap(find.byKey(const Key('sim-refresh')));
    await tester.pumpAndSettle();

    expect(source.detectCalls, callsBefore + 1);
    expect(find.byKey(const Key('sim-card-2')), findsOneWidget);
    expect(_inCard(1, 'Selected'), findsOneWidget);
    expect(storage.writes, 0);
  });

  testWidgets('refresh after the selected SIM was taken out marks it unavailable', (tester) async {
    final source = FakeSimPlatformSource(sims: dual);
    await _pump(tester, source: source, storage: FakeSimSelectionStorage(saved: _savedSelection(1)));
    expect(find.text('Selected SIM unavailable'), findsNothing);

    source.sims = [dual[1]];
    await tester.tap(find.byKey(const Key('sim-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('Selected SIM unavailable'), findsOneWidget);
  });

  testWidgets('a read failure shows a friendly message with Retry, never the raw error', (tester) async {
    final source = FakeSimPlatformSource(sims: dual, detectError: PlatformException(code: 'read_failed', message: 'java.lang.NullPointerException'));
    await _pump(tester, source: source);

    expect(find.text('Unable to read SIM information.'), findsOneWidget);
    expect(find.textContaining('NullPointerException'), findsNothing);

    source.detectError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sim-card-1')), findsOneWidget);
  });

  testWidgets('a failed save rolls the choice back and says so', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(sims: dual), storage: FakeSimSelectionStorage(failWrite: true));

    await tester.tap(selectLabel(1));
    await tester.pumpAndSettle();

    expect(find.text('Selected'), findsNothing);
    expect(find.text('Couldn\'t save your SIM choice. Try again.'), findsOneWidget);
  });

  group('mobile number entry', () {
    final noNumbers = [simMap(1, slot: 0, carrier: 'Jio'), simMap(2, slot: 1, carrier: 'Airtel')];

    testWidgets('a number Android reported is prefilled; a missing one is left for the employee', (tester) async {
      await _pump(tester, source: FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'Jio', number: '8925829917'), noNumbers[1]]));

      expect(tester.widget<TextField>(find.byKey(const Key('sim-number-1'))).controller!.text, '8925829917');
      expect(tester.widget<TextField>(find.byKey(const Key('sim-number-2'))).controller!.text, isEmpty);
      expect(find.textContaining('Tap Submit to confirm'), findsOneWidget);
    });

    testWidgets('entering and submitting a number saves it (as +91...) on this phone', (tester) async {
      final storage = FakeSimSelectionStorage();
      final container = await _pump(tester, source: FakeSimPlatformSource(sims: noNumbers), storage: storage);

      await tester.enterText(find.byKey(const Key('sim-number-2')), '98765 43210');
      await tester.tap(find.byKey(const Key('sim-number-submit-2')));
      await tester.pumpAndSettle();

      expect(find.text('Mobile number saved for SIM 2.'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('sim-card-2')), matching: find.text('Saved')), findsOneWidget);
      expect(await container.read(simRepositoryProvider).loadNumbers('user-1'), {2: '+919876543210'});
    });

    testWidgets('an invalid or empty number is refused with a message under the field', (tester) async {
      final storage = FakeSimSelectionStorage();
      await _pump(tester, source: FakeSimPlatformSource(sims: noNumbers), storage: storage);

      await tester.tap(find.byKey(const Key('sim-number-submit-1')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the mobile number for this SIM.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('sim-number-1')), '12345');
      await tester.tap(find.byKey(const Key('sim-number-submit-1')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid 10-digit mobile number.'), findsOneWidget);
      expect(storage.writes, 0);
    });

    testWidgets('a SIM can only be selected for recording once its number is submitted', (tester) async {
      await _pump(tester, source: FakeSimPlatformSource(sims: noNumbers));

      await tester.tap(selectLabel(1));
      await tester.pumpAndSettle();
      expect(find.text('Enter and submit the mobile number for SIM 1 first.'), findsOneWidget);
      expect(find.text('Selected'), findsNothing);

      await tester.enterText(find.byKey(const Key('sim-number-1')), '8925829917');
      await tester.tap(find.byKey(const Key('sim-number-submit-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIM 1'));
      await tester.pumpAndSettle();

      expect(_inCard(1, 'Selected'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('sim-selected-summary')), matching: find.text('Jio • SIM 1 (+918925829917)')),
        findsOneWidget,
      );
    });

    testWidgets('submitted numbers are shown again when the screen reopens', (tester) async {
      final storage = FakeSimSelectionStorage(saved: '{"numbers": {"user-1": {"2": "+919876543210"}}}');
      await _pump(tester, source: FakeSimPlatformSource(sims: noNumbers), storage: storage);

      expect(tester.widget<TextField>(find.byKey(const Key('sim-number-2'))).controller!.text, '+919876543210');
      expect(find.descendant(of: find.byKey(const Key('sim-card-2')), matching: find.text('Saved')), findsOneWidget);
    });
  });

  testWidgets('a device without SIM support says so', (tester) async {
    await _pump(tester, source: FakeSimPlatformSource(permission: 'unavailable'));
    expect(find.byKey(const Key('sim-unavailable')), findsOneWidget);
  });
}
