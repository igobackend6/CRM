import '../../../followups/domain/entities/lead_summary.dart';
import '../../../leads/domain/entities/member_summary.dart';
import 'call_outcome.dart';

/// Mirrors the backend's `CallOut` shape (backend/app/schemas/calls.py),
/// itself the enriched form of `calls`
/// (supabase/migrations/000009_calls_followups.sql) — lead/agent/outcome
/// are already resolved server-side, not raw ids. Reuses [LeadSummary]/
/// [MemberSummary] rather than defining second identical types (§10:
/// reuse, don't duplicate).
class Call {
  const Call({
    required this.id,
    required this.workspaceId,
    required this.lead,
    this.agentMember,
    required this.direction,
    required this.state,
    this.outcome,
    required this.startedAt,
    this.connectedAt,
    this.endedAt,
    this.durationSeconds,
    this.notes,
    required this.createdAt,
  });

  factory Call.fromJson(Map<String, dynamic> json) => Call(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        lead: LeadSummary.fromJson(json['lead'] as Map<String, dynamic>),
        agentMember: json['agent_member'] != null ? MemberSummary.fromJson(json['agent_member'] as Map<String, dynamic>) : null,
        direction: json['direction'] as String,
        state: json['state'] as String,
        outcome: json['outcome'] != null ? CallOutcome.fromJson(json['outcome'] as Map<String, dynamic>) : null,
        startedAt: DateTime.parse(json['started_at'] as String),
        connectedAt: json['connected_at'] != null ? DateTime.parse(json['connected_at'] as String) : null,
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
        durationSeconds: json['duration_seconds'] as int?,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String workspaceId;
  final LeadSummary lead;
  final MemberSummary? agentMember;
  final String direction;
  final String state;
  final CallOutcome? outcome;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String? notes;
  final DateTime createdAt;

  bool get isInbound => direction == 'inbound';

  String get formattedDuration {
    final seconds = durationSeconds;
    if (seconds == null) return '—';
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes}m ${remaining}s';
  }
}
