import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../controllers/app_settings_controller.dart';
import '../providers/settings_providers.dart';
import '../widgets/app_lock_gate.dart';

/// Settings > App Security: ask for the phone's fingerprint / face / PIN when the app is opened or
/// comes back after being away.
class AppSecurityScreen extends ConsumerStatefulWidget {
  const AppSecurityScreen({super.key});

  @override
  ConsumerState<AppSecurityScreen> createState() => _AppSecurityScreenState();
}

class _AppSecurityScreenState extends ConsumerState<AppSecurityScreen> {
  bool _busy = false;

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await ref.read(appSettingsControllerProvider.notifier).setAppLock(enabled);
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      AppLockChangeResult.changed => null,
      AppLockChangeResult.notSupported =>
        'Set a screen lock (PIN, pattern or fingerprint) in your phone\'s settings first, then try again.',
      AppLockChangeResult.notConfirmed => 'Not confirmed, so app lock was left as it was.',
    };
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(appSettingsControllerProvider.select((s) => s.appLockEnabled));
    final minutes = kAppLockTimeout.inMinutes;

    return Scaffold(
      appBar: brandAppBar(title: const Text('App Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Keep your leads and customers private. With app lock on, the app asks for your phone\'s '
                  'fingerprint, face or screen-lock PIN each time you open it, and when you come back after '
                  'being away for $minutes ${minutes == 1 ? 'minute' : 'minutes'} or more.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              key: const Key('app-lock-switch'),
              title: const Text('Lock the app'),
              subtitle: Text(enabled ? 'On' : 'Off'),
              secondary: const Icon(Icons.lock_outline, color: AppColors.accent),
              value: enabled,
              onChanged: _busy ? null : _toggle,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Turning this on or off asks you to confirm with your phone first. '
            'If you forget your phone\'s PIN, you can still sign out from the lock screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
