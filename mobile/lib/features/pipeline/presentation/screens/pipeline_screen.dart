import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../leads/domain/entities/lead_status.dart';
import '../../domain/entities/pipeline_column.dart';
import '../../domain/entities/pipeline_lead_card.dart';
import '../../domain/entities/pipeline_state.dart';
import '../providers/pipeline_providers.dart';

/// Pipeline / Sales Funnel board (Phase 12) — leads grouped into columns
/// by the workspace's own `lead_statuses`, never a hardcoded status list
/// (§"Status Handling"). Its own screen (`RoutePaths.pipeline`), reached
/// from the Lead List app bar — the existing shell (app bar/nav) is
/// otherwise untouched (§"Do NOT redesign the existing app shell").
class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});

  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pipelineControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pipeline')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, phone, or email',
                isDense: true,
              ),
              onChanged: (value) => ref.read(pipelineControllerProvider.notifier).updateSearch(value),
            ),
          ),
          Expanded(child: _buildBody(context, state)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, PipelineState state) {
    switch (state.status) {
      case PipelineStatus.initial:
      case PipelineStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case PipelineStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load the pipeline.',
          onRetry: () => ref.read(pipelineControllerProvider.notifier).refresh(),
        );

      case PipelineStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(pipelineControllerProvider.notifier).refresh(),
          child: ListView(
            children: [
              const SizedBox(height: 80),
              EmptyStateView(
                icon: Icons.view_column_outlined,
                message: state.searchQuery.isEmpty
                    ? 'No leads in the pipeline yet.'
                    : 'No leads match "${state.searchQuery}".',
              ),
            ],
          ),
        );

      case PipelineStatus.success:
      case PipelineStatus.refreshing:
        return _PipelineBoard(columns: state.columns);
    }
  }
}

/// A horizontally-scrolling row of status columns, each independently
/// vertically-scrolling — the standard Kanban-board layout. Wrapped in a
/// vertical `SingleChildScrollView` (rather than a horizontal one) so
/// `RefreshIndicator`'s pull-down gesture still works: the outer
/// scrollable is vertical (its content is exactly one viewport tall, so
/// it never actually needs to scroll), while the horizontal board
/// scrolls independently inside it.
class _PipelineBoard extends ConsumerWidget {
  const _PipelineBoard({required this.columns});

  final List<PipelineColumn> columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allStatuses = columns.map((c) => c.status).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: () => ref.read(pipelineControllerProvider.notifier).refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: columns.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: _PipelineColumnView(column: columns[index], allStatuses: allStatuses),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PipelineColumnView extends StatelessWidget {
  const _PipelineColumnView({required this.column, required this.allStatuses});

  final PipelineColumn column;
  final List<LeadStatus> allStatuses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.standard),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: AppStatusChip.forLeadStatus(name: column.status.name, stage: column.status.stage),
                  ),
                  Text('${column.total}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: column.leads.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text('No leads here.', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      itemCount: column.leads.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _PipelineLeadCardTile(lead: column.leads[index], otherStatuses: allStatuses.where((s) => s.id != column.status.id).toList()),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineLeadCardTile extends ConsumerWidget {
  const _PipelineLeadCardTile({required this.lead, required this.otherStatuses});

  final PipelineLeadCard lead;
  final List<LeadStatus> otherStatuses;

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, LeadStatus newStatus) async {
    final ok = await ref.read(pipelineControllerProvider.notifier).changeStatus(leadId: lead.id, statusId: newStatus.id);
    if (!context.mounted) return;
    if (!ok) {
      final message = ref.read(pipelineControllerProvider).errorMessage ?? 'Could not change the lead status.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contact = [lead.phone, lead.email].where((v) => v != null && v.isNotEmpty).join(' • ');
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        onTap: () => context.push(RoutePaths.leadDetail(lead.id)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.standard),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(lead.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (otherStatuses.isNotEmpty)
                    PopupMenuButton<LeadStatus>(
                      icon: Icon(Icons.more_vert, size: 18, color: theme.colorScheme.outline),
                      tooltip: 'Change status',
                      padding: EdgeInsets.zero,
                      onSelected: (status) => _changeStatus(context, ref, status),
                      itemBuilder: (context) => [
                        for (final status in otherStatuses) PopupMenuItem(value: status, child: Text('Move to ${status.name}')),
                      ],
                    ),
                ],
              ),
              if (contact.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(contact, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: AppSpacing.xs),
              MetaRow(
                items: [
                  MetaItem(Icons.flag_outlined, lead.priority),
                  MetaItem(Icons.person_outline, lead.assignedMember?.displayName ?? 'Unassigned'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
