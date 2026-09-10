/// Display-only workspace member identity — "assigned to", "created by",
/// "activity by". Never used to decide what the UI allows; authorization
/// is only ever real when enforced by the backend/database (Phase 5 §9).
class MemberSummary {
  const MemberSummary({required this.id, this.fullName});

  factory MemberSummary.fromJson(Map<String, dynamic> json) => MemberSummary(
        id: json['id'] as String,
        fullName: json['full_name'] as String?,
      );

  final String id;
  final String? fullName;

  String get displayName => fullName ?? 'Unknown';
}
