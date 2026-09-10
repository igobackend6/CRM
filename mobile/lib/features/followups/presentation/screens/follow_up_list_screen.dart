import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/follow_up.dart';
import '../../domain/entities/follow_up_list_state.dart';
import '../providers/followup_providers.dart';

String formatFollowUpDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Follow-Up List (Phase 7 §2A) — workspace-scoped, loading/empty/error,
/// pull-to-refresh, load-more pagination. Mirrors LeadListScreen's
/// structure. No search box or FAB here: creation is lead-scoped (§2C —
/// there is no lead picker in this phase), reached from a lead's own
/// follow-up section instead.
class FollowUpListScreen extends ConsumerStatefulWidget {
  const FollowUpListScreen({super.key});

  @override
  ConsumerState<FollowUpListScreen> createState() => _FollowUpListScreenState();
}

class _FollowUpListScreenState extends ConsumerState<FollowUpListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(followUpListControllerProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(followUpListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(FollowUpListState state) {
    switch (state.status) {
      case FollowUpListStatus.initial:
      case FollowUpListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case FollowUpListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load follow-ups.',
          onRetry: () => ref.read(followUpListControllerProvider.notifier).refresh(),
        );

      case FollowUpListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(followUpListControllerProvider.notifier).refresh(),
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.event_note_outlined, message: 'No follow-ups yet.'),
            ],
          ),
        );

      case FollowUpListStatus.success:
      case FollowUpListStatus.refreshing:
      case FollowUpListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => ref.read(followUpListControllerProvider.notifier).refresh(),
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
              return _FollowUpTile(followUp: state.items[index]);
            },
          ),
        );
    }
  }
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.followUp});

  final FollowUp followUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EntityListTile(
      avatarName: followUp.lead.name,
      title: followUp.lead.name,
      onTap: () => context.push(RoutePaths.followUpDetail(followUp.id)),
      trailing: AppStatusChip.forFollowUpStatus(status: followUp.status, isOverdue: followUp.isOverdue),
      metaItems: [
        MetaItem(Icons.category_outlined, followUp.type),
        MetaItem(
          followUp.isOverdue ? Icons.warning_amber_outlined : Icons.schedule_outlined,
          formatFollowUpDateTime(followUp.dueAt),
          color: followUp.isOverdue ? theme.colorScheme.error : null,
        ),
        MetaItem(Icons.person_outline, followUp.assignedMember?.fullName ?? 'Unassigned'),
      ],
    );
  }
}
