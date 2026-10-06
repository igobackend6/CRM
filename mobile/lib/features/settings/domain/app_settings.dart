import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;

import '../../../core/router/route_paths.dart';

/// The tab the app opens on after sign-in (Settings > Default screen).
enum DefaultScreen {
  home('Home', RoutePaths.app),
  allocations('Allocations', RoutePaths.leads),
  customers('Customers', RoutePaths.customers);

  const DefaultScreen(this.label, this.path);

  final String label;
  final String path;
}

/// When the after-call pop-up asks for the call's result (Settings > Enable Note Dialog).
enum NoteDialogMode {
  always('All calls'),
  onlyForLeads('Only for leads'),
  never('Never');

  const NoteDialogMode(this.label);

  final String label;
}

/// Settings > Theme.
enum ThemeChoice {
  system('System theme', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  const ThemeChoice(this.label, this.mode);

  final String label;
  final ThemeMode mode;
}

/// Settings > Not Sync Notification: after how many hours without a successful call-history sync the
/// phone reminds the member. The options of the reference app's list.
const List<int> kNotSyncHourOptions = [2, 4, 6, 8, 10, 12];

const int kDefaultNotSyncHours = 2;

/// Per-device preferences. Stored on the phone only (never sent to the backend): they describe how
/// this device behaves, not anything about the workspace.
class AppSettings {
  const AppSettings({
    this.defaultScreen = DefaultScreen.home,
    this.noteDialogMode = NoteDialogMode.always,
    this.theme = ThemeChoice.system,
    this.loggingEnabled = false,
    this.appLockEnabled = false,
    this.notSyncHours = kDefaultNotSyncHours,
    this.loaded = false,
  });

  /// What the app uses until the saved values have been read.
  static const AppSettings defaults = AppSettings();

  final DefaultScreen defaultScreen;
  final NoteDialogMode noteDialogMode;
  final ThemeChoice theme;
  final bool loggingEnabled;
  final bool appLockEnabled;

  /// One of [kNotSyncHourOptions].
  final int notSyncHours;

  /// False until the saved values were read from storage; never itself stored. The app lock waits
  /// for it so a cold start can't skip the lock before the setting is known.
  final bool loaded;

  AppSettings copyWith({
    DefaultScreen? defaultScreen,
    NoteDialogMode? noteDialogMode,
    ThemeChoice? theme,
    bool? loggingEnabled,
    bool? appLockEnabled,
    int? notSyncHours,
    bool? loaded,
  }) {
    return AppSettings(
      defaultScreen: defaultScreen ?? this.defaultScreen,
      noteDialogMode: noteDialogMode ?? this.noteDialogMode,
      theme: theme ?? this.theme,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      notSyncHours: notSyncHours ?? this.notSyncHours,
      loaded: loaded ?? this.loaded,
    );
  }

  String toJsonString() => jsonEncode({
        'default_screen': defaultScreen.name,
        'note_dialog_mode': noteDialogMode.name,
        'theme': theme.name,
        'logging_enabled': loggingEnabled,
        'app_lock_enabled': appLockEnabled,
        'not_sync_hours': notSyncHours,
      });

  /// Tolerant on purpose: a missing, corrupt or older-version value falls back to the default for
  /// that field instead of throwing, so a bad save can never stop the app opening.
  factory AppSettings.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const AppSettings(loaded: true);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AppSettings(loaded: true);
      return AppSettings(
        defaultScreen: _byName(DefaultScreen.values, decoded['default_screen'], DefaultScreen.home),
        noteDialogMode: _byName(NoteDialogMode.values, decoded['note_dialog_mode'], NoteDialogMode.always),
        theme: _byName(ThemeChoice.values, decoded['theme'], ThemeChoice.system),
        loggingEnabled: decoded['logging_enabled'] == true,
        appLockEnabled: decoded['app_lock_enabled'] == true,
        notSyncHours: kNotSyncHourOptions.contains(decoded['not_sync_hours']) ? decoded['not_sync_hours'] as int : kDefaultNotSyncHours,
        loaded: true,
      );
    } catch (_) {
      return const AppSettings(loaded: true);
    }
  }

  static T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
