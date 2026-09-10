import 'package:mobile/services/api/notification_api_data_source.dart';

/// Records the arguments of the last call to each method (so tests can
/// assert on what was sent) and returns whatever the test configured, or
/// throws [errorToThrow] if set. Mirrors fake_call_api_data_source.dart.
class FakeNotificationApiDataSource implements NotificationApiDataSource {
  Map<String, dynamic> listNotificationsResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> markReadResponse = const {};
  Map<String, dynamic> markAllReadResponse = const {'updated': 0};

  Object? errorToThrow;

  int? lastOffset;
  bool? lastIsRead;
  String? lastMarkReadId;
  bool? lastMarkReadValue;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastOffset = offset;
    lastIsRead = isRead;
    return listNotificationsResponse;
  }

  @override
  Future<Map<String, dynamic>> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  }) async {
    _maybeThrow();
    lastMarkReadId = notificationId;
    lastMarkReadValue = isRead;
    return markReadResponse;
  }

  @override
  Future<Map<String, dynamic>> markAllRead({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return markAllReadResponse;
  }
}
