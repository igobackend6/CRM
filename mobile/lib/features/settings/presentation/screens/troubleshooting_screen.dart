import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../domain/diagnostic_check.dart';
import '../providers/diagnostics_providers.dart';
import '../providers/settings_providers.dart';

/// Settings > Troubleshooting: quick health checks, plus a way to hand the diagnostic log to support.
class TroubleshootingScreen extends ConsumerWidget {
  const TroubleshootingScreen({super.key});

  Future<void> _copyLog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final lines = AppLogger.bufferedLines;
    if (lines.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The log is empty. Turn on "Enable Log" in Settings, repeat the problem, then copy it here.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    messenger.showSnackBar(SnackBar(content: Text('Copied ${lines.length} log ${lines.length == 1 ? 'line' : 'lines'}.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final checks = ref.watch(diagnosticsProvider);
    // Re-run the "Diagnostic log" line when Enable Log is flipped.
    ref.listen(appSettingsControllerProvider.select((s) => s.loggingEnabled), (_, _) => ref.invalidate(diagnosticsProvider));

    return Scaffold(
      appBar: brandAppBar(title: const Text('Troubleshooting')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Checks', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          checks.when(
            loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => const Text('Could not run the checks. Pull back and try again.'),
            data: (list) => Card(
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _CheckRow(check: list[i]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('run-checks'),
            onPressed: () => ref.invalidate(diagnosticsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Run checks again'),
          ),
          const SizedBox(height: 24),
          Text('Diagnostic log', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'If something isn\'t working, turn on "Enable Log" in Settings, repeat the problem, then copy the log '
            'here and send it to support. It stays on this phone until you copy it.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('copy-log'),
            onPressed: () => _copyLog(context, ref),
            icon: const Icon(Icons.copy),
            label: const Text('Copy diagnostic log'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('clear-log'),
            onPressed: () {
              AppLogger.clearBuffer();
              ref.invalidate(diagnosticsProvider);
            },
            child: const Text('Clear log'),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final DiagnosticCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      DiagnosticStatus.ok => (Icons.check_circle, AppColors.success),
      DiagnosticStatus.warning => (Icons.warning_amber_rounded, AppColors.warning),
      DiagnosticStatus.problem => (Icons.error, AppColors.danger),
      DiagnosticStatus.info => (Icons.info, AppColors.textDim),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(check.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(check.detail),
    );
  }
}
