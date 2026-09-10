import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/message_list_state.dart';
import '../../domain/repositories/messaging_repository.dart';

/// Conversation Detail (Phase 16 §"Conversation Detail") — message
/// history + pagination + a send action, `.family`-scoped per
/// conversationId. Same load-on-workspace-context pattern as
/// `CallDetailController`/`FollowUpDetailController` (listens for
/// workspace selection rather than loading unconditionally in the
/// constructor — the workspace may not be selected yet on the very
/// first build), then marks the conversation read once the first page
/// has loaded (§"mark conversation read" — the simplest correct trigger
/// for "the user opened this conversation").
class MessageListController extends StateNotifier<MessageListState> with RealtimeRefreshMixin<MessageListState> {
  MessageListController(this._repository, this._ref, this._conversationId) : super(const MessageListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) load();
    }, fireImmediately: true);
    // Phase 21B — filtered to this open conversation only (never
    // subscribes across conversations the caller can't see — the shared
    // stream itself is already workspace-scoped and RLS-filtered
    // upstream, see RealtimeChannelManager).
    subscribeRealtime(_ref, const {'messages'}, _onRealtimeEvent);
  }

  final MessagingRepository _repository;
  final Ref _ref;
  final String _conversationId;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    if (event.record['conversation_id'] != _conversationId && event.oldRecord['conversation_id'] != _conversationId) return;

    if (event.type == RealtimeEventType.update) {
      // A read-state change (someone else's "mark read") on a message
      // already loaded — patch it in place, no fetch needed.
      final id = event.id;
      final idx = state.items.indexWhere((m) => m.id == id);
      if (idx == -1) return;
      final readAtRaw = event.record['read_at'] as String?;
      final updated = state.items[idx].copyWith(readAt: readAtRaw != null ? DateTime.parse(readAtRaw) : null);
      final items = [...state.items];
      items[idx] = updated;
      state = state.copyWith(items: items);
      return;
    }

    if (event.type == RealtimeEventType.insert) {
      // Debounced tail-sync rather than hand-decoding the raw payload:
      // `Message.fromJson` needs the sender's resolved name
      // (`sender_member`), which the raw row doesn't carry, so this
      // reuses the existing, already-enriched `listMessages` — fetching
      // only what's missing after what's already loaded, never the full
      // history (STEP 7 "avoid unnecessary full-history reloads").
      debouncedRealtimeRefresh(_syncTail, duration: const Duration(milliseconds: 300));
    }
  }

  Future<void> _syncTail() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    try {
      final page = await _repository.listMessages(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        conversationId: _conversationId,
        limit: 20,
        offset: state.items.length,
      );
      final existingIds = state.items.map((m) => m.id).toSet();
      final fresh = page.items.where((m) => !existingIds.contains(m.id)).toList();
      if (fresh.isEmpty) return;
      state = state.copyWith(status: MessageListStatus.success, items: [...state.items, ...fresh], total: page.total);
      unawaited(markRead());
    } catch (e) {
      AppLogger.error('Failed to sync new messages for conversation $_conversationId', error: e);
    }
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(_syncTail);

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: MessageListStatus.loading, clearError: true);
    try {
      final page = await _repository.listMessages(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        conversationId: _conversationId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? MessageListStatus.empty : MessageListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
      unawaited(markRead());
    } on AppException catch (e) {
      state = state.copyWith(status: MessageListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load messages', error: e);
      state = state.copyWith(status: MessageListStatus.error, errorMessage: 'Could not load messages.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == MessageListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: MessageListStatus.loadingMore);
    try {
      final page = await _repository.listMessages(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        conversationId: _conversationId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: MessageListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: MessageListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more messages', error: e);
      state = state.copyWith(status: MessageListStatus.success, errorMessage: 'Could not load more messages.');
    }
  }

  /// Returns true on success so the composer knows whether to clear its
  /// text field (§"Conversation Detail": composer + send button).
  /// Blank/whitespace-only text is rejected here too, not just by the
  /// UI's disabled send button — a defensive second check, same
  /// "never trust the UI alone" spirit as every server-side validation
  /// in this codebase, even though this one is client-side.
  Future<bool> sendMessage(String body) async {
    final text = body.trim();
    if (text.isEmpty) return false;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;

    state = state.copyWith(sending: true, clearError: true);
    try {
      final message = await _repository.sendMessage(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        conversationId: _conversationId,
        body: text,
      );
      state = state.copyWith(
        status: MessageListStatus.success,
        items: [...state.items, message],
        total: state.total + 1,
        sending: false,
      );
      return true;
    } on AppException catch (e) {
      state = state.copyWith(sending: false, errorMessage: e.message);
      return false;
    } catch (e) {
      AppLogger.error('Failed to send message', error: e);
      state = state.copyWith(sending: false, errorMessage: 'Could not send the message.');
      return false;
    }
  }

  Future<void> markRead() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    try {
      await _repository.markConversationRead(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        conversationId: _conversationId,
      );
    } catch (e) {
      // Read-state is a courtesy, not the primary operation (same
      // "never let a side effect fail the request that triggered it"
      // spirit as the backend's own notify() swallowing its errors).
      AppLogger.error('Failed to mark conversation read', error: e);
    }
  }

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }
}
