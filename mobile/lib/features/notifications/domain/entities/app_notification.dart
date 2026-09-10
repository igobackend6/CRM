/// Mirrors the backend's `NotificationOut` shape
/// (backend/app/schemas/notifications.py), itself a direct read of
/// `notifications` (supabase/migrations/000011_notifications_audit.sql)
/// — unlike Call/FollowUp there is no enriched lead/member summary
/// here: `relatedEntityType`/`relatedEntityId` are an intentionally
/// unconstrained polymorphic reference (the table's own comment), so
/// this app resolves a navigation target itself (see
/// `resolveNotificationRoute` in the notifications screen) from the
/// type+id pair against its own existing routes, rather than the
/// backend guessing which of leads/follow_ups/calls to join against.
///
/// Named `AppNotification`, not `Notification` — Flutter's own widgets
/// library already defines a `Notification` class (the
/// NotificationListener bubbling system), and colliding with it would
/// be a constant source of confusing import errors.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.relatedEntityType,
    this.relatedEntityId,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        relatedEntityType: json['related_entity_type'] as String?,
        relatedEntityId: json['related_entity_id'] as String?,
        isRead: json['is_read'] as bool? ?? false,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String type;
  final String title;
  final String? body;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        relatedEntityType: relatedEntityType,
        relatedEntityId: relatedEntityId,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );
}
