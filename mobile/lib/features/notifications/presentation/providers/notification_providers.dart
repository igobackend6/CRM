import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/notification_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/notification_repository_impl.dart';
import '../../domain/entities/notification_list_state.dart';
import '../../domain/repositories/notification_repository.dart';
import '../controllers/notification_list_controller.dart';

final notificationApiDataSourceProvider = Provider<NotificationApiDataSource>((ref) => DioNotificationApiDataSource());

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(ref.watch(notificationApiDataSourceProvider));
});

final notificationListControllerProvider = StateNotifierProvider.autoDispose<NotificationListController, NotificationListState>((ref) {
  return NotificationListController(ref.watch(notificationRepositoryProvider), ref);
});

/// Unread count for the shell's app bar badge (Phase 10 §3's "lightweight
/// notification entry point") — a small, cheap `limit: 1` unread-filtered
/// query, reading its `total` rather than adding a second, dedicated
/// "unread count" endpoint the backend doesn't otherwise need (§13: no
/// duplicate API layers). Recomputed whenever the workspace changes;
/// the notifications list screen also refreshes it on pull-to-refresh
/// via `ref.invalidate` so the badge doesn't go stale after visiting
/// the inbox.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return 0;
  final repository = ref.watch(notificationRepositoryProvider);
  final page = await repository.listNotifications(
    accessToken: user.accessToken,
    workspaceId: workspace.workspace.id,
    isRead: false,
    limit: 1,
    offset: 0,
  );
  return page.total;
});
