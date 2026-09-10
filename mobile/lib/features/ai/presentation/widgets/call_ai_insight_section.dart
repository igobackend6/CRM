import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/ai_call_insight.dart';
import '../../domain/entities/call_ai_insight_state.dart';
import '../providers/ai_providers.dart';

/// Call Detail's "AI Insight" section (Phase 20) — added as one more
/// section on the existing screen, same restraint as every other
/// addition to this screen (§"Do not redesign Call Log or Customer
/// 360"). Handles every state the pipeline can actually produce: never
/// requested, requesting, completed, and failed (including the honest
/// "no recording"/"no AI provider configured" failure this environment
/// always produces today — see AIInsightService's own docstring).
class CallAiInsightSection extends ConsumerWidget {
  const CallAiInsightSection({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callAiInsightControllerProvider(callId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(icon: Icons.auto_awesome_outlined, title: 'AI Insight'),
        const SizedBox(height: AppSpacing.sm),
        _buildBody(context, ref, state),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, CallAiInsightState state) {
    switch (state.status) {
      case CallAiInsightStatus.initial:
      case CallAiInsightStatus.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));

      case CallAiInsightStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load the AI insight.',
          onRetry: () => ref.read(callAiInsightControllerProvider(callId).notifier).load(),
        );

      case CallAiInsightStatus.requesting:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: AppSpacing.sm),
              Text('Analyzing call…'),
            ],
          ),
        );

      case CallAiInsightStatus.loaded:
        return _LoadedInsight(callId: callId, insight: state.insight, errorMessage: state.errorMessage);
    }
  }
}

class _LoadedInsight extends ConsumerWidget {
  const _LoadedInsight({required this.callId, required this.insight, this.errorMessage});

  final String callId;
  final AiCallInsight? insight;
  final String? errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (insight == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (errorMessage != null) ...[
            Text(errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Analyze this call'),
            onPressed: () => ref.read(callAiInsightControllerProvider(callId).notifier).requestAnalysis(),
          ),
        ],
      );
    }

    switch (insight!.status) {
      case AiInsightStatus.pending:
      case AiInsightStatus.processing:
        return const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AppSpacing.sm),
            Text('Analyzing call…'),
          ],
        );

      case AiInsightStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    insight!.errorMessage ?? 'AI analysis could not be completed.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry analysis'),
              onPressed: () => ref.read(callAiInsightControllerProvider(callId).notifier).requestAnalysis(),
            ),
          ],
        );

      case AiInsightStatus.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (insight!.sentiment != null) ...[
                  AppStatusChip.forSentiment(insight!.sentiment!),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (insight!.callScore != null) Text('Score: ${insight!.callScore}', style: theme.textTheme.bodyMedium),
              ],
            ),
            if (insight!.summary != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(insight!.summary!, style: theme.textTheme.bodyMedium),
            ],
            if (insight!.actionItems.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Action items', style: theme.textTheme.labelLarge),
              for (final item in insight!.actionItems)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const Text('• '), Expanded(child: Text(item))],
                  ),
                ),
            ],
          ],
        );
    }
  }
}
