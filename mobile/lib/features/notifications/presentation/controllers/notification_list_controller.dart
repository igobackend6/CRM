import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_list_state.dart';
import '../../domain/repositories/notification_repository.dart';

/// Notification inbox (Phase 10 §3) — loading/success/empty/error +
/// pull-to-refresh + offset-pagination + mark read/mark all read.
/// Same load-on-workspace-context pattern as CallListController/
/// FollowUpListController (reacts to workspace selection rather than
/// loading once at construction time, since selection can still be
/// resolving asynchronously). Reuses `resolveLeadContext` from the
/// leads feature (session + selected workspace, not lead-specific
/// despite its name/location — see its own docstring), same as every
/// other list controller in this app.
class NotificationListController extends StateNotifier<NotificationListState> with RealtimeRefreshMixin<NotificationListState> {
  NotificationListController(this._repository, this._ref) : super(const NotificationListState.initial()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) refresh();
    }, fireImmediately: true);
    // Phase 21B — `notifications_select` RLS already scopes every row
    // this client receives to `recipient_member_id = current_member_id`
    // (000014_rls_policies.sql), so every event on this stream is
    // already this member's own — nothing here re-derives or trusts a
    // client-side workspace/recipient check as the security boundary.
    // `AppNotification` is a direct, un-enriched read of `notifications`
    // (see its own docstring), so the raw payload can be decoded
    // straight into it — no repository round trip needed for a
    // brand-new notification to appear instantly.
    subscribeRealtime(_ref, const {'notifications'}, _onRealtimeEvent);
  }

  final NotificationRepository _repository;
  final Ref _ref;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    if (event.type == RealtimeEventType.delete) return; // notifications are never deleted
    final AppNotification notification;
    try {
      notification = AppNotification.fromJson(event.record);
    } catch (e) {
      AppLogger.warning('Could not decode a realtime notification payload: $e');
      return;
    }
    if (event.type == RealtimeEventType.insert) {
      if (state.items.any((n) => n.id == notification.id)) return; // duplicate/replay protection
      state = state.copyWith(
        status: NotificationListStatus.success,
        items: [notification, ...state.items],
        total: state.total + 1,
      );
    } else {
      // e.g. marked read from another device — replaceItem() is a safe
      // no-op if this notification isn't part of the currently loaded page.
      state = state.replaceItem(notification);
    }
  }

  @override
  void onRealtimeResync() => refresh();

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == NotificationListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? NotificationListStatus.loading : NotificationListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listNotifications(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? NotificationListStatus.empty : NotificationListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: NotificationListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load notifications', error: e);
      state = state.copyWith(status: NotificationListStatus.error, errorMessage: 'Could not load notifications.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == NotificationListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: NotificationListStatus.loadingMore);
    try {
      final page = await _repository.listNotifications(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: NotificationListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      // Keep the already-loaded items visible; only surface the error.
      state = state.copyWith(status: NotificationListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more notifications', error: e);
      state = state.copyWith(status: NotificationListStatus.success, errorMessage: 'Could not load more notifications.');
    }
  }

  /// Marks one notification read (or unread) and updates it in place —
  /// no full refresh, so scroll position and the rest of the loaded
  /// page are preserved. Silently ignored on failure (e.g. tapping a
  /// notification to navigate shouldn't be blocked by a mark-read
  /// hiccup) beyond logging — the item just stays in its previous state
  /// until the next refresh.
  Future<void> setRead(String notificationId, bool isRead) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    try {
      final updated = await _repository.markRead(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        notificationId: notificationId,
        isRead: isRead,
      );
      state = state.replaceItem(updated);
    } on AppException catch (e) {
      AppLogger.error('Failed to update notification $notificationId', error: e);
    } catch (e) {
      AppLogger.error('Failed to update notification $notificationId', error: e);
    }
  }

  Future<void> markAllRead() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    try {
      await _repository.markAllRead(accessToken: context.accessToken, workspaceId: context.workspaceId);
      state = state.markAllLoadedRead();
    } on AppException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to mark all notifications read', error: e);
      state = state.copyWith(errorMessage: 'Could not mark all notifications read.');
    }
  }

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }
}
