import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../leads/domain/entities/lead_status.dart';
import '../../../leads/presentation/providers/leads_providers.dart';
import '../../domain/entities/rechurn_filters.dart';
import '../../domain/entities/rechurn_lead_card.dart';
import '../../domain/entities/rechurn_list_state.dart';
import '../providers/rechurn_providers.dart';

/// Phase 19 — Rechurn / Re-engagement queue. Same loading/empty/error +
/// pull-to-refresh + load-more-on-scroll shape as `LeadListScreen`
/// (Phase 5/14), just over the rechurn-filtered lead set instead of
/// every lead. Every action reuses an existing screen/write path
/// (Lead Detail, the Call/Follow-up forms, Pipeline's status-change
/// call) — see RechurnListController's own docstring for why there is
/// no duplicated business logic here.
class RechurnQueueScreen extends ConsumerStatefulWidget {
  const RechurnQueueScreen({super.key});

  @override
  ConsumerState<RechurnQueueScreen> createState() => _RechurnQueueScreenState();
}

class _RechurnQueueScreenState extends ConsumerState<RechurnQueueScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(rechurnListControllerProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechurnListControllerProvider);
    final activeCount = ref.watch(rechurnListControllerProvider.select((s) => s.filters.activeCount));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechurn'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$activeCount'),
              isLabelVisible: activeCount > 0,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filter queue',
            onPressed: () => _openFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name, phone, or email', isDense: true),
              onChanged: (value) => ref.read(rechurnListControllerProvider.notifier).updateSearch(value),
            ),
          ),
          _SegmentChips(
            selected: state.filters.segment,
            onChanged: (segment) => ref
                .read(rechurnListControllerProvider.notifier)
                .applyFilters(state.filters.copyWith(segment: segment, clearSegment: segment == null)),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final current = ref.read(rechurnListControllerProvider).filters;
    final result = await showModalBottomSheet<RechurnFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initialFilters: current),
    );
    if (result == null || !context.mounted) return;
    await ref.read(rechurnListControllerProvider.notifier).applyFilters(result);
  }

  Widget _buildBody(RechurnListState state) {
    switch (state.status) {
      case RechurnListStatus.initial:
      case RechurnListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case RechurnListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load the rechurn queue.',
          onRetry: () => ref.read(rechurnListControllerProvider.notifier).refresh(),
        );

      case RechurnListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(rechurnListControllerProvider.notifier).refresh(),
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.history_toggle_off, message: 'No leads need re-engagement right now.'),
            ],
          ),
        );

      case RechurnListStatus.success:
      case RechurnListStatus.refreshing:
      case RechurnListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => ref.read(rechurnListControllerProvider.notifier).refresh(),
          child: ListView.separated(
            controller: _scrollController,
            itemCount: state.items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return _RechurnCard(card: state.items[index]);
            },
          ),
        );
    }
  }
}

class _SegmentChips extends StatelessWidget {
  const _SegmentChips({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.xs,
        children: [
          ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) => onChanged(null)),
          ChoiceChip(label: const Text('Inactive'), selected: selected == 'inactive', onSelected: (_) => onChanged('inactive')),
          ChoiceChip(label: const Text('Lost'), selected: selected == 'lost', onSelected: (_) => onChanged('lost')),
        ],
      ),
    );
  }
}

class _RechurnCard extends ConsumerWidget {
  const _RechurnCard({required this.card});

  final RechurnLeadCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntityListTile(
          avatarName: card.name,
          title: card.name,
          onTap: () => context.push(RoutePaths.leadDetail(card.id)),
          trailing: card.status == null
              ? null
              : AppStatusChip.forLeadStatus(name: card.status!.name, stage: card.status!.stage),
          subtitle: [card.phone, card.email].where((v) => v != null && v.isNotEmpty).join(' • ').isEmpty
              ? null
              : [card.phone, card.email].where((v) => v != null && v.isNotEmpty).join(' • '),
          metaItems: [
            MetaItem(Icons.flag_outlined, card.priority),
            MetaItem(Icons.person_outline, card.assignedMember?.fullName ?? 'Unassigned'),
            MetaItem(Icons.history, 'Last activity ${_formatDate(card.lastActivityAt)}'),
            if (card.nextFollowUp != null) MetaItem(Icons.event_note_outlined, 'Next: ${_formatDate(card.nextFollowUp!.dueAt)}'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm, bottom: AppSpacing.xs),
          child: Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.call_outlined, size: 16),
                label: const Text('Call'),
                onPressed: () => context.push(RoutePaths.callCreateForLead(card.id)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.event_note_outlined, size: 16),
                label: const Text('Follow-up'),
                onPressed: () => context.push(RoutePaths.followUpCreateForLead(card.id)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.sync_alt, size: 16),
                label: const Text('Status'),
                onPressed: () => _openStatusPicker(context, ref),
              ),
              if (card.isCustomer)
                TextButton.icon(
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('Customer 360'),
                  onPressed: () => context.push(RoutePaths.customerDetail(card.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openStatusPicker(BuildContext context, WidgetRef ref) async {
    final statusId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _StatusPickerSheet(),
    );
    if (statusId == null || !context.mounted) return;
    final ok = await ref.read(rechurnListControllerProvider.notifier).changeStatus(leadId: card.id, statusId: statusId);
    if (!context.mounted) return;
    if (!ok) {
      final message = ref.read(rechurnListControllerProvider).errorMessage ?? 'Could not change the lead status.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Inline "Update status" picker — reuses `leadReferenceDataProvider`
/// (already loaded elsewhere for the same workspace) rather than a
/// dedicated rechurn statuses request, same reuse `LeadListScreen`'s own
/// `_BulkStatusPickerSheet` already relies on.
class _StatusPickerSheet extends ConsumerWidget {
  const _StatusPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referenceAsync = ref.watch(leadReferenceDataProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change status to', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: referenceAsync.when(
                loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
                error: (error, stackTrace) => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text('Could not load statuses.')),
                data: (reference) {
                  final statuses = reference.statuses;
                  if (statuses.isEmpty) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text('No statuses configured for this workspace.'));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: statuses.length,
                    itemBuilder: (context, index) => _StatusTile(status: statuses[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status});

  final LeadStatus status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: AppStatusChip.forLeadStatus(name: status.name, stage: status.stage),
      onTap: () => Navigator.pop(context, status.id),
    );
  }
}

/// Segment/inactive-days/assignee/priority/status/source filters — same
/// bottom-sheet shape as `LeadListScreen`'s own `_FilterSheet`, just for
/// the rechurn-specific field set (no saved views/tags/created-date/
/// customer filter here — out of scope).
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initialFilters});

  final RechurnFilters initialFilters;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _assignedMemberId = widget.initialFilters.assignedMemberId;
  late String? _priority = widget.initialFilters.priority;
  late String? _statusId = widget.initialFilters.statusId;
  late String? _sourceId = widget.initialFilters.sourceId;
  late int _inactiveDays = widget.initialFilters.inactiveDays;

  RechurnFilters get _current => RechurnFilters(
        segment: widget.initialFilters.segment,
        inactiveDays: _inactiveDays,
        assignedMemberId: _assignedMemberId,
        priority: _priority,
        statusId: _statusId,
        sourceId: _sourceId,
      );

  @override
  Widget build(BuildContext context) {
    final referenceAsync = ref.watch(leadReferenceDataProvider);
    final membersAsync = ref.watch(workspaceMembersProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.md, top: AppSpacing.md, bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filter rechurn queue', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                Text('Inactive for at least', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final days in const [14, 30, 60, 90])
                      ChoiceChip(label: Text('$days days'), selected: _inactiveDays == days, onSelected: (_) => setState(() => _inactiveDays = days)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Status', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                referenceAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const Text('Could not load statuses.'),
                  data: (reference) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any status'), selected: _statusId == null, onSelected: (_) => setState(() => _statusId = null)),
                      for (final status in reference.statuses)
                        ChoiceChip(label: Text(status.name), selected: _statusId == status.id, onSelected: (_) => setState(() => _statusId = status.id)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Source', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                referenceAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const Text('Could not load sources.'),
                  data: (reference) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any source'), selected: _sourceId == null, onSelected: (_) => setState(() => _sourceId = null)),
                      for (final source in reference.sources)
                        ChoiceChip(label: Text(source.name), selected: _sourceId == source.id, onSelected: (_) => setState(() => _sourceId = source.id)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Assigned to', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                membersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const Text('Could not load members.'),
                  data: (members) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any assignee'), selected: _assignedMemberId == null, onSelected: (_) => setState(() => _assignedMemberId = null)),
                      for (final member in members)
                        ChoiceChip(label: Text(member.displayName), selected: _assignedMemberId == member.id, onSelected: (_) => setState(() => _assignedMemberId = member.id)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Priority', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    ChoiceChip(label: const Text('Any priority'), selected: _priority == null, onSelected: (_) => setState(() => _priority = null)),
                    for (final priority in const ['low', 'medium', 'high', 'urgent'])
                      ChoiceChip(label: Text(priority), selected: _priority == priority, onSelected: (_) => setState(() => _priority = priority)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, RechurnFilters(segment: widget.initialFilters.segment)),
                        child: const Text('Clear all'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(onPressed: () => Navigator.pop(context, _current), child: const Text('Apply filters')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
