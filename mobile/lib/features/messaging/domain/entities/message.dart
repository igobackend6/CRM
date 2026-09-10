import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `MessageOut` shape
/// (backend/app/schemas/messaging.py) — `senderMember` is already
/// resolved server-side (id + full_name), never a raw id the client
/// would have to look up. `readAt` is the schema's single per-message
/// "seen" timestamp (Phase 16's documented read-state simplification —
/// see 000019_messaging.sql), not per-viewer state.
class Message {
  const Message({
    required this.id,
    required this.workspaceId,
    required this.conversationId,
    required this.senderMember,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        conversationId: json['conversation_id'] as String,
        senderMember: MemberSummary.fromJson(json['sender_member'] as Map<String, dynamic>),
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      );

  final String id;
  final String workspaceId;
  final String conversationId;
  final MemberSummary senderMember;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  Message copyWith({DateTime? readAt}) => Message(
        id: id,
        workspaceId: workspaceId,
        conversationId: conversationId,
        senderMember: senderMember,
        body: body,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );
}
