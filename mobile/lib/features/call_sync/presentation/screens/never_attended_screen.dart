import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../../sim/domain/sim_permission_status.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../providers/call_sync_providers.dart';
import '../widgets/setup_notice.dart';

/// What the info button explains.
const kNeverAttendedInfo =
    'If a call is missed, rejected, or never attended, a reminder will be automatically scheduled, so you never forget to follow up.';

/// Settings > Never Attended Call Reminder: turns on automatic "call back" reminders for calls to
/// leads that went unanswered.
class NeverAttendedScreen extends ConsumerStatefulWidget {
  const NeverAttendedScreen({super.key});

  @override
  ConsumerState<NeverAttendedScreen> createState() => _NeverAttendedScreenState();
}

class _NeverAttendedScreenState extends ConsumerState<NeverAttendedScreen> with WidgetsBindingObserver {
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

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('never-attended-info-dialog'),
        content: const Text(kNeverAttendedInfo, textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _turnOnNotifications() async {
    final controller = ref.read(callSyncControllerProvider.notifier);
    await controller.requestNotifications();
    if (!ref.read(callSyncControllerProvider).notificationsAllowed) await controller.openNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.watch(callSyncControllerProvider);
    final controller = ref.read(callSyncControllerProvider.notifier);
    final sim = ref.watch(businessSimSelectionProvider).valueOrNull;
    final syncSetUp = sync.permission == SimPermissionStatus.granted && sim != null;
    final on = sync.neverAttendedOn;

    return Scaffold(
      appBar: brandAppBar(
        // Long title beside the info button: shrink to fit rather than cut it off with "...".
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Never Attended Call Reminder')),
        actions: [
          IconButton(key: const Key('never-attended-info'), icon: const Icon(Icons.info_outline), tooltip: 'About this reminder', onPressed: _showInfo),
        ],
      ),
      body: ListView(
        children: [
          if (!syncSetUp)
            SetupNotice(
              key: const Key('never-attended-needs-setup'),
              icon: Icons.sync_problem_outlined,
              text: 'Reminders need Sync Call History set up first (call history access and a business SIM).',
              button: 'Set up',
              onPressed: () => context.push(RoutePaths.callSync),
            ),
          if (on && !sync.notificationsAllowed)
            SetupNotice(
              key: const Key('never-attended-notifications-off'),
              icon: Icons.notifications_off_outlined,
              text: 'Notifications are turned off for Sales CRM, so the reminder can\'t be shown.',
              button: 'Turn on',
              onPressed: _turnOnNotifications,
            ),
          SwitchListTile(
            key: const Key('never-attended-switch'),
            title: Text('Remind Me', style: theme.textTheme.titleMedium),
            value: on,
            onChanged: controller.setNeverAttendedReminder,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          ),
          const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              on
                  ? 'When you miss a lead\'s call, decline it, or call and they don\'t pick up, Sales CRM adds a "call back" '
                      'follow-up for that lead and reminds you on this phone about 30 minutes later. Calls from before you '
                      'turned this on are ignored, and a lead who already has a pending follow-up isn\'t given another.'
                  : 'Turn this on to be reminded to call back leads you missed.',
              key: const Key('never-attended-detail'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
