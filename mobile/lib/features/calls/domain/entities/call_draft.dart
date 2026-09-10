/// The submittable subset of a manually-logged call (Phase 9 §4). Mirrors
/// backend `CallCreate` (backend/app/schemas/calls.py). Carries no
/// `workspace_id`/`agent_member_id`/`state` — those are never
/// client-supplied (§4/§9), so there's nothing here to trust or not
/// trust. `durationSeconds` is NOT the generated `duration_seconds`
/// column — see CallCreate's docstring: the server derives
/// connected_at/ended_at from this + startedAt, and the database
/// computes the authoritative duration from those.
class CallDraft {
  const CallDraft({
    required this.direction,
    this.outcomeId,
    this.startedAt,
    this.durationSeconds,
    this.notes,
  });

  final String direction;
  final String? outcomeId;
  final DateTime? startedAt;
  final int? durationSeconds;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'direction': direction,
        if (outcomeId != null) 'outcome_id': outcomeId,
        if (startedAt != null) 'started_at': startedAt!.toUtc().toIso8601String(),
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}
