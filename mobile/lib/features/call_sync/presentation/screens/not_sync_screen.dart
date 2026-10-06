import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../sim/domain/sim_permission_status.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../providers/call_sync_providers.dart';
import '../widgets/setup_notice.dart';

/// Settings > Not Sync Notification: after how many hours without a successful call-history sync the
/// phone reminds the member to open the app.
class NotSyncScreen extends ConsumerStatefulWidget {
  const NotSyncScreen({super.key});

  @override
  ConsumerState<NotSyncScreen> createState() => _NotSyncScreenState();
}

class _NotSyncScreenState extends ConsumerState<NotSyncScreen> with WidgetsBindingObserver {
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Back from Android's notification settings: look again.
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (lifecycle == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      ref.read(callSyncControllerProvider.notifier).refreshNotificationsAllowed();
    }
  }

  Future<void> _turnOnNotifications() async {
    final controller = ref.read(callSyncControllerProvider.notifier);
    await controller.requestNotifications();
    // Android shows its dialog once or twice; after that only the settings page can allow it.
    if (!ref.read(callSyncControllerProvider).notificationsAllowed) await controller.openNotificationSettings();
  }

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    final shown = await ref.read(callSyncControllerProvider.notifier).sendTestReminder();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          shown
              ? 'Test reminder sent. Pull down your notification bar to see it.'
              : 'Android didn\'t show it. Turn on notifications for Sales CRM first.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = ref.watch(appSettingsControllerProvider.select((s) => s.notSyncHours));
    final sync = ref.watch(callSyncControllerProvider);
    final sim = ref.watch(businessSimSelectionProvider).valueOrNull;
    final dim = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim);
    final syncSetUp = sync.permission == SimPermissionStatus.granted && sim != null;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Not Sync Notification')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.outline),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'App will notify you if call logs are not synced since selected time period.',
                    key: const Key('not-sync-info'),
                    style: dim,
                  ),
                ),
              ],
            ),
          ),
          if (!syncSetUp)
            SetupNotice(
              key: const Key('not-sync-needs-setup'),
              icon: Icons.sync_problem_outlined,
              text: 'Reminders start once Sync Call History is set up (call history access and a business SIM).',
              button: 'Set up',
              onPressed: () => context.push(RoutePaths.callSync),
            ),
          if (!sync.notificationsAllowed)
            SetupNotice(
              key: const Key('not-sync-notifications-off'),
              icon: Icons.notifications_off_outlined,
              text: 'Notifications are turned off for Sales CRM, so the reminder can\'t be shown.',
              button: 'Turn on',
              onPressed: _turnOnNotifications,
            ),
          const SizedBox(height: AppSpacing.sm),
          for (final option in kNotSyncHourOptions) ...[
            _HoursTile(
              key: Key('not-sync-option-$option'),
              hours: option,
              selected: option == hours,
              onTap: () => ref.read(appSettingsControllerProvider.notifier).setNotSyncHours(option),
            ),
            const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('not-sync-test'),
                onPressed: _sendTest,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send test reminder'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Call history syncs when you open Sales CRM. If it hasn\'t synced for the time you choose, '
              'you\'ll be reminded every ${hours == 1 ? 'hour' : '$hours hours'} until it does.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoursTile extends StatelessWidget {
  const _HoursTile({super.key, required this.hours, required this.selected, required this.onTap});

  final int hours;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text('$hours Hours', style: Theme.of(context).textTheme.titleMedium)),
              if (selected)
                Container(
                  key: const Key('not-sync-selected'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                )
              else
                const SizedBox(width: 32, height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
