import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';
import 'package:mobile/features/settings/presentation/controllers/app_settings_controller.dart';

import 'settings_fakes.dart';

void main() {
  tearDown(() {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
  });

  group('AppSettingsController', () {
    test('loads the saved values', () async {
      final storage = FakeAppSettingsStorage(
        saved: const AppSettings(theme: ThemeChoice.dark, defaultScreen: DefaultScreen.customers).toJsonString(),
      );
      final controller = AppSettingsController(storage, FakeDeviceAuthenticator());
      expect(controller.state.loaded, isFalse);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.loaded, isTrue);
      expect(controller.state.theme, ThemeChoice.dark);
      expect(controller.state.defaultScreen, DefaultScreen.customers);
    });

    test('unreadable storage runs on defaults and still reports loaded', () async {
      final controller = AppSettingsController(FakeAppSettingsStorage(failRead: true), FakeDeviceAuthenticator());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.loaded, isTrue);
      expect(controller.state.theme, ThemeChoice.system);
    });

    test('a change is applied at once and saved', () async {
      final storage = FakeAppSettingsStorage();
      final controller = AppSettingsController(storage, FakeDeviceAuthenticator());
      await Future<void>.delayed(Duration.zero);

      await controller.setTheme(ThemeChoice.light);
      await controller.setDefaultScreen(DefaultScreen.allocations);
      await controller.setNoteDialogMode(NoteDialogMode.never);

      expect(controller.state.theme, ThemeChoice.light);
      final saved = AppSettings.fromJsonString(storage.saved);
      expect(saved.theme, ThemeChoice.light);
      expect(saved.defaultScreen, DefaultScreen.allocations);
      expect(saved.noteDialogMode, NoteDialogMode.never);
    });

    test('a failed save still applies the change for this run', () async {
      final controller = AppSettingsController(FakeAppSettingsStorage(failWrite: true), FakeDeviceAuthenticator());
      await Future<void>.delayed(Duration.zero);

      await controller.setTheme(ThemeChoice.dark);

      expect(controller.state.theme, ThemeChoice.dark);
    });

    test('a change made before the saved values finish loading is not overwritten', () async {
      final storage = FakeAppSettingsStorage(saved: const AppSettings(theme: ThemeChoice.dark).toJsonString());
      final controller = AppSettingsController(storage, FakeDeviceAuthenticator());

      await controller.setTheme(ThemeChoice.light); // the initial read is still in flight
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.theme, ThemeChoice.light);
      expect(controller.state.loaded, isTrue);
    });

    test('Enable Log switches the logger\'s capture buffer on and off', () async {
      final controller = AppSettingsController(FakeAppSettingsStorage(), FakeDeviceAuthenticator());
      await Future<void>.delayed(Duration.zero);
      expect(AppLogger.capture, isFalse);

      await controller.setLoggingEnabled(true);
      AppLogger.info('hello from the test');
      expect(AppLogger.capture, isTrue);
      expect(AppLogger.bufferedLines.single, contains('hello from the test'));

      await controller.setLoggingEnabled(false);
      AppLogger.info('not captured');
      expect(AppLogger.bufferedLines, hasLength(1));
    });

    test('a saved "log on" turns capture on at startup', () async {
      final storage = FakeAppSettingsStorage(saved: const AppSettings(loggingEnabled: true).toJsonString());
      AppSettingsController(storage, FakeDeviceAuthenticator());
      await Future<void>.delayed(Duration.zero);

      expect(AppLogger.capture, isTrue);
    });
  });

  group('App lock', () {
    test('turning it on needs the phone\'s confirmation, then sticks', () async {
      final authenticator = FakeDeviceAuthenticator();
      final storage = FakeAppSettingsStorage();
      final controller = AppSettingsController(storage, authenticator);
      await Future<void>.delayed(Duration.zero);

      final result = await controller.setAppLock(true);

      expect(result, AppLockChangeResult.changed);
      expect(controller.state.appLockEnabled, isTrue);
      expect(authenticator.reasons, hasLength(1));
      expect(AppSettings.fromJsonString(storage.saved).appLockEnabled, isTrue);
    });

    test('a phone with no screen lock cannot turn it on (would lock the member out)', () async {
      final controller = AppSettingsController(FakeAppSettingsStorage(), FakeDeviceAuthenticator(supported: false));
      await Future<void>.delayed(Duration.zero);

      expect(await controller.setAppLock(true), AppLockChangeResult.notSupported);
      expect(controller.state.appLockEnabled, isFalse);
    });

    test('cancelling the prompt leaves it unchanged', () async {
      final controller = AppSettingsController(FakeAppSettingsStorage(), FakeDeviceAuthenticator(succeeds: false));
      await Future<void>.delayed(Duration.zero);

      expect(await controller.setAppLock(true), AppLockChangeResult.notConfirmed);
      expect(controller.state.appLockEnabled, isFalse);
    });

    test('turning it off also needs confirmation', () async {
      final authenticator = FakeDeviceAuthenticator();
      final controller = AppSettingsController(
        FakeAppSettingsStorage(saved: const AppSettings(appLockEnabled: true).toJsonString()),
        authenticator,
      );
      await Future<void>.delayed(Duration.zero);

      authenticator.succeeds = false;
      expect(await controller.setAppLock(false), AppLockChangeResult.notConfirmed);
      expect(controller.state.appLockEnabled, isTrue);

      authenticator.succeeds = true;
      expect(await controller.setAppLock(false), AppLockChangeResult.changed);
      expect(controller.state.appLockEnabled, isFalse);
    });

    test('setting it to what it already is does not prompt', () async {
      final authenticator = FakeDeviceAuthenticator();
      final controller = AppSettingsController(FakeAppSettingsStorage(), authenticator);
      await Future<void>.delayed(Duration.zero);

      expect(await controller.setAppLock(false), AppLockChangeResult.changed);
      expect(authenticator.reasons, isEmpty);
    });
  });
}
