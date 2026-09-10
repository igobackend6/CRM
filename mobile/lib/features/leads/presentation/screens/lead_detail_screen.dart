import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/widgets/lead_ai_section.dart';
import '../../../calls/presentation/providers/call_providers.dart';
import '../../../calls/presentation/screens/call_list_screen.dart' show CallTile;
import '../../../customer360/domain/entities/timeline_item.dart';
import '../../../customer360/domain/entities/timeline_list_state.dart';
import '../../../documents/presentation/widgets/documents_section.dart';
import '../../../followups/domain/entities/follow_up.dart';
import '../../../followups/presentation/providers/followup_providers.dart';
import '../../../messaging/presentation/widgets/messages_entry_button.dart';
import '../../../whatsapp/presentation/widgets/whatsapp_send_button.dart';
import '../../domain/entities/allocation.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_detail_state.dart';
import '../../domain/entities/tag.dart';
import '../controllers/lead_request_context.dart';
import '../providers/leads_providers.dart';

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Lead Details (Phase 5 §2) — lead info, status/source, assigned
/// member, created/updated, tags (§6), basic interaction history.
/// Phase 6 adds assignment (§2A) and allocation history (§2B). Phase 7
/// adds a follow-up section (§2B) without duplicating any lead state —
/// it only reads leadFollowUpsProvider(leadId), fetched lazily by this
/// screen.
class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leadDetailControllerProvider(leadId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead details'),
        actions: [
          if (state.status == LeadDetailStatus.success)
            IconButton(icon: const Icon(Icons.edit), onPressed: () => context.push(RoutePaths.leadEdit(leadId))),
        ],
      ),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, LeadDetailState state) {
    switch (state.status) {
      case LeadDetailStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case LeadDetailStatus.notFound:
        return const Center(child: Text('This lead could not be found.'));

      case LeadDetailStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => ref.read(leadDetailControllerProvider(leadId).notifier).load(),
        );

      case LeadDetailStatus.success:
        final lead = state.lead!;
        return RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.read(leadDetailControllerProvider(leadId).notifier).load(),
            ref.read(leadActivityControllerProvider(leadId).notifier).refresh(),
          ]),
          child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _LeadHeaderCard(lead: lead),
            const SizedBox(height: AppSpacing.sm),
            _CustomerBanner(leadId: leadId, lead: lead),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                MessagesEntryButton(leadId: leadId),
                WhatsAppSendButton(
                  leadName: lead.name,
                  leadPhone: lead.phone,
                  leadStatus: lead.status?.name,
                  assignedMemberName: lead.assignedMember?.fullName,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DetailInfoRow(label: 'Phone', value: lead.phone ?? '—'),
            DetailInfoRow(label: 'Email', value: lead.email ?? '—'),
            DetailInfoRow(label: 'Status', value: lead.status?.name ?? '—'),
            DetailInfoRow(label: 'Source', value: lead.source?.name ?? '—'),
            DetailInfoRow(label: 'Priority', value: lead.priority),
            _AssignmentRow(leadId: leadId, lead: lead),
            DetailInfoRow(label: 'Created by', value: lead.createdByMember?.fullName ?? '—'),
            DetailInfoRow(label: 'Created', value: _formatDateTime(lead.createdAt)),
            DetailInfoRow(label: 'Updated', value: _formatDateTime(lead.updatedAt)),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.sell_outlined, title: 'Tags'),
            const SizedBox(height: AppSpacing.sm),
            _TagsSection(leadId: leadId, tags: lead.tags),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.history_outlined, title: 'Assignment history'),
            const SizedBox(height: AppSpacing.sm),
            if (state.allocations.isEmpty)
              const EmptyStateView(icon: Icons.person_pin_circle_outlined, message: 'No assignment history yet.')
            else
              ...state.allocations.map((allocation) => _AllocationTile(allocation: allocation)),
            const SizedBox(height: AppSpacing.lg),
            _FollowUpsSectionHeader(leadId: leadId),
            const SizedBox(height: AppSpacing.sm),
            _FollowUpsSection(leadId: leadId),
            const SizedBox(height: AppSpacing.lg),
            _CallsSectionHeader(leadId: leadId),
            const SizedBox(height: AppSpacing.sm),
            _CallsSection(leadId: leadId),
            const SizedBox(height: AppSpacing.lg),
            DocumentsSection(leadId: leadId),
            const SizedBox(height: AppSpacing.lg),
            LeadAiSection(leadId: leadId),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(icon: Icons.timeline_outlined, title: 'Activity'),
            const SizedBox(height: AppSpacing.sm),
            _NoteComposer(leadId: leadId),
            const SizedBox(height: AppSpacing.sm),
            _ActivityFilterChipsSection(leadId: leadId),
            const SizedBox(height: AppSpacing.sm),
            _ActivitySection(leadId: leadId),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete lead'),
              onPressed: () => _confirmDelete(context, ref),
            ),
            ],
          ),
        );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this lead?'),
        content: const Text('This can only be reversed by an administrator.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref.read(leadDetailControllerProvider(leadId).notifier).deleteLead();
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(leadListControllerProvider);
      context.pop();
    } else {
      final message = ref.read(leadDetailControllerProvider(leadId)).errorMessage ?? 'Could not delete this lead.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Lead identity header — avatar + name + primary status chip in an
/// accent-bordered card (Phase 5 §2's headline `Text(lead.name)`
/// upgraded to the real "Call Summary"-card pattern —
/// docs/design/design-tokens.md). Still renders `lead.name` exactly
/// once, same as before (existing tests assert on that).
class _LeadHeaderCard extends StatelessWidget {
  const _LeadHeaderCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final status = lead.status;
    final accentColor = status == null
        ? null
        : (status.isWon ? AppColors.success : (status.isLost ? Theme.of(context).colorScheme.error : null));
    return AccentCard(
      accentColor: accentColor,
      child: Row(
        children: [
          InitialsAvatar(name: lead.name, size: 48),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead.name, style: Theme.of(context).textTheme.headlineSmall),
                if (status != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  AppStatusChip.forLeadStatus(name: status.name, stage: status.stage),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lead Detail -> Customer 360 navigation (Phase 8 §8), plus Phase 18's
/// "Convert to Customer" action. Exactly one of the two is ever shown:
/// a non-customer lead gets the convert button, a customer gets the
/// Customer 360 link — never both, never a silent/broken link either
/// way (the backend independently enforces the same rule: /convert
/// rejects an already-converted lead with 409, and /customers/{id}
/// 404s for a non-customer lead regardless of what the client shows).
class _CustomerBanner extends ConsumerStatefulWidget {
  const _CustomerBanner({required this.leadId, required this.lead});

  final String leadId;
  final Lead lead;

  @override
  ConsumerState<_CustomerBanner> createState() => _CustomerBannerState();
}

class _CustomerBannerState extends ConsumerState<_CustomerBanner> {
  bool _converting = false;

  @override
  Widget build(BuildContext context) {
    if (widget.lead.isCustomer) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.person_search_outlined, size: 18),
        label: const Text('View Customer 360'),
        onPressed: () => context.push(RoutePaths.customerDetail(widget.lead.id)),
      );
    }
    return OutlinedButton.icon(
      icon: _converting
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.person_add_alt_1_outlined, size: 18),
      label: const Text('Convert to Customer'),
      onPressed: _converting ? null : () => _confirmAndConvert(context),
    );
  }

  Future<void> _confirmAndConvert(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Convert to customer?'),
        content: Text('${widget.lead.name} will become a customer. Their existing history is kept as-is.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Convert')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _converting = true);
    final ok = await ref.read(leadDetailControllerProvider(widget.leadId).notifier).convertToCustomer();
    if (!mounted) return;
    setState(() => _converting = false);
    if (!context.mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lead converted to customer.')));
    } else {
      final message =
          ref.read(leadDetailControllerProvider(widget.leadId)).errorMessage ?? 'Could not convert this lead.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Current assignee + Assign/Reassign/Unassign action (Phase 6 §2A/§2C).
/// Always shown, regardless of the viewer's role — the backend/RLS is
/// the real permission boundary (Phase 6 §4); a failed attempt surfaces
/// as a "permission denied" error banner (see _AssignmentSheet), not a
/// hidden button.
class _AssignmentRow extends ConsumerWidget {
  const _AssignmentRow({required this.leadId, required this.lead});

  final String leadId;
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAssigned = lead.assignedMember != null;
    return DetailInfoRow(
      label: 'Assigned to',
      value: lead.assignedMember?.fullName ?? 'Unassigned',
      trailing: TextButton(
        onPressed: () => _openAssignmentSheet(context, ref),
        child: Text(isAssigned ? 'Change' : 'Assign'),
      ),
    );
  }

  Future<void> _openAssignmentSheet(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<_AssignmentChoice>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AssignmentSheet(currentAssigneeId: lead.assignedMember?.id),
    );
    if (selected == null) return;

    final ok = await ref.read(leadDetailControllerProvider(leadId).notifier).assignLead(selected.memberId);
    if (!context.mounted) return;
    if (!ok) {
      final message = ref.read(leadDetailControllerProvider(leadId)).errorMessage ?? 'Could not update the assignment.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// One row of the assignment-history list (Phase 6 §2B).
class _AllocationTile extends StatelessWidget {
  const _AllocationTile({required this.allocation});

  final Allocation allocation;

  @override
  Widget build(BuildContext context) {
    final from = allocation.previousMember?.fullName;
    final to = allocation.assignedMember?.fullName ?? 'Unassigned';
    final title = from == null ? 'Assigned to $to' : 'Reassigned from $from to $to';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(radius: 16, child: Icon(Icons.person_pin_circle_outlined, size: 16)),
      title: Text(title),
      subtitle: Text('By ${allocation.assignedBy?.fullName ?? 'Unknown'}'),
      trailing: Text(_formatDateTime(allocation.assignedAt), style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// "Add follow-up" — the create route's leadId query param is how the
/// form knows which lead this is for (Phase 7 §2C/§7: no lead picker
/// this phase).
class _FollowUpsSectionHeader extends StatelessWidget {
  const _FollowUpsSectionHeader({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      icon: Icons.event_note_outlined,
      title: 'Follow-ups',
      action: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add follow-up'),
        onPressed: () => context.push(RoutePaths.followUpCreateForLead(leadId)),
      ),
    );
  }
}

/// Lead Detail's follow-up section (Phase 7 §2B) — fetched only when
/// this screen is actually built (`leadFollowUpsProvider` is
/// `.family`-scoped per lead), not as part of every lead load.
class _FollowUpsSection extends ConsumerWidget {
  const _FollowUpsSection({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followUpsAsync = ref.watch(leadFollowUpsProvider(leadId));
    return followUpsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (error, stackTrace) => const Text('Could not load follow-ups.'),
      data: (followUps) {
        if (followUps.isEmpty) return const EmptyStateView(icon: Icons.event_note_outlined, message: 'No follow-ups yet.');
        return Column(children: followUps.map((f) => _FollowUpTile(followUp: f)).toList());
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
      subtitle: Text('${followUp.status} • ${followUp.assignedMember?.fullName ?? 'Unassigned'}'),
      onTap: () => context.push(RoutePaths.followUpDetail(followUp.id)),
    );
  }
}

/// "Log call" — the create route's leadId query param is how the form
/// knows which lead this is for (Phase 9 §4/§11: no lead picker this
/// phase, same convention as follow-up creation).
class _CallsSectionHeader extends StatelessWidget {
  const _CallsSectionHeader({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      icon: Icons.call_outlined,
      title: 'Calls',
      action: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Log call'),
        onPressed: () => context.push(RoutePaths.callCreateForLead(leadId)),
      ),
    );
  }
}

/// Lead Detail's Calls section (Phase 9 §6) — fetched only when this
/// screen is actually built (`leadCallsProvider` is `.family`-scoped
/// per lead), not as part of every lead load. Shows the lead's recent
/// calls with a "View all calls" link to the full, paginated,
/// lead-scoped call list (reuses CallListScreen — no second call-list
/// implementation).
class _CallsSection extends ConsumerWidget {
  const _CallsSection({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(leadCallsProvider(leadId));
    return callsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (error, stackTrace) => const Text('Could not load calls.'),
      data: (calls) {
        if (calls.isEmpty) return const EmptyStateView(icon: Icons.call_outlined, message: 'No calls logged yet.');
        final preview = calls.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...preview.map((c) => CallTile(call: c, showLeadName: false)),
            if (calls.length > preview.length)
              TextButton(
                onPressed: () => context.push(RoutePaths.callsForLead(leadId)),
                child: const Text('View all calls'),
              ),
          ],
        );
      },
    );
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection({required this.leadId, required this.tags});

  final String leadId;
  final List<Tag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...tags.map(
          (tag) => Chip(
            label: Text(tag.name),
            onDeleted: () => ref.read(leadDetailControllerProvider(leadId).notifier).removeTag(tag),
          ),
        ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add tag'),
          onPressed: () => _showAddTagSheet(context, ref),
        ),
      ],
    );
  }

  Future<void> _showAddTagSheet(BuildContext context, WidgetRef ref) async {
    final requestContext = resolveLeadContext(ref.read);
    if (requestContext == null) return;

    final repository = ref.read(leadRepositoryProvider);
    List<Tag> available = const [];
    try {
      available = await repository.listTags(accessToken: requestContext.accessToken, workspaceId: requestContext.workspaceId);
    } catch (_) {
      // Fall through with an empty list — the sheet still lets the user
      // create a brand-new tag.
    }
    final existingIds = tags.map((t) => t.id).toSet();
    final selectable = available.where((t) => !existingIds.contains(t.id)).toList();

    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<Tag>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddTagSheet(
        existingTags: selectable,
        onCreateNew: (name) async {
          final freshContext = resolveLeadContext(ref.read);
          if (freshContext == null) return null;
          try {
            return await repository.createTag(accessToken: freshContext.accessToken, workspaceId: freshContext.workspaceId, name: name);
          } catch (_) {
            return null;
          }
        },
      ),
    );

    if (chosen != null) {
      await ref.read(leadDetailControllerProvider(leadId).notifier).addTag(chosen);
    }
  }
}

class _AddTagSheet extends StatefulWidget {
  const _AddTagSheet({required this.existingTags, required this.onCreateNew});

  final List<Tag> existingTags;
  final Future<Tag?> Function(String name) onCreateNew;

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final _controller = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createAndSelect() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    final created = await widget.onCreateNew(name);
    if (!mounted) return;
    setState(() => _creating = false);
    if (created != null) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
          bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a tag', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (widget.existingTags.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Text('No existing tags yet.'))
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: widget.existingTags
                    .map((tag) => ActionChip(label: Text(tag.name), onPressed: () => Navigator.pop(context, tag)))
                    .toList(),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'New tag name', isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _creating ? null : _createAndSelect,
                  child: _creating
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The assignment picker's result. Distinguishes "chose Unassign"
/// (memberId: null) from "dismissed the sheet without choosing"
/// (showModalBottomSheet itself returns null in that case).
class _AssignmentChoice {
  const _AssignmentChoice(this.memberId);

  final String? memberId;
}

/// Member picker for lead assignment (Phase 6 §2A/§2C/§3). Reads
/// [workspaceMembersProvider], which is cached per workspace — opening
/// this sheet repeatedly does not re-fetch the member list every time
/// (Phase 6 §10).
class _AssignmentSheet extends ConsumerWidget {
  const _AssignmentSheet({required this.currentAssigneeId});

  final String? currentAssigneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(workspaceMembersProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assign lead', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (currentAssigneeId != null)
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Unassign'),
                onTap: () => Navigator.pop(context, const _AssignmentChoice(null)),
              ),
            Flexible(
              child: membersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('Could not load workspace members.'),
                ),
                data: (members) {
                  if (members.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No active workspace members found.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isCurrent = member.id == currentAssigneeId;
                      return ListTile(
                        leading: InitialsAvatar(name: member.fullName, size: 36),
                        title: Text(member.fullName ?? 'Unknown'),
                        trailing: isCurrent ? const Icon(Icons.check) : null,
                        onTap: isCurrent ? null : () => Navigator.pop(context, _AssignmentChoice(member.id)),
                      );
                    },
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

/// Phase 15 — minimal note-creation capability, also reachable from Lead
/// Detail now (previously Customer 360-only). Posts directly to
/// `/leads/{id}/notes` and prepends the result into the activity
/// section's already-loaded state, mirroring Customer 360's
/// `_NoteComposer` exactly.
class _NoteComposer extends ConsumerStatefulWidget {
  const _NoteComposer({required this.leadId});

  final String leadId;

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
      final repository = ref.read(leadRepositoryProvider);
      final item = await repository.createNote(
        accessToken: requestContext.accessToken,
        workspaceId: requestContext.workspaceId,
        leadId: widget.leadId,
        text: text,
      );
      ref.read(leadActivityControllerProvider(widget.leadId).notifier).prependItem(item);
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

class _ActivityFilterChipsSection extends ConsumerWidget {
  const _ActivityFilterChipsSection({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(leadActivityControllerProvider(leadId).select((s) => s.filter));
    return ActivityFilterChips(
      selected: filter,
      onChanged: (f) => ref.read(leadActivityControllerProvider(leadId).notifier).setFilter(f),
    );
  }
}

/// Phase 15's unified activity feed (calls/follow-ups/notes/allocations/
/// documents merged, newest first) — replaces the previous, Phase-5-only
/// "raw interactions" list with the same aggregation Customer 360 already
/// has (`LeadActivityController`/`GET /leads/{id}/activity`), so a
/// non-customer lead gets the same depth of activity history a customer
/// does. Lazy fetch + "load more" pagination, same pattern as
/// _FollowUpsSection/_CallsSection above.
class _ActivitySection extends ConsumerStatefulWidget {
  const _ActivitySection({required this.leadId});

  final String leadId;

  @override
  ConsumerState<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends ConsumerState<_ActivitySection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final state = ref.read(leadActivityControllerProvider(widget.leadId));
      if (state.status == TimelineListStatus.initial) {
        ref.read(leadActivityControllerProvider(widget.leadId).notifier).refresh();
      }
    });
  }

  void _openActivity(TimelineItem item) {
    switch (item.type) {
      case 'call':
        context.push(RoutePaths.callDetail(item.sourceId));
      case 'follow_up':
        context.push(RoutePaths.followUpDetail(item.sourceId));
      // Notes/documents/allocations have no separate detail screen
      // (§"Activity Navigation": "do not create duplicate detail
      // screens") — the tile already shows everything available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leadActivityControllerProvider(widget.leadId));
    switch (state.status) {
      case TimelineListStatus.initial:
      case TimelineListStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator());
      case TimelineListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load the activity feed.',
          onRetry: () => ref.read(leadActivityControllerProvider(widget.leadId).notifier).refresh(),
        );
      case TimelineListStatus.empty:
        return const EmptyStateView(icon: Icons.timeline_outlined, message: 'No activity recorded yet.');
      case TimelineListStatus.refreshing:
      case TimelineListStatus.success:
      case TimelineListStatus.loadingMore:
        final visible = state.visibleItems;
        if (visible.isEmpty) {
          return const EmptyStateView(icon: Icons.timeline_outlined, message: 'No activity for this filter.');
        }
        return Column(
          children: [
            ...visible.map((i) => ActivityTile(item: i, onTap: () => _openActivity(i))),
            if (state.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: state.status == TimelineListStatus.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton(
                        onPressed: () => ref.read(leadActivityControllerProvider(widget.leadId).notifier).loadMore(),
                        child: const Text('Load more'),
                      ),
              ),
          ],
        );
    }
  }
}
