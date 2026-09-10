import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `TimelineItemOut` shape
/// (backend/app/schemas/customer360.py) — one entry of the unified
/// Customer 360 timeline, assembled server-side from several existing
/// tables (interactions/calls/follow_ups/lead_documents/allocations).
/// `id` is source-prefixed (e.g. "call:uuid") since items are merged
/// from multiple tables; `type` reuses the same vocabulary
/// `interactions.type` defines, regardless of which table an item came
/// from, so the UI only needs one type->icon/label mapping.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.actorMember,
    required this.summary,
    required this.details,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) => TimelineItem(
        id: json['id'] as String,
        type: json['type'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        actorMember: json['actor_member'] != null ? MemberSummary.fromJson(json['actor_member'] as Map<String, dynamic>) : null,
        summary: json['summary'] as String,
        details: (json['details'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String id;
  final String type;
  final DateTime occurredAt;
  final MemberSummary? actorMember;
  final String summary;
  final Map<String, dynamic> details;

  /// `id` is `"<source table>:<row id>"` (see this class's own doc
  /// comment) — Phase 15 §"Activity Navigation" needs the bare row id to
  /// open the existing Call/Follow-Up Detail screen for a call/follow_up
  /// item.
  String get sourceId => id.contains(':') ? id.substring(id.indexOf(':') + 1) : id;
}
