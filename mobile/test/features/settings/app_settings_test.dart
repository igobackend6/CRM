import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/route_guard.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults keep today\'s behaviour (Home, pop-up on every call, system theme, nothing locked)', () {
      const s = AppSettings.defaults;
      expect(s.defaultScreen, DefaultScreen.home);
      expect(s.noteDialogMode, NoteDialogMode.always);
      expect(s.theme, ThemeChoice.system);
      expect(s.loggingEnabled, isFalse);
      expect(s.appLockEnabled, isFalse);
      expect(s.loaded, isFalse);
    });

    test('round-trips through JSON (the loaded flag is not stored)', () {
      const original = AppSettings(
        defaultScreen: DefaultScreen.customers,
        noteDialogMode: NoteDialogMode.onlyForLeads,
        theme: ThemeChoice.dark,
        loggingEnabled: true,
        appLockEnabled: true,
      );
      final restored = AppSettings.fromJsonString(original.toJsonString());

      expect(restored.defaultScreen, DefaultScreen.customers);
      expect(restored.noteDialogMode, NoteDialogMode.onlyForLeads);
      expect(restored.theme, ThemeChoice.dark);
      expect(restored.loggingEnabled, isTrue);
      expect(restored.appLockEnabled, isTrue);
      expect(restored.loaded, isTrue);
    });

    test('nothing saved yet -> defaults, but marked loaded', () {
      expect(AppSettings.fromJsonString(null).loaded, isTrue);
      expect(AppSettings.fromJsonString('').defaultScreen, DefaultScreen.home);
    });

    test('corrupt or unexpected JSON falls back to defaults instead of throwing', () {
      for (final bad in ['not json', '[]', '"text"', '{"default_screen": 5, "theme": null}']) {
        final s = AppSettings.fromJsonString(bad);
        expect(s.defaultScreen, DefaultScreen.home, reason: bad);
        expect(s.theme, ThemeChoice.system, reason: bad);
        expect(s.loaded, isTrue, reason: bad);
      }
    });

    test('an unknown value from a newer version only resets that field', () {
      final s = AppSettings.fromJsonString('{"default_screen":"calendar","theme":"dark"}');
      expect(s.defaultScreen, DefaultScreen.home);
      expect(s.theme, ThemeChoice.dark);
    });

    test('theme choices map to Flutter theme modes', () {
      expect(ThemeChoice.system.mode, ThemeMode.system);
      expect(ThemeChoice.light.mode, ThemeMode.light);
      expect(ThemeChoice.dark.mode, ThemeMode.dark);
    });
  });

  group('applyDefaultScreen', () {
    test('entering the app from outside lands on the chosen tab', () {
      expect(applyDefaultScreen(RoutePaths.app, DefaultScreen.allocations), RoutePaths.leads);
      expect(applyDefaultScreen(RoutePaths.app, DefaultScreen.customers), RoutePaths.customers);
      expect(applyDefaultScreen(RoutePaths.app, DefaultScreen.home), RoutePaths.app);
    });

    test('any other redirect, or no redirect, is left alone', () {
      expect(applyDefaultScreen(null, DefaultScreen.customers), isNull);
      expect(applyDefaultScreen(RoutePaths.login, DefaultScreen.customers), RoutePaths.login);
      expect(applyDefaultScreen(RoutePaths.workspace, DefaultScreen.allocations), RoutePaths.workspace);
    });
  });
}
