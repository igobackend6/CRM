import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/conversation_list_state.dart';
import '../../domain/repositories/messaging_repository.dart';

/// Conversation List (Phase 16 §"Conversation List") — loading/success/
/// empty/error + pull-to-refresh + offset-pagination. Mirrors
/// CallListController's structure exactly (§"reuse existing feature/
/// provider/controller patterns").
class ConversationListController extends StateNotifier<ConversationListState> with RealtimeRefreshMixin<ConversationListState> {
  ConversationListController(this._repository, this._ref) : super(const ConversationListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — `conversations` itself isn't published (see
    // 000023_realtime_messages.sql's comment); a `messages` insert is
    // already the right signal, since it's the only thing that changes
    // this list's ordering/preview/unread-count.
    subscribeRealtime(_ref, const {'messages'}, (_) => debouncedRealtimeRefresh(refresh));
  }

  final MessagingRepository _repository;
  final Ref _ref;

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(refresh);

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == ConversationListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? ConversationListStatus.loading : ConversationListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listConversations(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? ConversationListStatus.empty : ConversationListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: ConversationListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load conversations', error: e);
      state = state.copyWith(status: ConversationListStatus.error, errorMessage: 'Could not load conversations.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == ConversationListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: ConversationListStatus.loadingMore);
    try {
      final page = await _repository.listConversations(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: ConversationListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      // Keep the already-loaded items visible; only surface the error.
      state = state.copyWith(status: ConversationListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more conversations', error: e);
      state = state.copyWith(status: ConversationListStatus.success, errorMessage: 'Could not load more conversations.');
    }
  }
}
