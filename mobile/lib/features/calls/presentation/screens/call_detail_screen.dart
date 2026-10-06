import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/widgets/call_ai_insight_section.dart';
import '../../domain/entities/call_detail_state.dart';
import '../providers/call_providers.dart';
import 'call_list_screen.dart' show formatCallDateTime;

/// Call Detail (Phase 9 §3) — every relevant field the schema carries,
/// plus navigation to the related Lead/Customer 360. Mirrors
/// FollowUpDetailScreen's status-switch structure. Does not duplicate
/// lead/customer data (§3): only the lead's name + a link, not its full
/// profile.
class CallDetailScreen extends ConsumerWidget {
  const CallDetailScreen({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callDetailControllerProvider(callId));

    return Scaffold(
      appBar: brandAppBar(title: const Text('Call')),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, CallDetailState state) {
    switch (state.status) {
      case CallDetailStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case CallDetailStatus.notFound:
        return const Center(child: Text('This call could not be found.'));

      case CallDetailStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => ref.read(callDetailControllerProvider(callId).notifier).load(),
        );

      case CallDetailStatus.success:
        final call = state.call!;
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AccentCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.12),
                    child: Icon(call.isInbound ? Icons.call_received : Icons.call_made, color: theme.colorScheme.secondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(call.lead.name, style: theme.textTheme.headlineSmall),
                        if (call.outcome != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          AppStatusChip.forCallOutcome(name: call.outcome!.name, isPositive: call.outcome!.isPositive),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.person_search_outlined, size: 18),
              label: const Text('View lead'),
              onPressed: () => context.push(RoutePaths.leadDetail(call.lead.id)),
            ),
            const SizedBox(height: AppSpacing.sm),
            DetailInfoRow(label: 'Direction', value: call.direction),
            DetailInfoRow(label: 'Status', value: call.state),
            DetailInfoRow(label: 'Started', value: formatCallDateTime(call.startedAt)),
            DetailInfoRow(label: 'Duration', value: call.formattedDuration),
            DetailInfoRow(label: 'Caller', value: call.agentMember?.fullName ?? 'Unknown'),
            DetailInfoRow(label: 'Logged', value: formatCallDateTime(call.createdAt)),
            if (call.notes != null && call.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(icon: Icons.notes_outlined, title: 'Notes'),
              const SizedBox(height: AppSpacing.sm),
              Text(call.notes!),
            ],
            const SizedBox(height: AppSpacing.lg),
            CallAiInsightSection(callId: callId),
          ],
        );
    }
  }
}
