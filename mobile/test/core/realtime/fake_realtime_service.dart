import 'dart:async';

import 'package:mobile/core/realtime/realtime_event.dart';
import 'package:mobile/core/realtime/realtime_event_source.dart';

/// Test double for `realtimeServiceProvider` — every test container
/// overrides the provider with one of these instead of letting
/// controllers construct a real `RealtimeService` (which needs an
/// initialized `supabase_flutter` client). Tests call [emit]/[emitResync]
/// directly to simulate a Postgres Changes event/reconnect, exactly as
/// `RealtimeChannelManager` would push one in production.
class FakeRealtimeService implements RealtimeEventSource {
  final _eventsController = StreamController<RealtimeRecordEvent>.broadcast();
  final _resyncController = StreamController<void>.broadcast();

  @override
  Stream<RealtimeRecordEvent> get events => _eventsController.stream;

  @override
  Stream<void> get resynced => _resyncController.stream;

  void emit(RealtimeRecordEvent event) => _eventsController.add(event);

  void emitInsert(String table, Map<String, dynamic> record) =>
      emit(RealtimeRecordEvent(table: table, type: RealtimeEventType.insert, record: record, oldRecord: const {}));

  void emitUpdate(String table, Map<String, dynamic> record, {Map<String, dynamic> oldRecord = const {}}) =>
      emit(RealtimeRecordEvent(table: table, type: RealtimeEventType.update, record: record, oldRecord: oldRecord));

  void emitDelete(String table, Map<String, dynamic> oldRecord) =>
      emit(RealtimeRecordEvent(table: table, type: RealtimeEventType.delete, record: const {}, oldRecord: oldRecord));

  void emitResync() => _resyncController.add(null);

  void dispose() {
    unawaited(_eventsController.close());
    unawaited(_resyncController.close());
  }
}
