import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/device_authenticator.dart';
import '../../data/settings_storage.dart';
import '../../domain/app_settings.dart';

/// Outcome of turning the App Security lock on or off.
enum AppLockChangeResult {
  changed,

  /// The phone has no screen lock / biometric set up, so there is nothing to unlock with. Turning the
  /// lock on would lock the member out of their own app.
  notSupported,

  /// The member cancelled, or failed, the confirmation prompt.
  notConfirmed,
}

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController(this._storage, this._authenticator) : super(AppSettings.defaults) {
    _load();
  }

  final AppSettingsStorage _storage;
  final DeviceAuthenticator _authenticator;

  /// Set once any change is made, so a slow initial read can't overwrite it.
  bool _touched = false;

  Future<void> _load() async {
    AppSettings loaded;
    try {
      loaded = AppSettings.fromJsonString(await _storage.read());
    } catch (e) {
      // Unreadable storage must never stop the app opening: run on the defaults.
      AppLogger.warning('Could not read app settings: $e');
      loaded = const AppSettings(loaded: true);
    }
    if (!mounted) return;
    if (_touched) {
      state = state.copyWith(loaded: true);
    } else {
      state = loaded;
    }
    _applySideEffects();
  }

  /// Settings that act outside the widget tree.
  void _applySideEffects() {
    AppLogger.capture = state.loggingEnabled;
  }

  Future<void> _update(AppSettings next) async {
    _touched = true;
    state = next;
    _applySideEffects();
    try {
      await _storage.write(next.toJsonString());
    } catch (e) {
      // The change still applies for this run; it just won't survive a restart.
      AppLogger.warning('Could not save app settings: $e');
    }
  }

  Future<void> setDefaultScreen(DefaultScreen value) => _update(state.copyWith(defaultScreen: value));

  Future<void> setNoteDialogMode(NoteDialogMode value) => _update(state.copyWith(noteDialogMode: value));

  Future<void> setTheme(ThemeChoice value) => _update(state.copyWith(theme: value));

  /// Settings > Not Sync Notification. Anything outside the offered options is ignored.
  Future<void> setNotSyncHours(int hours) {
    if (!kNotSyncHourOptions.contains(hours)) return Future.value();
    return _update(state.copyWith(notSyncHours: hours));
  }

  Future<void> setLoggingEnabled(bool value) => _update(state.copyWith(loggingEnabled: value));

  /// Turning the lock on or off both need the phone's own confirmation, so nobody holding an
  /// unlocked phone can quietly switch it off.
  Future<AppLockChangeResult> setAppLock(bool enabled) async {
    if (enabled == state.appLockEnabled) return AppLockChangeResult.changed;
    if (!await _authenticator.isSupported()) return AppLockChangeResult.notSupported;
    final confirmed = await _authenticator.authenticate(
      enabled ? 'Confirm it\'s you to turn on app lock' : 'Confirm it\'s you to turn off app lock',
    );
    if (!confirmed) return AppLockChangeResult.notConfirmed;
    await _update(state.copyWith(appLockEnabled: enabled));
    return AppLockChangeResult.changed;
  }
}
