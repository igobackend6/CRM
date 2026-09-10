import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../calls/presentation/providers/call_providers.dart';
import '../../../calls/presentation/screens/call_list_screen.dart' show CallTile;
import '../../../documents/presentation/widgets/documents_section.dart';
import '../../../followups/domain/entities/follow_up.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../messaging/presentation/widgets/messages_entry_button.dart';
import '../../../whatsapp/presentation/widgets/whatsapp_send_button.dart';
import '../../domain/entities/customer_detail_state.dart';
import '../../domain/entities/timeline_item.dart';
import '../../domain/entities/timeline_list_state.dart';
import '../providers/customer360_providers.dart';

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Customer 360 (Phase 8) — built entirely on the existing `leads` model
/// (a customer IS a lead with is_customer=true, §"Customer model"): no
/// new customer entity, no duplicated tag/follow-up/document state.
/// Section order follows §14: Header -> Profile/Contact ->
/// Status/Priority/Assignment -> Tags -> Documents -> Follow-Ups ->
/// Unified Timeline. Documents/Follow-ups/Timeline are each fetched
/// lazily by their own section widget, not eagerly on screen load
/// (§15 "lazy-load large sections").
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerDetailControllerProvider(customerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Customer 360')),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, CustomerDetailState state) {
    switch (state.status) {
      case CustomerDetailStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case CustomerDetailStatus.notFound:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('This customer could not be found, or this lead is not a customer.', textAlign: TextAlign.center),
          ),
        );

      case CustomerDetailStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => ref.read(customerDetailControllerProvider(customerId).notifier).load(),
        );

      case CustomerDetailStatus.success:
        final customer = state.customer!;
        return RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.read(customerDetailControllerProvider(customerId).notifier).load(),
            ref.read(customerTimelineControllerProvider(customerId).notifier).refresh(),
          ]),
          child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AccentCard(
              accentColor: AppColors.success,
              child: Row(
                children: [
                  InitialsAvatar(name: customer.name, size: 48),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.name, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: AppSpacing.xs),
                        const AppStatusChip(label: 'Customer', tone: ChipTone.positive, icon: Icons.verified),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                MessagesEntryButton(leadId: customerId),
                WhatsAppSendButton(
                  leadName: customer.name,
                  leadPhone: customer.phone,
                  leadStatus: customer.status?.name,
                  assignedMemberName: customer.assignedMember?.fullName,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionHeader(icon: Icons.badge_outlined, title: 'Profile'),
            const SizedBox(height: AppSpacing.sm),
            DetailInfoRow(label: 'Phone', value: customer.phone ?? '—'),
            DetailInfoRow(label: 'Email', value: customer.email ?? '—'),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.assignment_ind_outlined, title: 'Status & assignment'),
            const SizedBox(height: AppSpacing.sm),
            DetailInfoRow(label: 'Status', value: customer.status?.name ?? '—'),
            DetailInfoRow(label: 'Priority', value: customer.priority),
            DetailInfoRow(label: 'Source', value: customer.source?.name ?? '—'),
            DetailInfoRow(label: 'Assigned to', value: customer.assignedMember?.fullName ?? 'Unassigned'),
            DetailInfoRow(label: 'Created by', value: customer.createdByMember?.fullName ?? '—'),
            DetailInfoRow(label: 'Created', value: _formatDateTime(customer.createdAt)),
            DetailInfoRow(label: 'Updated', value: _formatDateTime(customer.updatedAt)),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.sell_outlined, title: 'Tags'),
            const SizedBox(height: AppSpacing.sm),
            if (customer.tags.isEmpty)
              const Text('No tags.')
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: customer.tags.map((tag) => Chip(label: Text(tag.name))).toList(),
              ),
            const SizedBox(height: AppSpacing.lg),
            DocumentsSection(leadId: customerId),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.event_note_outlined, title: 'Follow-ups'),
            const SizedBox(height: AppSpacing.sm),
            _FollowUpsSection(customerId: customerId),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              icon: Icons.call_outlined,
              title: 'Calls',
              action: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log call'),
                onPressed: () => context.push(RoutePaths.callCreateForLead(customerId)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CallsSection(customerId: customerId),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.timeline_outlined, title: 'Activity timeline'),
            const SizedBox(height: AppSpacing.sm),
            _NoteComposer(customerId: customerId),
            const SizedBox(height: AppSpacing.sm),
            _TimelineFilterChips(customerId: customerId),
            const SizedBox(height: AppSpacing.sm),
            _TimelineSection(customerId: customerId),
            ],
          ),
        );
    }
  }
}

/// Follow-Ups section (§2 "Follow-Ups") — reuses the Phase 7 FollowUp
/// entity/Follow-Up Detail screen unchanged, no duplicated state.
class _FollowUpsSection extends ConsumerWidget {
  const _FollowUpsSection({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followUpsAsync = ref.watch(customerFollowUpsProvider(customerId));
    return followUpsAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => const Text('Could not load follow-ups.'),
      data: (followUps) {
        if (followUps.isEmpty) return const Text('No follow-ups yet.');
        final pending = followUps.where((f) => f.status == 'pending').length;
        final completed = followUps.where((f) => f.status == 'completed').length;
        final cancelled = followUps.where((f) => f.status == 'cancelled').length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$pending pending • $completed completed • $cancelled cancelled', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            ...followUps.map((f) => _FollowUpTile(followUp: f)),
          ],
        );
      },
    );
  }
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.followUp});

  final FollowUp followUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = followUp.isOverdue ? theme.colorScheme.error : theme.colorScheme.secondary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: tone.withValues(alpha: 0.12),
        child: Icon(followUp.isOverdue ? Icons.warning_amber_outlined : Icons.event_note_outlined, size: 16, color: tone),
      ),
      title: Text('${followUp.type} • ${_formatDateTime(followUp.dueAt)}'),
      subtitle: Text(followUp.status),
      onTap: () => context.push(RoutePaths.followUpDetail(followUp.id)),
    );
  }
}

/// Calls section (Phase 9 §7) — reuses the calls feature's lead-nested
/// provider unchanged (`leadCallsProvider(customerId)`: a customer IS a
/// lead, §"Customer model", so the same `GET /leads/{id}/calls` endpoint
/// serves both Lead Detail and Customer 360 without a second endpoint or
/// a second aggregation path — §7 "reuse the existing Phase 8 call
/// aggregation path where possible. Do not build a second timeline
/// system"). Real call records also appear in the unified timeline below
/// unchanged (CustomerService._call_item, Phase 8) — this section is an
/// additional, focused view, not a competing source of truth.
class _CallsSection extends ConsumerWidget {
  const _CallsSection({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(leadCallsProvider(customerId));
    return callsAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator()),
      error: (error, stackTrace) => const Text('Could not load calls.'),
      data: (calls) {
        if (calls.isEmpty) return const Text('No calls logged yet.');
        final preview = calls.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...preview.map((c) => CallTile(call: c, showLeadName: false)),
            if (calls.length > preview.length)
              TextButton(
                onPressed: () => context.push(RoutePaths.callsForLead(customerId)),
                child: const Text('View all calls'),
              ),
          ],
        );
      },
    );
  }
}

/// Minimal note-creation capability (§7) — posts directly to
/// /customers/{id}/notes and prepends the result into the timeline
/// section's already-loaded state, avoiding a full timeline refetch.
class _NoteComposer extends ConsumerStatefulWidget {
  const _NoteComposer({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<_NoteComposer> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final requestContext = resolveLeadContext(ref.read);
    if (requestContext == null) return;

    setState(() => _saving = true);
    try {
      final repository = ref.read(customerRepositoryProvider);
      final item = await repository.createNote(
        accessToken: requestContext.accessToken,
        workspaceId: requestContext.workspaceId,
        customerId: widget.customerId,
        text: text,
      );
      ref.read(customerTimelineControllerProvider(widget.customerId).notifier).prependItem(item);
      _controller.clear();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Add a note…', isDense: true),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
        ),
      ],
    );
  }
}

/// Phase 15 §"Activity Filters" — reuses the shared [ActivityFilterChips]
/// widget so Customer 360 and Lead Detail render the exact same filter
/// row.
class _TimelineFilterChips extends ConsumerWidget {
  const _TimelineFilterChips({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(customerTimelineControllerProvider(customerId).select((s) => s.filter));
    return ActivityFilterChips(
      selected: filter,
      onChanged: (f) => ref.read(customerTimelineControllerProvider(customerId).notifier).setFilter(f),
    );
  }
}

/// Unified timeline section (§3/§4/§10) — lazy fetch + "load more"
/// pagination, same pattern as _DocumentsSection. Phase 15 adds
/// navigation-on-tap (call/follow-up -> their existing detail screens)
/// and renders the active filter's [TimelineListState.visibleItems]
/// instead of the raw, unfiltered `items`.
class _TimelineSection extends ConsumerStatefulWidget {
  const _TimelineSection({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends ConsumerState<_TimelineSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final state = ref.read(customerTimelineControllerProvider(widget.customerId));
      if (state.status == TimelineListStatus.initial) {
        ref.read(customerTimelineControllerProvider(widget.customerId).notifier).refresh();
      }
    });
  }

  void _openActivity(TimelineItem item) {
    switch (item.type) {
      case 'call':
        context.push(RoutePaths.callDetail(item.sourceId));
      case 'follow_up':
        context.push(RoutePaths.followUpDetail(item.sourceId));
      // Notes/documents/allocations have no separate detail screen to
      // navigate to (§"Activity Navigation": "do not create duplicate
      // detail screens") — the tile itself already shows everything
      // available for them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerTimelineControllerProvider(widget.customerId));
    switch (state.status) {
      case TimelineListStatus.initial:
      case TimelineListStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator());
      case TimelineListStatus.error:
        return Text(state.errorMessage ?? 'Could not load the activity timeline.');
      case TimelineListStatus.empty:
        return const Text('No activity recorded yet.');
      case TimelineListStatus.refreshing:
      case TimelineListStatus.success:
      case TimelineListStatus.loadingMore:
        final visible = state.visibleItems;
        if (visible.isEmpty) return const Text('No activity for this filter.');
        return Column(
          children: [
            ...visible.map((i) => ActivityTile(item: i, onTap: () => _openActivity(i))),
            if (state.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: state.status == TimelineListStatus.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton(
                        onPressed: () => ref.read(customerTimelineControllerProvider(widget.customerId).notifier).loadMore(),
                        child: const Text('Load more'),
                      ),
              ),
          ],
        );
    }
  }
}
