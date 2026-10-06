import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';
import 'package:mobile/features/settings/presentation/providers/settings_providers.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/sim/domain/business_sim_selection.dart';
import 'package:mobile/features/sim/presentation/screens/connected_sim_screen.dart';

import '../auth/fake_auth_repository.dart';
import '../sim/sim_fakes.dart';
import 'settings_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  FakeAppSettingsStorage? storage,
  FakeAuthRepository? authRepo,
  FakeSimSelectionStorage? simStorage,
  FakeSimPlatformSource? simSource,
  bool realSimScreen = false,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = const Size(800, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = settingsContainer(
    storage: storage,
    authRepo: authRepo,
    simStorage: simStorage,
    simSource: simSource,
    extraOverrides: extraOverrides,
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: RoutePaths.settings,
    routes: [
      GoRoute(path: RoutePaths.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: RoutePaths.troubleshooting, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('TROUBLESHOOTING PAGE'))),
      GoRoute(path: RoutePaths.appSecurity, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('SECURITY PAGE'))),
      GoRoute(path: RoutePaths.defaultDialer, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('DEFAULT DIALER PAGE'))),
      GoRoute(path: RoutePaths.neverAttended, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('NEVER ATTENDED PAGE'))),
      GoRoute(path: RoutePaths.notSync, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('NOT SYNC PAGE'))),
      GoRoute(path: RoutePaths.callSync, builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('CALL SYNC PAGE'))),
      GoRoute(
        path: RoutePaths.connectedSim,
        builder: (_, _) => realSimScreen ? const ConnectedSimScreen() : Scaffold(appBar: AppBar(), body: const Text('SIM PAGE')),
      ),
    ],
  );
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  tearDown(() {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
  });

  testWidgets('lists every option from the reference settings list', (tester) async {
    await _pump(tester);

    for (final title in const [
      'Connected SIM Details',
      'Default screen',
      'Enable Note Dialog',
      'Sync Call History',
      'Not Sync Notification',
      'Never Attended Call Reminder',
      'Theme',
      'Default Dialer',
      'Troubleshooting',
      'App Security',
      'Re-sync Call Recordings',
      'Change Call Recordings Location',
      'Enable Log',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('every option is now real: nothing is marked Coming soon', (tester) async {
    await _pump(tester);
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('Default Dialer shows Off and opens its own screen', (tester) async {
    await _pump(tester);
    expect(find.descendant(of: find.byKey(const Key('settings-default-dialer')), matching: find.text('Off')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-default-dialer')));
    await tester.pumpAndSettle();

    expect(find.text('DEFAULT DIALER PAGE'), findsOneWidget);
  });

  testWidgets('Theme: choosing Dark applies and shows the new value', (tester) async {
    final container = await _pump(tester);
    expect(find.descendant(of: find.byKey(const Key('settings-theme')), matching: find.text('System theme')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsControllerProvider).theme, ThemeChoice.dark);
    expect(find.descendant(of: find.byKey(const Key('settings-theme')), matching: find.text('Dark')), findsOneWidget);
  });

  testWidgets('Default screen: choosing Customers is saved', (tester) async {
    final storage = FakeAppSettingsStorage();
    final container = await _pump(tester, storage: storage);

    await tester.tap(find.byKey(const Key('settings-default-screen')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsControllerProvider).defaultScreen, DefaultScreen.customers);
    expect(AppSettings.fromJsonString(storage.saved).defaultScreen, DefaultScreen.customers);
  });

  testWidgets('Enable Note Dialog: choosing Never is saved', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byKey(const Key('settings-note-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsControllerProvider).noteDialogMode, NoteDialogMode.never);
  });

  testWidgets('Enable Log: the switch turns the diagnostic log on', (tester) async {
    final container = await _pump(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsControllerProvider).loggingEnabled, isTrue);
    expect(AppLogger.capture, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('Troubleshooting and App Security open their own screens', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('settings-troubleshooting')));
    await tester.pumpAndSettle();
    expect(find.text('TROUBLESHOOTING PAGE'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-app-security')));
    await tester.pumpAndSettle();
    expect(find.text('SECURITY PAGE'), findsOneWidget);
  });

  testWidgets('Never Attended Call Reminder shows Off and opens its own screen', (tester) async {
    await _pump(tester);
    expect(find.descendant(of: find.byKey(const Key('settings-never-attended')), matching: find.text('Off')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-never-attended')));
    await tester.pumpAndSettle();

    expect(find.text('NEVER ATTENDED PAGE'), findsOneWidget);
  });

  testWidgets('Not Sync Notification shows its hours and opens its own screen', (tester) async {
    await _pump(tester, storage: FakeAppSettingsStorage(saved: const AppSettings(notSyncHours: 6).toJsonString()));
    expect(find.descendant(of: find.byKey(const Key('settings-not-sync')), matching: find.text('6 hours')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-not-sync')));
    await tester.pumpAndSettle();

    expect(find.text('NOT SYNC PAGE'), findsOneWidget);
  });

  testWidgets('Sync Call History opens its own screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('settings-call-sync')));
    await tester.pumpAndSettle();

    expect(find.text('CALL SYNC PAGE'), findsOneWidget);
  });

  testWidgets('Change Call Recordings Location picks a folder and shows it', (tester) async {
    await _pump(
      tester,
      extraOverrides: [
        callSyncControllerProvider.overrideWith(
          (ref) => CallSyncController(ref.watch(callSyncRepositoryProvider), 'user-1', 'ws-1')..load(),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('settings-recordings-location')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byKey(const Key('settings-recordings-location')), matching: find.text('Music/Recordings/Call Recordings')),
      findsOneWidget,
    );
  });

  testWidgets('Connected SIM Details opens its own screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('settings-connected-sim')));
    await tester.pumpAndSettle();

    expect(find.text('SIM PAGE'), findsOneWidget);
  });

  testWidgets('Connected SIM Details shows the business SIM chosen on this phone', (tester) async {
    final simStorage = FakeSimSelectionStorage(
      saved: jsonEncode({
        'installId': 'abc',
        'selections': {
          'user-1': BusinessSimSelection(subscriptionId: 2, deviceInstallId: 'abc', selectedAt: DateTime(2026, 10, 1), slotIndex: 1, carrierName: 'Airtel').toJson(),
        },
      }),
    );
    await _pump(tester, authRepo: signedInAuthRepository(), simStorage: simStorage);

    expect(find.descendant(of: find.byKey(const Key('settings-connected-sim')), matching: find.text('Airtel • SIM 2')), findsOneWidget);
  });

  testWidgets('switching the SIM on its screen updates the value back on Settings', (tester) async {
    final simStorage = FakeSimSelectionStorage(writeDelay: const Duration(milliseconds: 50));
    final simSource = FakeSimPlatformSource(sims: [
      simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001'),
      simMap(2, slot: 1, carrier: 'Airtel', number: '+919800000002'),
    ]);
    await _pump(tester, authRepo: signedInAuthRepository(), simStorage: simStorage, simSource: simSource, realSimScreen: true);

    await tester.tap(find.byKey(const Key('settings-connected-sim')));
    await tester.pumpAndSettle();
    await tester.tap(selectLabel(1));
    await tester.pumpAndSettle();
    await tester.tap(selectLabel(2));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byKey(const Key('settings-connected-sim')), matching: find.text('Airtel • SIM 2')), findsOneWidget);
  });

  testWidgets('App Security shows On once the lock is enabled', (tester) async {
    final storage = FakeAppSettingsStorage(saved: const AppSettings(appLockEnabled: true).toJsonString());
    await _pump(tester, storage: storage);

    expect(find.descendant(of: find.byKey(const Key('settings-app-security')), matching: find.text('On')), findsOneWidget);
  });
}
