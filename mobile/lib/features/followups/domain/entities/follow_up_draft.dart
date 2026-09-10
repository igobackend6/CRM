/// The editable subset of a follow-up, as submitted from the create/edit
/// form (Phase 7 §2C/§2D). Mirrors backend `FollowUpCreate`/
/// `FollowUpUpdate` (backend/app/schemas/followups.py). Carries no
/// `workspace_id`/`created_by_member_id` — those are never
/// client-supplied (§3), so there's nothing here to trust or not trust.
/// `assignedMemberId` IS included (unlike a lead's create draft):
/// follow_ups.assigned_member_id is NOT NULL, so a value must be
/// supplied or the server defaults it to the creator.
class FollowUpDraft {
  const FollowUpDraft({
    required this.dueAt,
    required this.type,
    this.notes,
    this.assignedMemberId,
    this.status,
  });

  final DateTime dueAt;
  final String type;
  final String? notes;
  final String? assignedMemberId;

  /// Edit-only (§2D "change supported status") — left null on create, so
  /// the server applies its own default ('pending', via the DB column
  /// default) rather than this draft trying to set it.
  final String? status;

  Map<String, dynamic> toJson() => {
        'due_at': dueAt.toUtc().toIso8601String(),
        'type': type,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (assignedMemberId != null) 'assigned_member_id': assignedMemberId,
        if (status != null) 'status': status,
      };
}
