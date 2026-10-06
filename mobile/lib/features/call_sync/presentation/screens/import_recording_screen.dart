import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_status_chip.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../../sim/presentation/screens/connected_sim_screen.dart' show formatDetectedAt;
import '../../domain/shared_audio.dart';
import '../providers/call_sync_providers.dart';

/// Share > Sales CRM on a call recording: confirm which call it belongs to, then it is stored in the
/// CRM (for the lead and the admins) and on this phone.
class ImportRecordingScreen extends ConsumerWidget {
  const ImportRecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(pendingSharedAudioProvider);
    return Scaffold(
      appBar: brandAppBar(title: const Text('Add call recording')),
      body: audio == null
          ? const Center(key: Key('import-nothing'), child: Text('There is no recording to add.'))
          : _Body(audio: audio),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.audio});

  final SharedAudio audio;

  static String _length(int? seconds) => seconds == null ? '' : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(recordingImportControllerProvider(audio));
    final controller = ref.read(recordingImportControllerProvider(audio).notifier);
    final dim = theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim);

    if (state.done) {
      return Center(
        key: const Key('import-done'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 56, color: AppColors.success),
              const SizedBox(height: AppSpacing.md),
              Text('Recording added', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'It is saved with the call in the CRM and on this phone. Open the lead\'s Call recordings to play it.',
                textAlign: TextAlign.center,
                style: dim,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('import-close'),
                onPressed: () => context.canPop() ? context.pop() : context.go('/app'),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: Text(audio.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([if (audio.durationSeconds != null) _length(audio.durationSeconds), '${(audio.sizeBytes / 1024).round()} KB'].join(' · ')),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Which call is this?', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text('Calls to your leads on the business SIM that are still waiting for a recording.', style: dim),
        const SizedBox(height: AppSpacing.sm),
        if (!state.loading && audio.recordedAt != null && state.candidates.isNotEmpty && state.selectedCallId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'The call this was recorded on (${formatDetectedAt(context, audio.recordedAt!, DateTime.now())}) is not in the CRM yet. '
              'Tap "Check calls again" in a moment, or pick the call yourself.',
              key: const Key('import-call-not-synced'),
              style: dim?.copyWith(color: AppColors.warning),
            ),
          ),
        if (state.loading)
          const Padding(
            key: Key('import-loading'),
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.candidates.isEmpty)
          Container(
            key: const Key('import-no-calls'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.standard),
              border: Border.all(color: AppColors.warning),
            ),
            child: const Text(
              'No recent call is waiting for a recording. Check the call was to a lead\'s number on your business SIM and that '
              'Sync Call History is set up, then check again.',
            ),
          )
        else
          RadioGroup<String>(
            groupValue: state.selectedCallId,
            onChanged: (value) {
              if (value != null) controller.select(value);
            },
            child: Column(
              children: [
                for (final c in state.candidates)
                  Card(
                    key: Key('import-call-${c.call.callId}'),
                    child: RadioListTile<String>(
                      value: c.call.callId,
                      title: Row(
                        children: [
                          Flexible(child: Text(formatDetectedAt(context, DateTime.fromMillisecondsSinceEpoch(c.call.startMillis), DateTime.now()))),
                          if (c.likely) ...[
                            const SizedBox(width: AppSpacing.sm),
                            const AppStatusChip(label: 'Best match', tone: ChipTone.positive),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        [
                          '${_length(c.call.durationSeconds)} call',
                          if (c.call.phoneKey != null) 'number ending ${c.call.phoneKey!.substring(c.call.phoneKey!.length - 4)}',
                        ].join(' · '),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(state.errorMessage!, key: const Key('import-error'), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('import-attach'),
          onPressed: state.selectedCallId == null || state.attaching || state.loading ? null : controller.attach,
          icon: state.attaching
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(state.attaching ? 'Adding...' : 'Add recording to this call'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('import-refresh'),
          onPressed: state.loading || state.attaching ? null : controller.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Check calls again'),
        ),
      ],
    );
  }
}
