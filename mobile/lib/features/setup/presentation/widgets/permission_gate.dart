import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../call_sync/presentation/providers/call_sync_providers.dart';
import '../../../sim/domain/sim_card.dart';
import '../../../sim/domain/sim_permission_status.dart';
import '../../../sim/presentation/controllers/connected_sim_controller.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';

/// What the phone must allow before the CRM can be used: the call log (so calls reach the leads),
/// notifications (reminders), the folder the phone saves call recordings in, and which SIM is the
/// business SIM. [phoneAvailable] is false on a device without telephony, where nothing is required.
class SetupChecklist {
  const SetupChecklist({
    required this.loaded,
    required this.phoneAvailable,
    required this.phone,
    required this.notifications,
    required this.folder,
    required this.sim,
  });

  final bool loaded;
  final bool phoneAvailable;
  final bool phone;
  final bool notifications;
  final bool folder;
  final bool sim;

  bool get complete => !phoneAvailable || (phone && notifications && folder && sim);

  int get done => [phone, notifications, folder, sim].where((d) => d).length;
}

final setupChecklistProvider = Provider<SetupChecklist>((ref) {
  final sync = ref.watch(callSyncControllerProvider);
  final sim = ref.watch(connectedSimControllerProvider);
  final phoneAvailable = sync.permission != SimPermissionStatus.unavailable;
  return SetupChecklist(
    loaded: sync.loaded,
    phoneAvailable: phoneAvailable,
    // Two Android permissions: the call log (sync) and phone state (to see which SIM is which).
    phone: sync.permission == SimPermissionStatus.granted &&
        sim.status != ConnectedSimStatus.permissionRequired &&
        sim.status != ConnectedSimStatus.permissionPermanentlyDenied,
    notifications: sync.notificationsAllowed,
    folder: sync.folder != null && sync.folderAccessible,
    sim: sim.selection != null && sim.sims.any((s) => s.subscriptionId == sim.selection!.subscriptionId),
  );
});

/// Covers the app with the "Set up your phone" checklist until every item is done, once the member is
/// signed in and has a workspace. The app underneath stays alive (it is only covered), so nothing is
/// lost when the checklist goes away.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider.select((s) => s.isAuthenticated));
    final hasWorkspace = ref.watch(workspaceControllerProvider.select((w) => w.selected != null));
    if (!signedIn || !hasWorkspace) return child;

    final checklist = ref.watch(setupChecklistProvider);
    final blocked = !checklist.loaded || !checklist.complete;
    return Stack(
      children: [
        child,
        if (blocked)
          Positioned.fill(
            child: checklist.loaded
                ? const SetupScreen(key: Key('setup-screen'))
                : const ColoredBox(key: Key('setup-loading'), color: AppColors.background, child: Center(child: CircularProgressIndicator())),
          ),
      ],
    );
  }
}

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> with WidgetsBindingObserver {
  final _number = TextEditingController();
  int? _picked;
  String? _numberError;
  bool _savingSim = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Read the SIMs afresh when the checklist opens, in case an earlier read never finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(connectedSimControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _number.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's Settings (or a permission dialog): re-read what is allowed now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(callSyncControllerProvider.notifier).load();
    ref.read(connectedSimControllerProvider.notifier).onResumed();
  }

  /// The chosen SIM's mobile number is needed first (calls are matched on it), so a SIM with no
  /// number saved asks for it here, then selects the SIM.
  Future<void> _chooseSim(SimCard sim) async {
    final controller = ref.read(connectedSimControllerProvider.notifier);
    final state = ref.read(connectedSimControllerProvider);
    if (state.numberFor(sim) == null) {
      setState(() {
        _picked = sim.subscriptionId;
        _numberError = null;
        _number.clear();
      });
      return;
    }
    await controller.select(sim);
  }

  Future<void> _saveSim(SimCard sim) async {
    final controller = ref.read(connectedSimControllerProvider.notifier);
    setState(() => _savingSim = true);
    final error = await controller.submitNumber(sim, _number.text);
    if (error == null) await controller.select(sim);
    if (mounted) {
      setState(() {
        _savingSim = false;
        _numberError = error;
        if (error == null) _picked = null;
      });
    }
  }

  String _simDetail(SetupChecklist checklist, ConnectedSimState sim) {
    if (!checklist.phone) return 'Allow phone access first, then choose the SIM you use for work calls.';
    return switch (sim.status) {
      ConnectedSimStatus.loading => 'Looking for your SIM...',
      ConnectedSimStatus.error => "Couldn't read your SIM details. Tap 'Check again'.",
      ConnectedSimStatus.permissionRequired || ConnectedSimStatus.permissionPermanentlyDenied =>
        'Phone access is needed to see your SIM. Allow it above, then tap "Check again".',
      ConnectedSimStatus.unavailable => 'This phone has no SIM support.',
      ConnectedSimStatus.ready => sim.sims.isEmpty
          ? 'No active SIM found. Insert your SIM, then tap "Check again".'
          : sim.sims.length == 1
              ? 'Confirm the SIM you use for work calls. Only its calls are added to your leads.'
              : 'Choose the SIM you use for work calls. Only its calls are added to your leads.',
    };
  }

  Widget _simPicker(ConnectedSimState sim) {
    final chosen = sim.selection?.subscriptionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sim.sims) ...[
          RadioListTile<int>(
            key: Key('setup-sim-${s.subscriptionId}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.subscriptionId,
            // ignore: deprecated_member_use
            groupValue: _picked ?? chosen,
            // ignore: deprecated_member_use
            onChanged: (_) => _chooseSim(s),
            title: Text([s.simLabel, if (s.operatorName != null) s.operatorName!].join(' • ')),
          ),
          if (_picked == s.subscriptionId)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('setup-sim-number'),
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Mobile number of ${s.simLabel}',
                      helperText: 'Calls are matched to this number.',
                      errorText: _numberError,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton(
                    key: const Key('setup-sim-save'),
                    onPressed: _savingSim ? null : () => _saveSim(s),
                    child: Text(_savingSim ? 'Saving...' : 'Use this SIM'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _allowPhone() async {
    final sync = ref.read(callSyncControllerProvider.notifier);
    final sims = ref.read(connectedSimControllerProvider.notifier);
    // Refused for good on either: only the app's page in Android Settings can allow it now.
    if (ref.read(callSyncControllerProvider).permission == SimPermissionStatus.permanentlyDenied ||
        ref.read(connectedSimControllerProvider).status == ConnectedSimStatus.permissionPermanentlyDenied) {
      await sync.openAppSettings();
      return;
    }
    if (ref.read(callSyncControllerProvider).permission != SimPermissionStatus.granted) await sync.requestPermission();
    final status = ref.read(connectedSimControllerProvider).status;
    if (status == ConnectedSimStatus.permissionRequired || status == ConnectedSimStatus.error) await sims.requestPermission();
    await sims.refresh();
  }

  Future<void> _allowNotifications() async {
    final sync = ref.read(callSyncControllerProvider.notifier);
    await sync.requestNotifications();
    // Refused for good: only the app's page in Android Settings can allow it now.
    if (!ref.read(callSyncControllerProvider).notificationsAllowed) await sync.openAppSettings();
  }

  /// One active SIM: there is nothing to choose, so it is picked for the member (asking for its
  /// number first when none is saved).
  void _autoPickSingleSim() {
    final sim = ref.read(connectedSimControllerProvider);
    if (sim.status != ConnectedSimStatus.ready || sim.sims.length != 1 || sim.selection != null || _picked != null || _savingSim) return;
    final only = sim.sims.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chooseSim(only);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checklist = ref.watch(setupChecklistProvider);
    _autoPickSingleSim();
    final sync = ref.watch(callSyncControllerProvider);
    final sim = ref.watch(connectedSimControllerProvider);
    final folderName = sync.folder?.name;

    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SizedBox(height: AppSpacing.md),
            Text('Set up your phone', key: const Key('setup-title'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${AppConstants.appName} needs these to bring your calls and call recordings to your leads. '
              'Allow all of them to start using the app.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: checklist.done / 4, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 4),
            Text('${checklist.done} of 4 done', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
            const SizedBox(height: AppSpacing.md),
            _Step(
              key: const Key('setup-phone'),
              icon: Icons.call_outlined,
              title: 'Phone and call log',
              detail: 'Lets the app see which calls you made to your leads, how long they lasted, and which SIM is which.',
              done: checklist.phone,
              actionLabel: sync.permission == SimPermissionStatus.permanentlyDenied || sim.status == ConnectedSimStatus.permissionPermanentlyDenied
                  ? 'Open settings'
                  : 'Allow',
              onAction: _allowPhone,
            ),
            _Step(
              key: const Key('setup-folder'),
              icon: Icons.folder_open_outlined,
              title: 'Call recordings folder',
              detail: checklist.folder
                  ? 'Using "$folderName". Recordings saved there are added to the right lead.'
                  : sync.folder != null
                      ? 'Access to "$folderName" was lost. Choose the folder again.'
                      : 'Choose the folder where your phone saves call recordings (for example Music > Recordings > Call Recordings). '
                          'Turn on call recording in your phone\'s dialer settings too.',
              done: checklist.folder,
              actionLabel: sync.folder != null ? 'Choose again' : 'Choose folder',
              onAction: () => ref.read(callSyncControllerProvider.notifier).pickRecordingFolder(),
            ),
            _Step(
              key: const Key('setup-notifications'),
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              detail: 'For call-back reminders and a warning if your calls have not synced.',
              done: checklist.notifications,
              actionLabel: 'Allow',
              onAction: _allowNotifications,
            ),
            _Step(
              key: const Key('setup-sim'),
              icon: Icons.sim_card_outlined,
              title: 'Business SIM',
              detail: _simDetail(checklist, sim),
              done: checklist.sim,
              actionLabel: checklist.phone && sim.sims.isEmpty && sim.status != ConnectedSimStatus.loading ? 'Check again' : null,
              onAction: () => ref.read(connectedSimControllerProvider.notifier).load(),
              child: !checklist.phone || sim.sims.isEmpty ? null : _simPicker(sim),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'You can change any of these later in Settings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.done,
    this.actionLabel,
    this.onAction,
    this.child,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool done;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        side: BorderSide(color: done ? AppColors.success : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (done) const Icon(Icons.check_circle, key: Key('setup-done'), color: AppColors.success),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
            ?child,
            if (!done && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
