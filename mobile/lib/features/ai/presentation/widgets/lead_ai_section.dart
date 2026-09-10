import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/ai_call_insight.dart';
import '../../domain/entities/lead_ai_assistant_state.dart';
import '../../domain/entities/lead_ai_insights_state.dart';
import '../providers/ai_providers.dart';

/// Lead Detail/Customer 360's "Lead Insights" + "AI Assistant" section
/// (Phase 20 §"Lead Insights"/§"AI Assistant") — added as one more
/// section on the existing screen (§"Do not redesign Call Log or
/// Customer 360"). Two independent sub-widgets so a slow/failed
/// assistant answer never blocks the insights list, same pattern every
/// other multi-source screen in this app already uses.
class LeadAiSection extends StatelessWidget {
  const LeadAiSection({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(icon: Icons.auto_awesome_outlined, title: 'Lead Insights'),
        const SizedBox(height: AppSpacing.sm),
        _LeadInsightsList(leadId: leadId),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.smart_toy_outlined, title: 'AI Assistant'),
        const SizedBox(height: AppSpacing.sm),
        _AiAssistantBox(leadId: leadId),
      ],
    );
  }
}

class _LeadInsightsList extends ConsumerWidget {
  const _LeadInsightsList({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leadAiInsightsControllerProvider(leadId));
    switch (state.status) {
      case LeadAiInsightsStatus.initial:
      case LeadAiInsightsStatus.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));

      case LeadAiInsightsStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load lead insights.',
          onRetry: () => ref.read(leadAiInsightsControllerProvider(leadId).notifier).load(),
        );

      case LeadAiInsightsStatus.empty:
        return const EmptyStateView(icon: Icons.auto_awesome_outlined, message: 'No AI call insights yet.');

      case LeadAiInsightsStatus.success:
        return Column(children: state.items.map((item) => _InsightTile(item: item)).toList());
    }
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.item});

  final AiCallInsight item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (item.status != AiInsightStatus.completed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          item.status == AiInsightStatus.failed ? (item.errorMessage ?? 'Analysis failed.') : 'Analysis in progress…',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.sentiment != null) ...[AppStatusChip.forSentiment(item.sentiment!), const SizedBox(width: AppSpacing.sm)],
          Expanded(child: Text(item.summary ?? '', style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AiAssistantBox extends ConsumerStatefulWidget {
  const _AiAssistantBox({required this.leadId});

  final String leadId;

  @override
  ConsumerState<_AiAssistantBox> createState() => _AiAssistantBoxState();
}

class _AiAssistantBoxState extends ConsumerState<_AiAssistantBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leadAiAssistantControllerProvider(widget.leadId));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Ask about this lead…', isDense: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: state.status == LeadAiAssistantStatus.asking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              tooltip: 'Ask',
              onPressed: state.status == LeadAiAssistantStatus.asking
                  ? null
                  : () => ref.read(leadAiAssistantControllerProvider(widget.leadId).notifier).ask(_controller.text),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        switch (state.status) {
          LeadAiAssistantStatus.idle || LeadAiAssistantStatus.asking => const SizedBox.shrink(),
          LeadAiAssistantStatus.answered => Text(state.answer ?? '', style: theme.textTheme.bodyMedium),
          LeadAiAssistantStatus.unavailable => Text(
              state.message ?? 'The AI assistant is not available.',
              style: theme.textTheme.bodySmall,
            ),
          LeadAiAssistantStatus.error => Text(
              state.message ?? 'Could not reach the AI assistant.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
        },
      ],
    );
  }
}
