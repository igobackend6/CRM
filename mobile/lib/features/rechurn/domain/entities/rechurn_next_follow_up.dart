/// Mirrors the backend's `RechurnNextFollowUp` (backend/app/schemas/rechurn.py)
/// — deliberately narrower than the full `FollowUp` entity (no lead/
/// assignee/notes/isOverdue), same "only what the card needs" restraint
/// `PipelineLeadCard` already applies to its own lead shape.
class RechurnNextFollowUp {
  const RechurnNextFollowUp({required this.id, required this.type, required this.dueAt});

  factory RechurnNextFollowUp.fromJson(Map<String, dynamic> json) => RechurnNextFollowUp(
        id: json['id'] as String,
        type: json['type'] as String,
        dueAt: DateTime.parse(json['due_at'] as String),
      );

  final String id;
  final String type;
  final DateTime dueAt;
}
