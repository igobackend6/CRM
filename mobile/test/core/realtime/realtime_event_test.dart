import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/realtime/realtime_event.dart';

void main() {
  group('RealtimeRecordEvent.id', () {
    test('resolves from the new record for an insert/update', () {
      const event = RealtimeRecordEvent(
        table: 'leads',
        type: RealtimeEventType.update,
        record: {'id': 'lead-1', 'name': 'Acme'},
        oldRecord: {},
      );
      expect(event.id, 'lead-1');
    });

    test('resolves from the old record for a delete (new record is empty)', () {
      const event = RealtimeRecordEvent(
        table: 'leads',
        type: RealtimeEventType.delete,
        record: {},
        oldRecord: {'id': 'lead-1'},
      );
      expect(event.id, 'lead-1');
    });

    test('is null when neither record carries an id', () {
      const event = RealtimeRecordEvent(table: 'leads', type: RealtimeEventType.delete, record: {}, oldRecord: {});
      expect(event.id, isNull);
    });
  });
}
