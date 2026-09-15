import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_list_state.dart';
import '../controllers/notification_list_controller.dart';
import '../providers/notification_providers.dart';

String formatNotificationDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Phase 10 §4 — resolves a notification's `relatedEntityType`/
/// `relatedEntityId` to one of the app's *existing* routes. Returns null
/// when the type is missing or unrecognized, in which case the
/// notification is shown but not tappable-to-navigate (§4 "If a
/// notification has no safely resolvable target, display it without
/// navigation. Do not create placeholder screens."). 'lead' covers
/// customer leads too — LeadDetailScreen already offers its own link
/// through to Customer 360 (`lead.isCustomer`) when relevant, so there
/// is no need to guess is_customer here just to pick a different route.
String? resolveNotificationRoute(AppNotification notification) {
  final id = notification.relatedEntityId;
  if (id == null) return null;
  switch (notification.relatedEntityType) {
    case 'lead':
      return RoutePaths.leadDetail(id);
    case 'follow_up':
      return RoutePaths.followUpDetail(id);
    case 'call':
      return RoutePaths.callDetail(id);
    case 'customer':
      return RoutePaths.customerDetail(id);
    default:
      return null;
  }
}

/// Notification inbox (Phase 10 §3) — workspace-scoped, loading/empty/
/// error, pull-to-refresh, load-more pagination. Mirrors CallListScreen's
/// structure. No create/detail screens: notifications are only ever
/// created server-side (§1/§9), and tapping one navigates straight to
/// the existing entity screen it refers to rather than a redundant
/// notification detail view.
class NotificationListScreen extends ConsumerStatefulWidget {
  const NotificationListScreen({super.key});

  @override
  ConsumerState<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends ConsumerState<NotificationListScreen> {
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

  NotificationListController get _notifier => ref.read(notificationListControllerProvider.notifier);

  Future<void> _refresh() async {
    await _notifier.refresh();
    // Keep the shell's badge in sync with whatever this refresh found,
    // instead of waiting for its own next rebuild.
    ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> _markAllRead() async {
    await _notifier.markAllRead();
    ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      unawaited(_notifier.setRead(notification.id, true));
      ref.invalidate(unreadNotificationCountProvider);
    }
    final route = resolveNotificationRoute(notification);
    if (route != null && mounted) {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(NotificationListState state) {
    switch (state.status) {
      case NotificationListStatus.initial:
      case NotificationListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case NotificationListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load notifications.',
          onRetry: _refresh,
        );

      case NotificationListStatus.empty:
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.notifications_none_outlined, message: 'No notifications yet.'),
            ],
          ),
        );

      case NotificationListStatus.success:
      case NotificationListStatus.refreshing:
      case NotificationListStatus.loadingMore:
        return RefreshIndicator(
          onRefresh: _refresh,
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
              return _NotificationTile(notification: state.items[index], onTap: () => _openNotification(state.items[index]));
            },
          ),
        );
    }
  }
}

/// Icon + color for a notification's category — `type` first (the
/// server-controlled CHECK-constrained set), falling back to
/// `relatedEntityType` for the 'system' events the follow-up/call hooks
/// use (Phase 10 §2 — there's no dedicated CHECK value for those).
(IconData, Color) _categoryVisual(BuildContext context, AppNotification notification) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (notification.type) {
    case 'lead_assigned':
      return (Icons.person_add_alt_outlined, colorScheme.secondary);
    case 'lead_reassigned':
      return (Icons.swap_horiz, colorScheme.secondary);
    case 'followup_reminder':
    case 'followup_overdue':
      return (Icons.event_note_outlined, colorScheme.error);
    default:
      switch (notification.relatedEntityType) {
        case 'follow_up':
          return (Icons.event_note_outlined, AppColors.accent);
        case 'call':
          return (Icons.call_outlined, colorScheme.tertiary);
        default:
          return (Icons.notifications_outlined, colorScheme.outline);
      }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    final canNavigate = resolveNotificationRoute(notification) != null;
    final (categoryIcon, categoryColor) = _categoryVisual(context, notification);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: categoryColor.withValues(alpha: 0.12),
              child: Icon(categoryIcon, size: 18, color: categoryColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: isUnread ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) : theme.textTheme.titleMedium,
                  ),
                  if (notification.body != null && notification.body!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(notification.body!, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined, size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(formatNotificationDateTime(notification.createdAt), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            if (canNavigate) Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
