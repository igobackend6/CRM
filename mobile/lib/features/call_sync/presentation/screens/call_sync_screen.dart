import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../../sim/domain/sim_permission_status.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../../sim/presentation/screens/connected_sim_screen.dart' show formatDetectedAt;
import '../../data/call_sync_repository.dart';
import '../controllers/call_sync_controller.dart';
import '../providers/call_sync_providers.dart';

/// Settings > Sync Call History: what's needed for sync, the recordings folder, and the last run.
class CallSyncScreen extends ConsumerStatefulWidget {
  const CallSyncScreen({super.key});

  @override
  ConsumerState<CallSyncScreen> createState() => _CallSyncScreenState();
}

class _CallSyncScreenState extends ConsumerState<CallSyncScreen> with WidgetsBindingObserver {
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
    // Back from Android Settings (permission) — re-check.
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (lifecycle == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      ref.read(callSyncControllerProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(callSyncControllerProvider);
    final controller = ref.read(callSyncControllerProvider.notifier);
    final sim = ref.watch(businessSimSelectionProvider).valueOrNull;
    final summary = state.lastSummary;
    final dim = theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim);

    final permissionOk = state.permission == SimPermissionStatus.granted;
    final canSync = permissionOk && sim != null && !state.syncing;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Sync Call History')),
      body: !state.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'Calls from the past 7 days on your business SIM to numbers that are leads in the CRM are '
                  'synced automatically and saved to each lead, with their recordings. Calls to other numbers '
                  'and older calls stay on your phone.',
                  style: dim,
                ),
                const SizedBox(height: AppSpacing.md),
                _StepCard(
                  key: const Key('call-sync-permission'),
                  icon: Icons.history,
                  title: 'Call history access',
                  done: permissionOk,
                  detail: switch (state.permission) {
                    SimPermissionStatus.granted => 'Allowed',
                    SimPermissionStatus.permanentlyDenied =>
                      'Turned off. Open app settings > Permissions > Call logs and allow it.',
                    SimPermissionStatus.unavailable => 'Not available on this device.',
                    _ => 'Needed to read your call history.',
                  },
                  action: permissionOk || state.permission == SimPermissionStatus.unavailable
                      ? null
                      : state.permission == SimPermissionStatus.permanentlyDenied
                          ? TextButton(
                              key: const Key('call-sync-open-settings'),
                              onPressed: () => ref.read(simRepositoryProvider).openAppSettings(),
                              child: const Text('Open settings'),
                            )
                          : FilledButton(
                              key: const Key('call-sync-allow'),
                              onPressed: controller.requestPermission,
                              child: const Text('Allow'),
                            ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StepCard(
                  key: const Key('call-sync-sim'),
                  icon: Icons.sim_card_outlined,
                  title: 'Business SIM',
                  done: sim != null,
                  detail: sim?.summary ?? 'Choose the SIM whose calls are synced.',
                  action: TextButton(
                    key: const Key('call-sync-choose-sim'),
                    onPressed: () => context.push(RoutePaths.connectedSim),
                    child: Text(sim == null ? 'Choose' : 'Change'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StepCard(
                  key: const Key('call-sync-folder'),
                  icon: Icons.folder_outlined,
                  title: 'Call recordings folder',
                  done: state.folder != null && state.folderAccessible,
                  detail: state.folder == null
                      ? 'Choose the folder where call recordings are saved: the CRM\'s own recorder (below) saves '
                          'into it, or pick the folder your phone\'s recorder uses.'
                      : !state.folderAccessible
                          ? '${state.folder!.name} — access lost. Choose the folder again.'
                          : state.recordCalls && state.recorder.supported && !state.recorder.folderWritable
                              ? '${state.folder!.name} — choose it again so the CRM can save recordings in it.'
                              : state.folder!.name,
                  action: TextButton(
                    key: const Key('call-sync-choose-folder'),
                    onPressed: state.syncing ? null : controller.pickRecordingFolder,
                    child: Text(state.folder == null ? 'Choose' : 'Change'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _RecorderCard(state: state, controller: controller),
                const SizedBox(height: AppSpacing.lg),
                Text('Last sync', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (summary == null)
                  Text('Not synced yet.', key: const Key('call-sync-never'), style: dim)
                else
                  Card(
                    key: const Key('call-sync-summary'),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatDetectedAt(context, summary.at, DateTime.now()), style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppSpacing.xs),
                          Text('${summary.callsSynced} ${summary.callsSynced == 1 ? 'call' : 'calls'} to leads synced'),
                          Text('${summary.callsSkipped} not leads (kept on phone only)', style: dim),
                          Text('${summary.recordingsUploaded} ${summary.recordingsUploaded == 1 ? 'recording' : 'recordings'} uploaded'),
                          if (summary.recordingsWaiting > 0)
                            Text('${summary.recordingsWaiting} waiting for their recording file', style: dim),
                        ],
                      ),
                    ),
                  ),
                if (state.blocker != null || state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    state.errorMessage ?? _blockerMessage(state.blocker!),
                    key: const Key('call-sync-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const Key('call-sync-now'),
                  onPressed: canSync ? () => controller.syncNow() : null,
                  icon: state.syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(state.syncing ? 'Syncing...' : 'Sync now'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  key: const Key('call-sync-resync'),
                  onPressed: canSync ? () => controller.syncNow(fromStart: true) : null,
                  child: const Text('Re-sync the past 7 days'),
                ),
              ],
            ),
    );
  }

  static String _blockerMessage(CallSyncBlocker blocker) => switch (blocker) {
        CallSyncBlocker.noBusinessSim => 'Choose your business SIM first.',
        CallSyncBlocker.permissionNeeded => 'Allow call history access first.',
        CallSyncBlocker.unavailable => 'Call history isn\'t available on this device.',
      };
}

class _StepCard extends StatelessWidget {
  const _StepCard({super.key, required this.icon, required this.title, required this.done, required this.detail, this.action});

  final IconData icon;
  final String title;
  final bool done;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Row(
          children: [
            Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(width: AppSpacing.xs),
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: done ? AppColors.success : AppColors.textDim),
          ],
        ),
        subtitle: Text(detail),
        trailing: action,
      ),
    );
  }
}

/// Settings > Sync Call History > Record calls: the CRM's own recorder and what it still needs.
class _RecorderCard extends StatelessWidget {
  const _RecorderCard({required this.state, required this.controller});

  final CallSyncState state;
  final CallSyncController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorder = state.recorder;
    final dim = theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim);
    final on = state.recordCalls;

    Widget need(String key, String text, String button, VoidCallback onPressed) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.error_outline, size: 18, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(text)),
              TextButton(key: Key(key), onPressed: onPressed, child: Text(button)),
            ],
          ),
        );

    return Card(
      key: const Key('call-sync-recorder'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic_none),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Record calls', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                Switch(
                  key: const Key('call-sync-record-switch'),
                  value: on,
                  onChanged: recorder.supported ? controller.setRecordCalls : null,
                ),
              ],
            ),
            Text(
              !recorder.supported
                  ? 'Call recording isn\'t available on this device.'
                  : on && recorder.ready
                      ? 'On. Business-SIM calls are recorded into the folder above and uploaded to the matching lead.'
                      : 'The CRM records your business-SIM calls with the microphone (clearest on speaker). '
                          'Set battery to "Unrestricted" for Sales CRM so Android doesn\'t stop it. '
                          'Let customers know calls may be recorded.',
              key: const Key('call-sync-recorder-detail'),
              style: dim,
            ),
            if (recorder.supported) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text('Auto speaker', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    key: const Key('call-sync-speaker-switch'),
                    value: state.recordOnSpeaker,
                    onChanged: controller.setRecordOnSpeaker,
                  ),
                ],
              ),
              Text(
                state.recordOnSpeaker
                    ? 'Recorded calls play on the loudspeaker so the customer\'s voice is captured as well as yours. '
                        'Android doesn\'t let apps record the other person directly. Keep the phone away from your ear.'
                    : 'Off: only your own voice is recorded clearly; the customer is barely audible unless you switch to '
                        'speaker yourself.',
                key: const Key('call-sync-speaker-detail'),
                style: dim,
              ),
            ],
            if (on && recorder.supported) ...[
              if (!recorder.microphone)
                recorder.microphonePermanentlyDenied
                    ? need('call-sync-mic-settings', 'Microphone is turned off for Sales CRM. Allow it in app settings.',
                        'Open', () => controller.openAppSettings())
                    : need('call-sync-mic', 'Allow the microphone.', 'Allow', controller.requestMicrophone),
              if (!recorder.accessibility) ...[
                need(
                  'call-sync-accessibility',
                  'Turn on "Sales CRM call recorder" in Accessibility (under Installed / Downloaded apps).',
                  'Open',
                  () => controller.openAccessibilitySettings(),
                ),
                // Android 13+ greys that switch out for apps installed from outside the Play Store.
                need(
                  'call-sync-restricted',
                  'Switch greyed out? In App info tap the ⋮ menu > "Allow restricted settings", then try again.',
                  'App info',
                  () => controller.openAppSettings(),
                ),
              ],
              if (state.folder == null)
                need('call-sync-recorder-folder', 'Choose the recordings folder.', 'Choose', controller.pickRecordingFolder)
              else if (!recorder.folderWritable)
                need('call-sync-recorder-folder', 'Choose the folder again to allow saving.', 'Choose', controller.pickRecordingFolder),
            ],
          ],
        ),
      ),
    );
  }
}
