import '../../../followups/domain/entities/lead_summary.dart';

/// Mirrors the backend's `ConversationOut` shape
/// (backend/app/schemas/messaging.py), itself the enriched form of
/// `conversations` (supabase/migrations/000019_messaging.sql) — lead
/// name and latest-message/unread-count are already resolved
/// server-side, not raw ids the client would have to look up itself
/// (Phase 16 §9 "avoid N+1"). Reuses [LeadSummary] rather than a second
/// identical type (same convention as `Call`).
class Conversation {
  const Conversation({
    required this.id,
    required this.workspaceId,
    required this.lead,
    this.latestMessagePreview,
    this.latestMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        lead: LeadSummary.fromJson(json['lead'] as Map<String, dynamic>),
        latestMessagePreview: json['latest_message_preview'] as String?,
        latestMessageAt: json['latest_message_at'] != null ? DateTime.parse(json['latest_message_at'] as String) : null,
        unreadCount: json['unread_count'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String workspaceId;
  final LeadSummary lead;
  final String? latestMessagePreview;
  final DateTime? latestMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasUnread => unreadCount > 0;
}
