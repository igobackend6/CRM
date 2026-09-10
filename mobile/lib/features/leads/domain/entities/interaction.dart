import 'member_summary.dart';

/// One entry of the read-only Customer 360 timeline (`interactions` —
/// supabase/migrations/000010_allocations_interactions.sql). Phase 5
/// only displays this history (§2); nothing in this phase writes to it.
class Interaction {
  const Interaction({required this.id, required this.type, required this.payload, this.actorMember, required this.createdAt});

  factory Interaction.fromJson(Map<String, dynamic> json) => Interaction(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        actorMember: json['actor_member'] != null ? MemberSummary.fromJson(json['actor_member'] as Map<String, dynamic>) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final MemberSummary? actorMember;
  final DateTime createdAt;
}
