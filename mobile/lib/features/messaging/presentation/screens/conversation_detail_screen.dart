import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/message_list_state.dart';
import '../controllers/message_list_controller.dart';
import '../providers/messaging_providers.dart';

String _formatMessageTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Conversation Detail (Phase 16 §"Conversation Detail") — message
/// history, sender/timestamp/body, current user's messages visually
/// differentiated, loading/empty/error, pagination, composer with a
/// send button disabled for empty/whitespace-only text.
class ConversationDetailScreen extends ConsumerStatefulWidget {
  const ConversationDetailScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends ConsumerState<ConversationDetailScreen> {
  final _textController = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final canSend = _textController.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  MessageListController get _notifier => ref.read(messageListControllerProvider(widget.conversationId).notifier);

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    final ok = await _notifier.sendMessage(text);
    if (!mounted) return;
    if (ok) {
      _textController.clear();
    } else {
      final message = ref.read(messageListControllerProvider(widget.conversationId)).errorMessage ?? 'Could not send the message.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messageListControllerProvider(widget.conversationId));
    final currentMemberId = ref.watch(workspaceControllerProvider).selected?.memberId;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Conversation')),
      body: Column(
        children: [
          Expanded(child: _buildMessages(state, currentMemberId)),
          const Divider(height: 1),
          _Composer(
            controller: _textController,
            canSend: _canSend,
            sending: state.sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(MessageListState state, String? currentMemberId) {
    switch (state.status) {
      case MessageListStatus.initial:
      case MessageListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case MessageListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load messages.',
          onRetry: () => _notifier.load(),
        );

      case MessageListStatus.empty:
        return const EmptyStateView(icon: Icons.forum_outlined, message: 'No messages yet. Say hello!');

      case MessageListStatus.success:
      case MessageListStatus.refreshing:
      case MessageListStatus.loadingMore:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (state.hasMore)
              Center(
                child: state.status == MessageListStatus.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : OutlinedButton(onPressed: () => _notifier.loadMore(), child: const Text('Load earlier messages')),
              ),
            ...state.items.map(
              (m) => _MessageBubble(message: m, isMine: currentMemberId != null && m.senderMember.id == currentMemberId),
            ),
          ],
        );
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(message.senderMember.displayName, style: theme.textTheme.labelSmall),
              ),
            Text(message.body),
            const SizedBox(height: 2),
            Text(_formatMessageTime(message.createdAt), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Message composer — send button disabled for empty/whitespace-only
/// text (§"Conversation Detail").
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.canSend, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool canSend;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Type a message…', isDense: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: (canSend && !sending) ? onSend : null,
              icon: sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
