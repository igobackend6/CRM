import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../providers/native_dialer_providers.dart';

/// Settings > Default Dialer: use Sales CRM as the phone's calling app. Off (the default) keeps
/// calls in Google Phone exactly as today; on, calls placed from the CRM and calls you receive use
/// the CRM's own call screen. Android decides who the Phone app is, so the switch always shows what
/// the phone says.
class DefaultDialerScreen extends ConsumerStatefulWidget {
  const DefaultDialerScreen({super.key});

  @override
  ConsumerState<DefaultDialerScreen> createState() => _DefaultDialerScreenState();
}

class _DefaultDialerScreenState extends ConsumerState<DefaultDialerScreen> with WidgetsBindingObserver {
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
    // Back from Android's Default apps page: look again at who the Phone app is.
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (lifecycle == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      ref.read(defaultDialerControllerProvider.notifier).refresh();
    }
  }

  Future<void> _onChanged(bool wantOn) async {
    final controller = ref.read(defaultDialerControllerProvider.notifier);
    if (wantOn) {
      await controller.turnOn();
      return;
    }
    // Android has no button for an app to give the Phone role back.
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('default-dialer-off-dialog'),
        title: const Text('Hand the phone back'),
        content: const Text(
          'To go back to Google Phone, open Android\'s Default apps and choose "Phone app" > Phone (Google). '
          'Sales CRM will then stop handling calls.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('default-dialer-open-settings'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Open Default apps')),
        ],
      ),
    );
    if (go == true) await controller.openDefaultAppsSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(defaultDialerControllerProvider);
    final accounts = ref.watch(dialerPhoneAccountsProvider).valueOrNull ?? const [];
    final dim = theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim);
    final on = state.isDefault;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Default Dialer')),
      body: !state.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.dialpad),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: Text('CRM Dialer', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                            Switch(
                              key: const Key('default-dialer-switch'),
                              value: on,
                              onChanged: state.busy || !state.status.available ? null : _onChanged,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: on ? AppColors.success : AppColors.textDim),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              on ? 'Default Phone App' : 'Not default',
                              key: const Key('default-dialer-status'),
                              style: TextStyle(fontWeight: FontWeight.w600, color: on ? AppColors.success : AppColors.textDim),
                            ),
                          ],
                        ),
                        if (!state.status.available) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('This phone doesn\'t let apps become the Phone app.', key: const Key('default-dialer-unavailable'), style: dim),
                        ],
                        if (state.message != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(state.message!, key: const Key('default-dialer-message'), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.warning)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('When it is on', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                const _Point(Icons.call_made, 'Calls you start from the CRM use the CRM\'s own call screen, on your business SIM.'),
                const _Point(Icons.call_received, 'Incoming calls show your CRM lead\'s name and status.'),
                const _Point(Icons.sync, 'Every call is added to the lead\'s call history as soon as it ends.'),
                const _Point(Icons.emergency, 'Emergency calls always work: Android handles them itself.'),
                const SizedBox(height: AppSpacing.md),
                Container(
                  key: const Key('default-dialer-warning'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.standard),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: const Text(
                    'While Sales CRM is your Phone app, Google Phone\'s call recording stops working for new calls. '
                    'Turn this off to get it back. Recordings you already saved stay in the CRM.',
                  ),
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Your SIMs', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  for (final a in accounts) _Point(Icons.sim_card_outlined, a.label),
                  Text('Calls use your business SIM (Settings > Connected SIM Details) unless you pick another on the dialer.', style: dim),
                ],
              ],
            ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textDim),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
