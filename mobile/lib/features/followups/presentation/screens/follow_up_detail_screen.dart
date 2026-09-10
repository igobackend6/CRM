import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/follow_up_detail_state.dart';
import '../providers/followup_providers.dart';
import 'follow_up_list_screen.dart' show formatFollowUpDateTime;

/// Follow-Up Detail (Phase 7 §2B/§2E) — lead, schedule, type, status,
/// assignee, notes, created info, plus quick Complete/Cancel actions
/// while pending. Mirrors LeadDetailScreen's status-switch structure.
class FollowUpDetailScreen extends ConsumerWidget {
  const FollowUpDetailScreen({super.key, required this.followUpId});

  final String followUpId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(followUpDetailControllerProvider(followUpId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow-up'),
        actions: [
          if (state.status == FollowUpDetailStatus.success)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push(RoutePaths.followUpEdit(followUpId)),
            ),
        ],
      ),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, FollowUpDetailState state) {
    switch (state.status) {
      case FollowUpDetailStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case FollowUpDetailStatus.notFound:
        return const Center(child: Text('This follow-up could not be found.'));

      case FollowUpDetailStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => ref.read(followUpDetailControllerProvider(followUpId).notifier).load(),
        );

      case FollowUpDetailStatus.success:
        final followUp = state.followUp!;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AccentCard(
              accentColor: followUp.isOverdue ? Theme.of(context).colorScheme.error : null,
              child: Row(
                children: [
                  InitialsAvatar(name: followUp.lead.name, size: 48),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(followUp.lead.name, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: AppSpacing.xs),
                        AppStatusChip.forFollowUpStatus(status: followUp.status, isOverdue: followUp.isOverdue),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DetailInfoRow(label: 'Type', value: followUp.type),
            DetailInfoRow(label: 'Due', value: formatFollowUpDateTime(followUp.dueAt)),
            DetailInfoRow(label: 'Assigned to', value: followUp.assignedMember?.fullName ?? 'Unassigned'),
            DetailInfoRow(label: 'Created by', value: followUp.createdByMember?.fullName ?? '—'),
            DetailInfoRow(label: 'Created', value: formatFollowUpDateTime(followUp.createdAt)),
            if (followUp.notes != null && followUp.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(icon: Icons.notes_outlined, title: 'Notes'),
              const SizedBox(height: AppSpacing.sm),
              Text(followUp.notes!),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (followUp.isPending) ...[
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Mark complete'),
                      onPressed: () => ref.read(followUpDetailControllerProvider(followUpId).notifier).updateStatus('completed'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                      onPressed: () => ref.read(followUpDetailControllerProvider(followUpId).notifier).updateStatus('cancelled'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
    }
  }
}
