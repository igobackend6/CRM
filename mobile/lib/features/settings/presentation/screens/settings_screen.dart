import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../../call_sync/presentation/providers/call_sync_providers.dart';
import '../../../dialer/presentation/providers/native_dialer_providers.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../domain/app_settings.dart';
import '../providers/settings_providers.dart';
import '../widgets/settings_tile.dart';

/// Menu > Settings. The options of the reference app's settings list.
///
/// Working today: Connected SIM Details, Default screen, Enable Note Dialog, Sync Call History,
/// Not Sync Notification, Never Attended Call Reminder, Theme, Troubleshooting, App Security, Re-sync
/// Call Recordings, Change Call Recordings Location, Enable Log, Default Dialer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final controller = ref.read(appSettingsControllerProvider.notifier);
    final businessSim = ref.watch(businessSimSelectionProvider);
    final callSync = ref.watch(callSyncControllerProvider);
    final defaultDialer = ref.watch(defaultDialerControllerProvider);

    Future<void> resyncRecordings() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('Re-syncing the past 7 days of calls and recordings...')));
      final ok = await ref.read(callSyncControllerProvider.notifier).syncNow(fromStart: true);
      final after = ref.read(callSyncControllerProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Done. ${after.lastSummary?.recordingsUploaded ?? 0} recording(s) uploaded.'
                : 'Couldn\'t re-sync. Open Sync Call History to see what\'s needed.',
          ),
        ),
      );
    }

    Future<void> pickDefaultScreen() async {
      final picked = await showOptionSheet<DefaultScreen>(
        context,
        title: 'Default screen',
        options: DefaultScreen.values,
        selected: settings.defaultScreen,
        labelOf: (o) => o.label,
      );
      if (picked != null) await controller.setDefaultScreen(picked);
    }

    Future<void> pickNoteDialog() async {
      final picked = await showOptionSheet<NoteDialogMode>(
        context,
        title: 'Enable Note Dialog',
        options: NoteDialogMode.values,
        selected: settings.noteDialogMode,
        labelOf: (o) => o.label,
      );
      if (picked != null) await controller.setNoteDialogMode(picked);
    }

    Future<void> pickTheme() async {
      final picked = await showOptionSheet<ThemeChoice>(
        context,
        title: 'Theme',
        options: ThemeChoice.values,
        selected: settings.theme,
        labelOf: (o) => o.label,
      );
      if (picked != null) await controller.setTheme(picked);
    }

    return Scaffold(
      appBar: brandAppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SettingsTile(
            key: const Key('settings-connected-sim'),
            icon: Icons.sim_card_outlined,
            title: 'Connected SIM Details',
            value: businessSim.valueOrNull?.summary,
            onTap: () => context.push(RoutePaths.connectedSim),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-default-screen'),
            icon: Icons.home_outlined,
            title: 'Default screen',
            value: settings.defaultScreen.label,
            onTap: pickDefaultScreen,
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-note-dialog'),
            icon: Icons.rate_review_outlined,
            title: 'Enable Note Dialog',
            value: settings.noteDialogMode.label,
            onTap: pickNoteDialog,
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-call-sync'),
            icon: Icons.cloud_upload_outlined,
            title: 'Sync Call History',
            value: callSync.syncing ? 'Syncing...' : null,
            onTap: () => context.push(RoutePaths.callSync),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-not-sync'),
            icon: Icons.notifications_none,
            title: 'Not Sync Notification',
            value: '${settings.notSyncHours} hours',
            onTap: () => context.push(RoutePaths.notSync),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-never-attended'),
            icon: Icons.phone_callback_outlined,
            title: 'Never Attended Call Reminder',
            value: callSync.neverAttendedOn ? 'On' : 'Off',
            onTap: () => context.push(RoutePaths.neverAttended),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-theme'),
            icon: Icons.contrast,
            title: 'Theme',
            value: settings.theme.label,
            onTap: pickTheme,
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-default-dialer'),
            icon: Icons.dialpad,
            title: 'Default Dialer',
            value: defaultDialer.isDefault ? 'On' : 'Off',
            onTap: () => context.push(RoutePaths.defaultDialer),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-troubleshooting'),
            icon: Icons.build_circle_outlined,
            title: 'Troubleshooting',
            onTap: () => context.push(RoutePaths.troubleshooting),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-app-security'),
            icon: Icons.shield_outlined,
            title: 'App Security',
            value: settings.appLockEnabled ? 'On' : 'Off',
            onTap: () => context.push(RoutePaths.appSecurity),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-resync-recordings'),
            icon: Icons.sync,
            title: 'Re-sync Call Recordings',
            onTap: callSync.syncing ? null : resyncRecordings,
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-recordings-location'),
            icon: Icons.settings_phone_outlined,
            title: 'Change Call Recordings Location',
            value: callSync.folder?.name,
            onTap: callSync.syncing ? null : () => ref.read(callSyncControllerProvider.notifier).pickRecordingFolder(),
          ),
          const _Divider(),
          SettingsTile(
            key: const Key('settings-enable-log'),
            icon: Icons.description_outlined,
            title: 'Enable Log',
            trailing: Switch(
              value: settings.loggingEnabled,
              onChanged: (value) => controller.setLoggingEnabled(value),
            ),
            onTap: () => controller.setLoggingEnabled(!settings.loggingEnabled),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 16, endIndent: 16);
}
