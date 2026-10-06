import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/presentation/controllers/call_sync_controller.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/screens/not_sync_screen.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';
import 'package:mobile/features/settings/presentation/providers/settings_providers.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';

import '../settings/settings_fakes.dart';
import '../sim/sim_fakes.dart';
import 'call_sync_fakes.dart';

void main() {
  final now = DateTime(2026, 10, 2, 12);
  const hour = Duration(hours: 1);

  late FakeCallLogSource source;
  late FakeCallSyncApi api;
  late FakeCallSyncStorage storage;
  late FakeSimPlatformSource simSource;
  late FakeSimSelectionStorage simStorage;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('not_sync_test');
    source = FakeCallLogSource(localDir: tmp.path);
    api = FakeCallSyncApi();
    storage = FakeCallSyncStorage();
    simSource = FakeSimPlatformSource(sims: [simMap(1, slot: 0, carrier: 'airtel')]);
    simStorage = FakeSimSelectionStorage();
  });

  tearDown(() => tmp.delete(recursive: true));

  CallSyncRepository repo({DateTime? at}) => CallSyncRepository(
        source: source,
        api: api,
        store: CallSyncStore(storage),
        sims: SimRepository(simSource, simStorage),
        downloader: FakeRecordingDownloader(),
        clock: () => at ?? now,
      );

  Future<void> chooseSim() =>
      SimRepository(simSource, simStorage).select('user-1', const SimCard(subscriptionId: 1, slotIndex: 0, carrierName: 'airtel'));

  Future<void> markSyncedAt(DateTime at) => CallSyncStore(storage).save(
        'user-1',
        'ws-1',
        CallSyncProgress(lastSummary: CallSyncSummary(at: at)),
      );

  group('AppSettings.notSyncHours', () {
    test('defaults to 2 hours and survives a save', () {
      expect(const AppSettings().notSyncHours, 2);
      final saved = AppSettings.fromJsonString(const AppSettings(notSyncHours: 8).toJsonString());
      expect(saved.notSyncHours, 8);
    });

    test('an old save without it, or a value that is not an option, falls back to 2', () {
      expect(AppSettings.fromJsonString('{"theme":"dark"}').notSyncHours, 2);
      expect(AppSettings.fromJsonString('{"not_sync_hours": 5}').notSyncHours, 2);
      expect(AppSettings.fromJsonString('{"not_sync_hours": "6"}').notSyncHours, 2);
    });

    test('only the offered options can be chosen', () async {
      final container = settingsContainer(storage: FakeAppSettingsStorage());
      addTearDown(container.dispose);
      final controller = container.read(appSettingsControllerProvider.notifier);

      await controller.setNotSyncHours(6);
      expect(container.read(appSettingsControllerProvider).notSyncHours, 6);
      await controller.setNotSyncHours(5);
      expect(container.read(appSettingsControllerProvider).notSyncHours, 6);
      expect(kNotSyncHourOptions, [2, 4, 6, 8, 10, 12]);
    });
  });

  group('reminder alarm', () {
    test('is set for the last successful sync plus the chosen hours', () async {
      await chooseSim();
      await markSyncedAt(now.subtract(hour));

      await repo().updateNotSyncReminder('user-1', 'ws-1', 4);

      expect(source.reminders.single.hours, 4);
      expect(DateTime.fromMillisecondsSinceEpoch(source.reminders.single.triggerAtMillis), now.add(const Duration(hours: 3)));
    });

    test('before any sync it counts from now', () async {
      await chooseSim();
      await repo().updateNotSyncReminder('user-1', 'ws-1', 2);
      expect(DateTime.fromMillisecondsSinceEpoch(source.reminders.single.triggerAtMillis), now.add(const Duration(hours: 2)));
    });

    test('when the sync is already overdue, the next reminder is the next N-hour step, not the past', () async {
      await chooseSim();
      await markSyncedAt(now.subtract(const Duration(hours: 5))); // 2-hourly: due at -3, -1, then +1

      await repo().updateNotSyncReminder('user-1', 'ws-1', 2);

      expect(DateTime.fromMillisecondsSinceEpoch(source.reminders.single.triggerAtMillis), now.add(hour));
    });

    test('is removed until sync is set up: no business SIM, or no call-history permission', () async {
      await repo().updateNotSyncReminder('user-1', 'ws-1', 2);
      expect(source.reminders, isEmpty);
      expect(source.reminderCancels, 1);

      await chooseSim();
      source.permission = 'denied';
      await repo().updateNotSyncReminder('user-1', 'ws-1', 2);
      expect(source.reminders, isEmpty);
      expect(source.reminderCancels, 2);
    });

    test('a platform failure never breaks sync', () async {
      await chooseSim();
      source.reminderError = Exception('alarm service unavailable');
      await repo().updateNotSyncReminder('user-1', 'ws-1', 2);
      // No exception escaped.
    });

    test('a good sync pushes the reminder forward, a failed one leaves it counting from the last good sync', () async {
      await chooseSim();
      source.calls = [callRow(1, at: now.subtract(const Duration(minutes: 30)))];
      var clock = now;
      final controller = CallSyncController(
        CallSyncRepository(
          source: source,
          api: api,
          store: CallSyncStore(storage),
          sims: SimRepository(simSource, simStorage),
          downloader: FakeRecordingDownloader(),
          clock: () => clock,
        ),
        'user-1',
        'ws-1',
        notSyncHours: 6,
        clock: () => clock,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.syncNow(), isTrue);
      final afterGood = source.reminders.last;
      expect(DateTime.fromMillisecondsSinceEpoch(afterGood.triggerAtMillis), now.add(const Duration(hours: 6)));
      expect(afterGood.hours, 6);

      clock = now.add(const Duration(hours: 1));
      api.syncError = const CallSyncApiException('server_error', 500);
      source.calls = [callRow(2, at: clock.subtract(const Duration(minutes: 5)))];
      expect(await controller.syncNow(), isFalse);

      // Still counted from the last good sync (now), not from the failed attempt.
      expect(DateTime.fromMillisecondsSinceEpoch(source.reminders.last.triggerAtMillis), now.add(const Duration(hours: 6)));
    });
  });

  group('Not Sync Notification screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, {FakeAppSettingsStorage? settings, bool withSim = true}) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (withSim) await chooseSim();
      final container = settingsContainer(
        storage: settings,
        simStorage: simStorage,
        simSource: simSource,
        callSyncSource: source,
        authRepo: signedInAuthRepository(),
        extraOverrides: [
          callSyncStorageProvider.overrideWithValue(storage),
          callSyncApiProvider.overrideWithValue(api),
          // A signed-in employee in a selected workspace (the real provider needs both).
          callSyncControllerProvider.overrideWith(
            (ref) => CallSyncController(
              ref.watch(callSyncRepositoryProvider),
              'user-1',
              'ws-1',
              notSyncHours: ref.watch(appSettingsControllerProvider.select((s) => s.notSyncHours)),
            )..load(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: NotSyncScreen())));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('lists the six options, with 2 hours selected by default', (tester) async {
      await pump(tester);

      expect(find.text('App will notify you if call logs are not synced since selected time period.'), findsOneWidget);
      for (final h in [2, 4, 6, 8, 10, 12]) {
        expect(find.text('$h Hours'), findsOneWidget);
      }
      expect(find.byKey(const Key('not-sync-selected')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('not-sync-option-2')), matching: find.byKey(const Key('not-sync-selected'))), findsOneWidget);
    });

    testWidgets('choosing 6 hours selects it, saves it, and moves the reminder', (tester) async {
      final settings = FakeAppSettingsStorage();
      final container = await pump(tester, settings: settings);

      await tester.tap(find.byKey(const Key('not-sync-option-6')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byKey(const Key('not-sync-option-6')), matching: find.byKey(const Key('not-sync-selected'))), findsOneWidget);
      expect(find.byKey(const Key('not-sync-selected')), findsOneWidget); // only one is ever selected
      expect(AppSettings.fromJsonString(settings.saved).notSyncHours, 6);
      expect(container.read(appSettingsControllerProvider).notSyncHours, 6);
    });

    testWidgets('a saved choice is shown when the screen opens', (tester) async {
      await pump(tester, settings: FakeAppSettingsStorage(saved: const AppSettings(notSyncHours: 10).toJsonString()));
      expect(find.descendant(of: find.byKey(const Key('not-sync-option-10')), matching: find.byKey(const Key('not-sync-selected'))), findsOneWidget);
    });

    testWidgets('says reminders need sync set up when there is no business SIM / permission', (tester) async {
      source.permission = 'notRequested';
      await pump(tester, withSim: false);
      expect(find.byKey(const Key('not-sync-needs-setup')), findsOneWidget);
    });

    testWidgets('no setup notice once call history is allowed and a SIM is chosen', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('not-sync-needs-setup')), findsNothing);
    });

    testWidgets('when Android blocks notifications it says so; Turn on asks, then opens settings if still blocked', (tester) async {
      source
        ..notificationsOn = false
        ..grantNotificationsOnRequest = false;
      await pump(tester);
      expect(find.byKey(const Key('not-sync-notifications-off')), findsOneWidget);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(source.notificationRequests, 1);
      expect(source.notificationSettingsOpens, 1);
    });

    testWidgets('Send test reminder shows a notification now, and says so', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('not-sync-test')));
      await tester.pumpAndSettle();

      expect(source.testReminders, 1);
      expect(find.textContaining('Test reminder sent'), findsOneWidget);
    });

    testWidgets('Send test reminder explains when Android blocks it', (tester) async {
      source.notificationsOn = false;
      await pump(tester);

      await tester.tap(find.byKey(const Key('not-sync-test')));
      await tester.pumpAndSettle();

      expect(source.testReminders, 0);
      expect(find.textContaining('Android didn\'t show it'), findsOneWidget);
    });

    testWidgets('allowing notifications clears the notice', (tester) async {
      source.notificationsOn = false;
      await pump(tester);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('not-sync-notifications-off')), findsNothing);
      expect(source.notificationSettingsOpens, 0);
    });
  });
}
