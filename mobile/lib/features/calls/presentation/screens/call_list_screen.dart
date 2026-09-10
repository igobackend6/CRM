import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/call.dart';
import '../../domain/entities/call_list_state.dart';
import '../controllers/call_list_controller.dart';
import '../providers/call_providers.dart';

String formatCallDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Call Log (Phase 9 §2) — workspace-scoped, loading/empty/error,
/// pull-to-refresh, load-more pagination. Mirrors FollowUpListScreen's
/// structure. No search box or FAB here: creation is lead-scoped (§4 —
/// there is no lead picker this phase), reached from a lead's own Calls
/// section instead. Optionally scoped to one lead (`leadId`) — Lead
/// Detail's "View all calls" (§6) pushes this screen with a leadId
/// rather than opening a second list implementation.
class CallListScreen extends ConsumerStatefulWidget {
  const CallListScreen({super.key, this.leadId});

  final String? leadId;

  @override
  ConsumerState<CallListScreen> createState() => _CallListScreenState();
}

class _CallListScreenState extends ConsumerState<CallListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _notifier.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  CallListController get _notifier => widget.leadId == null
      ? ref.read(callListControllerProvider.notifier)
      : ref.read(leadCallListControllerProvider(widget.leadId!).notifier);

  @override
  Widget build(BuildContext context) {
    final state =
        widget.leadId == null ? ref.watch(callListControllerProvider) : ref.watch(leadCallListControllerProvider(widget.leadId!));

    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(CallListState state) {
    switch (state.status) {
      case CallListStatus.initial:
      case CallListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case CallListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load calls.',
          onRetry: () => _notifier.refresh(),
        );

      case CallListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => _notifier.refresh(),
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.call_outlined, message: 'No calls logged yet.'),
            ],
          ),
        );

      case CallListStatus.success:
      case CallListStatus.refreshing:
      case CallListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => _notifier.refresh(),
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
              return CallTile(call: state.items[index], showLeadName: widget.leadId == null);
            },
          ),
        );
    }
  }
}

/// Shared by the global call log, Lead Detail's Calls section, and
/// Customer 360's Calls section — one tile widget, not three copies.
class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.call, this.showLeadName = true});

  final Call call;
  final bool showLeadName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.push(RoutePaths.callDetail(call.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.12),
                  child: Icon(call.isInbound ? Icons.call_received : Icons.call_made, size: 16, color: theme.colorScheme.secondary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(showLeadName ? call.lead.name : call.direction, style: theme.textTheme.titleMedium)),
                if (call.outcome != null)
                  AppStatusChip.forCallOutcome(name: call.outcome!.name, isPositive: call.outcome!.isPositive),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.schedule_outlined, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(formatCallDateTime(call.startedAt), style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(call.formattedDuration, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(call.agentMember?.fullName ?? 'Unknown', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
