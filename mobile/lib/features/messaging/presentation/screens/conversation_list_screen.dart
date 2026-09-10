import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_list_state.dart';
import '../providers/messaging_providers.dart';

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Conversation List (Phase 16 §"Conversation List") — workspace-scoped,
/// loading/empty/error, pull-to-refresh, load-more pagination. Mirrors
/// CallListScreen's structure exactly (§"reuse existing architecture/
/// conventions").
class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(conversationListControllerProvider.notifier).loadMore();
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
    final state = ref.watch(conversationListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(ConversationListState state) {
    switch (state.status) {
      case ConversationListStatus.initial:
      case ConversationListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case ConversationListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load conversations.',
          onRetry: () => ref.read(conversationListControllerProvider.notifier).refresh(),
        );

      case ConversationListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => ref.read(conversationListControllerProvider.notifier).refresh(),
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.forum_outlined, message: 'No conversations yet.'),
            ],
          ),
        );

      case ConversationListStatus.success:
      case ConversationListStatus.refreshing:
      case ConversationListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: () => ref.read(conversationListControllerProvider.notifier).refresh(),
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
              return ConversationTile(conversation: state.items[index]);
            },
          ),
        );
    }
  }
}

/// One row of the conversation list — lead name, latest message
/// preview, timestamp, unread badge (§"Conversation List").
class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.push(RoutePaths.messageDetail(conversation.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            InitialsAvatar(name: conversation.lead.name, size: 40),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conversation.lead.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    conversation.latestMessagePreview ?? 'No messages yet.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (conversation.latestMessageAt != null)
                  Text(_formatDateTime(conversation.latestMessageAt!), style: theme.textTheme.bodySmall),
                if (conversation.hasUnread) ...[
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
