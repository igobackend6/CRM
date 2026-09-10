import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `TimelineItemOut` (reused unchanged from
/// Customer 360, backend/app/schemas/customer360.py — see
/// backend/app/schemas/dashboard.py's own note on why there's no
/// separate dashboard-specific schema). `id` is prefixed by source
/// table (e.g. `"call:<uuid>"`, `"follow_up:<uuid>"`, `"notification:<uuid>"`)
/// since items are merged from five different tables and a bare row id
/// isn't unique across them — [entityType]/[entityId] split that prefix
/// back out for navigation (see `resolveActivityRoute` in the dashboard
/// screen).
class RecentActivityItem {
  const RecentActivityItem({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.actorMember,
    required this.summary,
    required this.details,
  });

  factory RecentActivityItem.fromJson(Map<String, dynamic> json) => RecentActivityItem(
        id: json['id'] as String,
        type: json['type'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        actorMember: json['actor_member'] != null ? MemberSummary.fromJson(json['actor_member'] as Map<String, dynamic>) : null,
        summary: json['summary'] as String,
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
      );

  final String id;
  final String type;
  final DateTime occurredAt;
  final MemberSummary? actorMember;
  final String summary;
  final Map<String, dynamic> details;

  /// The source table name before the ":" in [id] (e.g. "call",
  /// "follow_up") — null if [id] doesn't follow that convention (should
  /// never happen for a server-supplied item, but this stays defensive
  /// rather than throwing on an unexpected shape).
  String? get entityType {
    final i = id.indexOf(':');
    return i > 0 ? id.substring(0, i) : null;
  }

  /// The row id after the ":" in [id].
  String? get entityId {
    final i = id.indexOf(':');
    return i > 0 && i + 1 < id.length ? id.substring(i + 1) : null;
  }
}
