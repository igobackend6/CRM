import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../pipeline/presentation/providers/pipeline_providers.dart';
import '../../domain/allocation_range.dart';
import '../../domain/lead_list_mode.dart';
import '../../domain/entities/bulk_action_result.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_bulk_action.dart';
import '../../domain/entities/lead_filters.dart';
import '../../domain/entities/lead_import_state.dart';
import '../../domain/entities/lead_list_state.dart';
import '../../domain/entities/lead_status.dart';
import '../../domain/entities/member_summary.dart';
import '../controllers/lead_import_controller.dart';
import '../controllers/lead_list_controller.dart';
import '../providers/allocations_providers.dart';
import '../providers/leads_providers.dart';
import '../widgets/allocation_range_chips.dart';
import '../widgets/allocations_empty_view.dart';
import '../widgets/allocations_header.dart';
import '../widgets/lead_contact_actions.dart';

/// The paged lead list behind two tabs (Phase 5 §2's Lead List, restyled to the reference).
///
/// * **Allocations** ([LeadListMode.allocations]): every lead the member can see. A plain title with a
///   search icon, the date chips and an illustrated empty state. Leads an admin assigns from the admin
///   web land here through the same `leads` rows: RLS `leads_select` shows a member everything assigned
///   to them or created by them, and they can still add their own.
/// * **Customers** ([LeadListMode.customers]): the same list narrowed to converted leads, with the full
///   header (status selector, search, filters, pipeline board, more) and rows that open Customer 360.
///
/// Search, loading/empty/error, pull-to-refresh, basic pagination (load-more on scroll). Phase 13 adds
/// bulk selection/actions and a CSV import entry point on top of this same screen (§"Extend the existing
/// Leads/Pipeline UI rather than creating a separate data-management architecture").
class LeadListScreen extends ConsumerStatefulWidget {
  const LeadListScreen({super.key, this.mode = LeadListMode.allocations});

  final LeadListMode mode;

  @override
  ConsumerState<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends ConsumerState<LeadListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _searchOpen = false;

  bool get _isCustomers => widget.mode == LeadListMode.customers;

  /// The controller behind this tab: the customers tab has its own, with `isCustomer` pinned.
  AutoDisposeStateNotifierProvider<LeadListController, LeadListState> get _provider =>
      _isCustomers ? customerListControllerProvider : leadListControllerProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(_provider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen && _searchController.text.isNotEmpty) {
      _searchController.clear();
      ref.read(_provider.notifier).updateSearch('');
    }
  }

  Future<void> _pickCustomRange(BuildContext context, LeadFilters filters) async {
    final now = DateTime.now();
    final from = filters.createdFrom;
    final to = filters.createdTo;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: from != null && to != null ? DateTimeRange(start: from, end: to) : null,
    );
    if (picked == null || !mounted) return;
    await ref.read(_provider.notifier).applyFilters(
          filters.withDates(from: DateTime(picked.start.year, picked.start.month, picked.start.day), to: endOfDay(picked.end)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);

    return Scaffold(
      appBar: state.selectionMode
          ? _buildSelectionAppBar(context, state)
          : (_isCustomers ? _buildHeader(context, state) : _buildTitleHeader()),
      body: Column(
        children: [
          if (!state.selectionMode) ...[
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, phone, or email',
                    isDense: true,
                  ),
                  onChanged: (value) => ref.read(_provider.notifier).updateSearch(value),
                ),
              ),
            if (!_isCustomers) _buildRangeChips(context, state),
          ],
          Expanded(child: _buildBody(state)),
        ],
      ),
      floatingActionButton: state.selectionMode
          ? null
          : (_isCustomers
              // Opens the same create-lead form Allocations uses, not a separate "create customer" flow:
              // there is no direct-to-customer create in this data model (a lead becomes a customer
              // through conversion, a business event with its own gate; see leads.is_customer's CHECK
              // constraint in 000008_leads.sql). Its own hero tag because both tabs are alive at once.
              ? FloatingActionButton(
                  heroTag: 'customers-create-lead',
                  tooltip: 'New lead',
                  onPressed: () => context.push(RoutePaths.leadCreate),
                  child: const Icon(Icons.add),
                )
              : FloatingActionButton(
                  onPressed: () => context.push(RoutePaths.leadCreate),
                  tooltip: 'Add lead',
                  child: const Icon(Icons.add),
                )),
    );
  }

  Widget _buildRangeChips(BuildContext context, LeadListState state) {
    final notifier = ref.read(_provider.notifier);
    final filters = state.filters;
    return AllocationRangeChips(
      selected: allocationRangeOf(filters, DateTime.now()),
      customLabel: allocationRangeLabel(filters),
      onOverall: () => notifier.applyFilters(filters.withDates()),
      onLast30Days: () => notifier.applyFilters(filters.withDates(from: last30DaysStart(DateTime.now()))),
      onSelectRange: () => _pickCustomRange(context, filters),
    );
  }

  PreferredSizeWidget _buildHeader(BuildContext context, LeadListState state) {
    final statuses = ref.watch(leadReferenceDataProvider).valueOrNull?.statuses ?? const <LeadStatus>[];
    final total = ref.watch(customersTotalProvider).valueOrNull;
    return AllocationsHeader(
      searchTooltip: 'Search customers',
      statuses: statuses,
      selectedStatusId: state.filters.statusId,
      shownCount: state.total,
      totalCount: total,
      // The status is shown by the selector and the customer flag is what this tab is, so neither
      // counts toward the filter badge.
      activeFilterCount: state.filters.activeCount - (state.filters.statusId != null ? 1 : 0) - (state.filters.isCustomer != null ? 1 : 0),
      searchOpen: _searchOpen,
      onStatusSelected: (id) => ref.read(_provider.notifier).applyFilters(state.filters.withStatus(id)),
      onToggleSearch: _toggleSearch,
      onOpenFilters: () => _openFilterSheet(context),
      // Phase 12's pipeline board: one entry point from the existing
      // Lead List header, no shell redesign.
      onOpenPipeline: () => context.push(RoutePaths.pipeline),
      onMenuAction: (action) {
        switch (action) {
          case AllocationsMenuAction.select:
            ref.read(_provider.notifier).enterSelectionMode();
          case AllocationsMenuAction.importCsv:
            _openImportSheet(context);
        }
      },
    );
  }

  PreferredSizeWidget _buildTitleHeader() => AllocationsTitleHeader(searchOpen: _searchOpen, onToggleSearch: _toggleSearch);

  Future<void> _openFilterSheet(BuildContext context) async {
    final current = ref.read(_provider).filters;
    final result = await showModalBottomSheet<LeadFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initialFilters: current, showCustomerFilter: !_isCustomers),
    );
    if (result == null || !context.mounted) return;
    // Clear all / a loaded saved view must not un-pin the customer flag on the Customers tab.
    await ref.read(_provider.notifier).applyFilters(_isCustomers ? result.withIsCustomer(true) : result);
  }

  AppBar _buildSelectionAppBar(BuildContext context, LeadListState state) {
    final notifier = ref.read(_provider.notifier);
    return brandAppBar(
      leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: notifier.exitSelectionMode),
      title: Text('${state.selectedIds.length} selected'),
      actions: [
        IconButton(icon: const Icon(Icons.select_all), tooltip: 'Select all visible', onPressed: notifier.selectAllVisible),
        IconButton(
          icon: const Icon(Icons.deselect),
          tooltip: 'Clear selection',
          onPressed: state.selectedIds.isEmpty ? null : notifier.clearSelection,
        ),
        PopupMenuButton<LeadBulkAction>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Bulk actions',
          enabled: state.selectedIds.isNotEmpty,
          onSelected: (action) => _handleBulkAction(context, action),
          itemBuilder: (context) => [
            for (final action in LeadBulkAction.values) PopupMenuItem(value: action, child: Text(action.label)),
          ],
        ),
      ],
    );
  }

  Future<void> _handleBulkAction(BuildContext context, LeadBulkAction action) async {
    String? memberId;
    String? statusId;

    switch (action) {
      case LeadBulkAction.assign:
        memberId = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _BulkMemberPickerSheet());
        if (memberId == null) return;
      case LeadBulkAction.unassign:
        break;
      case LeadBulkAction.changeStatus:
        statusId = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _BulkStatusPickerSheet());
        if (statusId == null) return;
    }

    if (!context.mounted) return;
    final result = await ref
        .read(_provider.notifier)
        .runBulkAction(action: action, memberId: memberId, statusId: statusId);
    if (!context.mounted) return;

    if (result == null) {
      final message = ref.read(_provider).errorMessage ?? 'Could not complete the bulk action.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    // The pipeline groups the same leads by status — a bulk action can
    // change status/assignment/existence for any of them, so it needs to
    // reload next time it's viewed (same "refresh existing lead/pipeline
    // data" rule as the single-lead status change in pipeline_screen.dart,
    // just triggered from the other screen this time).
    ref.invalidate(pipelineControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_summarize(action, result))));
  }

  String _summarize(LeadBulkAction action, BulkActionResult result) {
    final base = '${result.succeeded} of ${result.total} leads updated';
    return result.failed == 0 ? '$base.' : '$base (${result.failed} failed).';
  }

  Future<void> _openImportSheet(BuildContext context) async {
    final shouldRefresh = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => const _ImportSheet(),
    );
    if (shouldRefresh == true) {
      ref.invalidate(leadListControllerProvider);
      ref.invalidate(customerListControllerProvider);
      ref.invalidate(pipelineControllerProvider);
    }
  }

  Widget _buildBody(LeadListState state) {
    switch (state.status) {
      case LeadListStatus.initial:
      case LeadListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case LeadListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load leads.',
          onRetry: () => ref.read(_provider.notifier).refresh(),
        );

      case LeadListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(_provider.notifier).refresh(),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: _buildEmpty(state),
              ),
            ),
          ),
        );

      case LeadListStatus.success:
      case LeadListStatus.refreshing:
      case LeadListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => ref.read(_provider.notifier).refresh(),
          child: ListView.separated(
            controller: _scrollController,
            itemCount: state.items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return _buildLeadRow(state, state.items[index]);
            },
          ),
        );
    }
  }

  Widget _buildEmpty(LeadListState state) {
    final noun = _isCustomers ? 'customers' : 'leads';
    if (state.searchQuery.isNotEmpty) {
      return AllocationsEmptyView(title: 'No $noun match "${state.searchQuery}".');
    }
    final statusId = state.filters.statusId;
    final statuses = ref.read(leadReferenceDataProvider).valueOrNull?.statuses ?? const <LeadStatus>[];
    final selected = statusId == null ? null : statuses.where((s) => s.id == statusId).firstOrNull;
    // The customer flag is part of what the Customers tab is, so it is not a "filter" here.
    final otherFilters = state.filters.withStatus(null).withIsCustomer(null).isNotEmpty;

    if (selected != null && !otherFilters) return AllocationsEmptyView(title: 'No $noun with status "${selected.name}"');
    if (otherFilters || selected != null) return AllocationsEmptyView(title: 'No $noun match your filters.');

    if (_isCustomers) {
      return const AllocationsEmptyView(
        title: 'No customers yet',
        hint: 'A lead becomes a customer once it is converted. Convert a lead and it will show up here.',
      );
    }
    return const AllocationsEmptyView(
      title: 'No allocations found',
      hint: 'Admins can allocate new customers via bulk upload or data source integration from the admin web. '
          'You can also add a lead yourself with the + button.',
    );
  }

  Widget _buildLeadRow(LeadListState state, Lead lead) {
    final selectionMode = state.selectionMode;
    final notifier = ref.read(_provider.notifier);
    final tile = _LeadTile(
      lead: lead,
      onTap: selectionMode
          ? () => notifier.toggleSelection(lead.id)
          : () => context.push(_isCustomers ? RoutePaths.customerDetail(lead.id) : RoutePaths.leadDetail(lead.id)),
    );
    if (!selectionMode) return tile;
    return Row(
      children: [
        Checkbox(value: state.selectedIds.contains(lead.id), onChanged: (_) => notifier.toggleSelection(lead.id)),
        Expanded(child: tile),
      ],
    );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.lead, required this.onTap});

  final Lead lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = lead.status;
    return EntityListTile(
      avatarName: lead.name,
      title: lead.name,
      onTap: onTap,
      trailing: LeadRowTrailing(phone: lead.phone, leadId: lead.id, leadName: lead.name, isCustomer: lead.isCustomer, chip: status == null ? null : AppStatusChip.forLeadStatus(name: status.name, stage: status.stage)),
      subtitle: [lead.phone, lead.email].where((v) => v != null && v.isNotEmpty).join(' • ').isEmpty
          ? null
          : [lead.phone, lead.email].where((v) => v != null && v.isNotEmpty).join(' • '),
      metaItems: [
        if (lead.source != null) MetaItem(Icons.source_outlined, lead.source!.name),
        MetaItem(Icons.person_outline, lead.assignedMember?.fullName ?? 'Unassigned'),
      ],
      trailingMeta: _formatDate(lead.createdAt),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Bulk-assign's member picker (Phase 13). Deliberately simpler than
/// lead_detail_screen.dart's `_AssignmentSheet` — no "current assignee"
/// checkmark (a bulk selection can span leads with different, or no,
/// current assignee) and no explicit "Unassign" row (that's its own top-
/// level bulk action).
class _BulkMemberPickerSheet extends ConsumerWidget {
  const _BulkMemberPickerSheet();

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
            Text('Assign to', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
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
                    itemBuilder: (context, index) => _MemberTile(member: members[index]),
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

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: InitialsAvatar(name: member.fullName, size: 36),
      title: Text(member.fullName ?? 'Unknown'),
      onTap: () => Navigator.pop(context, member.id),
    );
  }
}

/// Bulk change-status's status picker (Phase 13) — reuses
/// [leadReferenceDataProvider] (already loaded for the create/edit form
/// and the list filter) rather than issuing another statuses request.
class _BulkStatusPickerSheet extends ConsumerWidget {
  const _BulkStatusPickerSheet();

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
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('Could not load statuses.'),
                ),
                data: (reference) {
                  final statuses = reference.statuses;
                  if (statuses.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No statuses configured for this workspace.'),
                    );
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

/// CSV import entry point (Phase 13 §"CSV Import") — file selection,
/// upload, progress, and the server's row-level result summary, all in
/// one bottom sheet reached from the Lead List app bar.
class _ImportSheet extends ConsumerWidget {
  const _ImportSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leadImportControllerProvider);
    final notifier = ref.read(leadImportControllerProvider.notifier);

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
            Text('Import leads from CSV', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ..._content(context, state, notifier),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, LeadImportState state, LeadImportController notifier) {
    switch (state.status) {
      case LeadImportStatus.uploading:
        return const [
          Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
          Center(child: Text('Importing…')),
        ];

      case LeadImportStatus.success:
        final result = state.result!;
        return [
          Text('Imported ${result.created} of ${result.total} rows.'),
          if (result.failed > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('${result.failed} row(s) failed:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: result.errors.length,
                itemBuilder: (context, index) {
                  final rowError = result.errors[index];
                  return Text('Row ${rowError.row}: ${rowError.error}', style: Theme.of(context).textTheme.bodySmall);
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: () => Navigator.pop(context, result.created > 0), child: const Text('Done')),
        ];

      case LeadImportStatus.idle:
      case LeadImportStatus.error:
        return [
          if (state.errorMessage != null) ...[
            Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (state.fileName != null) ...[
            Text('Selected file: ${state.fileName}'),
            const SizedBox(height: AppSpacing.sm),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.attach_file),
            label: Text(state.fileName == null ? 'Choose CSV file' : 'Choose a different file'),
            onPressed: notifier.pickFile,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(onPressed: state.csvContent == null ? null : notifier.import, child: const Text('Import')),
        ];
    }
  }
}

/// Phase 14's filter bottom sheet — status/source/assignee/priority/
/// customer/date-range/tag selectors plus saved-view save/load/delete,
/// all reusing the reference-data providers Phase 5/6/13 already load
/// (no duplicate statuses/sources/members/tags requests). Edits stay
/// local to this sheet's own state until "Apply" — cancelling (back
/// button/backdrop tap) leaves the list's active filters untouched.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initialFilters, this.showCustomerFilter = true});

  final LeadFilters initialFilters;

  /// Hidden on the Customers tab, where every row is a customer by definition.
  final bool showCustomerFilter;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _statusId = widget.initialFilters.statusId;
  late String? _sourceId = widget.initialFilters.sourceId;
  late String? _assignedMemberId = widget.initialFilters.assignedMemberId;
  late String? _priority = widget.initialFilters.priority;
  late bool? _isCustomer = widget.initialFilters.isCustomer;
  late DateTime? _createdFrom = widget.initialFilters.createdFrom;
  late DateTime? _createdTo = widget.initialFilters.createdTo;
  late String? _tagId = widget.initialFilters.tagId;

  final _saveNameController = TextEditingController();
  bool _showSaveField = false;

  @override
  void dispose() {
    _saveNameController.dispose();
    super.dispose();
  }

  LeadFilters get _current => LeadFilters(
        statusId: _statusId,
        sourceId: _sourceId,
        assignedMemberId: _assignedMemberId,
        priority: _priority,
        isCustomer: _isCustomer,
        createdFrom: _createdFrom,
        createdTo: _createdTo,
        tagId: _tagId,
      );

  void _loadView(LeadFilters filters) {
    setState(() {
      _statusId = filters.statusId;
      _sourceId = filters.sourceId;
      _assignedMemberId = filters.assignedMemberId;
      _priority = filters.priority;
      _isCustomer = filters.isCustomer;
      _createdFrom = filters.createdFrom;
      _createdTo = filters.createdTo;
      _tagId = filters.tagId;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _createdFrom : _createdTo) ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() => isFrom ? _createdFrom = picked : _createdTo = picked);
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final referenceAsync = ref.watch(leadReferenceDataProvider);
    final membersAsync = ref.watch(workspaceMembersProvider);
    final tagsAsync = ref.watch(workspaceTagsProvider);
    final savedViews = ref.watch(savedViewsControllerProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
          bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filter leads', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                if (savedViews.isNotEmpty) ...[
                  Text('Saved views', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final view in savedViews)
                        InputChip(
                          label: Text(view.name),
                          onPressed: () => _loadView(view.filters),
                          onDeleted: () => ref.read(savedViewsControllerProvider.notifier).delete(view.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text('Status', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                referenceAsync.when(
                  loading: () => const _InlineLoading(),
                  error: (error, stackTrace) => const Text('Could not load statuses.'),
                  data: (reference) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any status'), selected: _statusId == null, onSelected: (_) => setState(() => _statusId = null)),
                      for (final status in reference.statuses)
                        ChoiceChip(
                          label: Text(status.name),
                          selected: _statusId == status.id,
                          onSelected: (_) => setState(() => _statusId = status.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Source', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                referenceAsync.when(
                  loading: () => const _InlineLoading(),
                  error: (error, stackTrace) => const Text('Could not load sources.'),
                  data: (reference) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any source'), selected: _sourceId == null, onSelected: (_) => setState(() => _sourceId = null)),
                      for (final source in reference.sources)
                        ChoiceChip(
                          label: Text(source.name),
                          selected: _sourceId == source.id,
                          onSelected: (_) => setState(() => _sourceId = source.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Assigned to', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                membersAsync.when(
                  loading: () => const _InlineLoading(),
                  error: (error, stackTrace) => const Text('Could not load members.'),
                  data: (members) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(
                        label: const Text('Any assignee'),
                        selected: _assignedMemberId == null,
                        onSelected: (_) => setState(() => _assignedMemberId = null),
                      ),
                      for (final member in members)
                        ChoiceChip(
                          label: Text(member.displayName),
                          selected: _assignedMemberId == member.id,
                          onSelected: (_) => setState(() => _assignedMemberId = member.id),
                        ),
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
                      ChoiceChip(
                        label: Text(priority),
                        selected: _priority == priority,
                        onSelected: (_) => setState(() => _priority = priority),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (widget.showCustomerFilter) ...[
                  Text('Customer', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any'), selected: _isCustomer == null, onSelected: (_) => setState(() => _isCustomer = null)),
                      ChoiceChip(
                        label: const Text('Customers only'),
                        selected: _isCustomer == true,
                        onSelected: (_) => setState(() => _isCustomer = true),
                      ),
                      ChoiceChip(
                        label: const Text('Non-customers only'),
                        selected: _isCustomer == false,
                        onSelected: (_) => setState(() => _isCustomer = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text('Created date', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isFrom: true),
                        child: Text(_createdFrom == null ? 'From date' : _formatDate(_createdFrom!)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isFrom: false),
                        child: Text(_createdTo == null ? 'To date' : _formatDate(_createdTo!)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Tags', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                tagsAsync.when(
                  loading: () => const _InlineLoading(),
                  error: (error, stackTrace) => const Text('Could not load tags.'),
                  data: (tags) => Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('Any tag'), selected: _tagId == null, onSelected: (_) => setState(() => _tagId = null)),
                      for (final tag in tags)
                        ChoiceChip(
                          label: Text(tag.name),
                          selected: _tagId == tag.id,
                          onSelected: (_) => setState(() => _tagId = tag.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_showSaveField) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('save_view_name_field'),
                          controller: _saveNameController,
                          decoration: const InputDecoration(hintText: 'View name', isDense: true),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: 'Confirm save',
                        onPressed: () {
                          ref.read(savedViewsControllerProvider.notifier).save(_saveNameController.text, _current);
                          setState(() {
                            _showSaveField = false;
                            _saveNameController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ] else
                  TextButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save current filters'),
                    onPressed: () => setState(() => _showSaveField = true),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, const LeadFilters.empty()),
                        child: const Text('Clear all'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _current),
                        child: const Text('Apply filters'),
                      ),
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

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
