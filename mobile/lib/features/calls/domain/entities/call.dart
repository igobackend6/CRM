import '../../../followups/domain/entities/lead_summary.dart';
import '../../../leads/domain/entities/member_summary.dart';
import 'call_outcome.dart';

/// "+91 89258 78325" for an Indian number (+91 and 10 digits), the raw text otherwise, null when empty.
String? formatPhoneNumber(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
  }
  if (digits.length == 10) return '${digits.substring(0, 5)} ${digits.substring(5)}';
  return text;
}

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
    this.lead,
    this.contactName,
    this.phoneNumber,
    this.source,
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
        lead: json['lead'] == null ? null : LeadSummary.fromJson(json['lead'] as Map<String, dynamic>),
        contactName: json['contact_name'] as String?,
        phoneNumber: json['phone_number'] as String?,
        source: json['source'] as String?,
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
  /// Null for a call to/from a number that is not a lead (an unknown caller).
  final LeadSummary? lead;

  /// The name for a call with no lead: the phone's saved contact name, or "Unknown".
  final String? contactName;

  /// The number, as the phone logged it (E.164, e.g. +918925958929).
  final String? phoneNumber;

  /// `device_sync` for calls logged from the phone, `manual` for ones typed in.
  final String? source;
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

  bool get hasLead => lead != null;

  /// Who the call was with: the lead's name, else the name the phone has for the number, else "Unknown".
  String get displayName {
    final name = lead?.name ?? contactName;
    return name == null || name.trim().isEmpty ? 'Unknown' : name.trim();
  }

  /// The last 10 digits of the number, the key calls to the same person share (null if unknown).
  String? get phoneKey {
    final digits = (phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : null;
  }

  /// "+91 89258 78325" for an Indian number, else as stored; null with no number.
  String? get formattedNumber => formatPhoneNumber(phoneNumber);

  /// An incoming call nobody picked up (missed, or declined): shown in red, like the phone's own log.
  bool get isMissedIncoming => isInbound && (state == 'MISSED' || state == 'CANCELLED');

  String get formattedDuration {
    final seconds = durationSeconds;
    if (seconds == null) return '—';
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes}m ${remaining}s';
  }
}
