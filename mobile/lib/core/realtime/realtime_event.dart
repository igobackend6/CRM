/// Phase 21B — Supabase Realtime. A table-agnostic, already-decoded form
/// of a Postgres Changes payload (`PostgresChangePayload` from
/// `realtime_client`), so feature controllers never touch the
/// supabase_flutter types directly — only [RealtimeChannelManager] does.
enum RealtimeEventType { insert, update, delete }

class RealtimeRecordEvent {
  const RealtimeRecordEvent({
    required this.table,
    required this.type,
    required this.record,
    required this.oldRecord,
  });

  final String table;
  final RealtimeEventType type;

  /// The new row (insert/update) — empty for a delete.
  final Map<String, dynamic> record;

  /// The old row. Only the primary key is guaranteed present (the
  /// workspace tables use the default `REPLICA IDENTITY` — primary key
  /// only, not `FULL`), which is all a delete handler needs to remove the
  /// right item by id.
  final Map<String, dynamic> oldRecord;

  /// The affected row's id, from whichever of [record]/[oldRecord] has it
  /// (a delete's [record] is empty, an insert/update's [oldRecord] may be
  /// empty too under the default replica identity).
  String? get id => (record['id'] ?? oldRecord['id']) as String?;
}
