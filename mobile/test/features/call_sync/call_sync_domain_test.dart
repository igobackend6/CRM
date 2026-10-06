import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/domain/call_recording.dart';
import 'package:mobile/features/call_sync/domain/device_call.dart';
import 'package:mobile/features/call_sync/domain/recording_match.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1, 10);

  group('DeviceCall', () {
    DeviceCall call({int type = DeviceCall.typeOutgoing, int duration = 60, String? number = '08925829917'}) =>
        DeviceCall(id: 7, type: type, dateMillis: t0.millisecondsSinceEpoch, durationSeconds: duration, number: number);

    test('maps each call-log type to a CRM direction and state', () {
      expect(call(type: DeviceCall.typeIncoming).crmKind, (direction: 'inbound', state: 'ENDED'));
      expect(call(type: DeviceCall.typeIncoming, duration: 0).crmKind, (direction: 'inbound', state: 'MISSED'));
      expect(call().crmKind, (direction: 'outbound', state: 'ENDED'));
      expect(call(duration: 0).crmKind, (direction: 'outbound', state: 'CANCELLED'));
      expect(call(type: DeviceCall.typeMissed, duration: 0).crmKind, (direction: 'inbound', state: 'MISSED'));
      expect(call(type: DeviceCall.typeRejected, duration: 0).crmKind, (direction: 'inbound', state: 'CANCELLED'));
      expect(call(type: DeviceCall.typeBlocked).crmKind, isNull);
      expect(call(type: DeviceCall.typeAnsweredExternally).crmKind, isNull);
    });

    test('builds the Edge Function entry with a +91 number and a stable key', () {
      expect(call().toSyncEntry('abc'), {
        'key': 'abc:7',
        'phone': '+918925829917',
        'direction': 'outbound',
        'state': 'ENDED',
        'started_at': '2026-10-01T10:00:00.000Z',
        'duration_seconds': 60,
      });
    });

    test('hidden numbers and skipped types produce no entry', () {
      expect(call(number: null).toSyncEntry('abc'), isNull);
      expect(call(number: '-2').toSyncEntry('abc'), isNull);
      expect(call(type: DeviceCall.typeBlocked).toSyncEntry('abc'), isNull);
    });

    test('platform rows with missing fields are dropped', () {
      expect(DeviceCall.fromPlatform({'id': 1, 'type': 2}), isNull);
      expect(DeviceCall.fromPlatform('x'), isNull);
      final c = DeviceCall.fromPlatform({'id': 1, 'type': 2, 'date': 5, 'duration': -3})!;
      expect(c.durationSeconds, 0);
      expect(c.subscriptionId, isNull);
    });
  });

  group('matchRecordings', () {
    PendingRecording pending(String id, DateTime start, int seconds, {String? phone = '9800000001'}) =>
        PendingRecording(callId: id, startMillis: start.millisecondsSinceEpoch, durationSeconds: seconds, phoneKey: phone);
    RecordingFile file(String name, DateTime modified) =>
        RecordingFile(uri: 'u/$name', name: name, mimeType: 'audio/mp4', size: 10, lastModifiedMillis: modified.millisecondsSinceEpoch);

    test('pairs a file written right after the call ended', () {
      final m = matchRecordings([pending('c1', t0, 120)], [file('Call_1.m4a', t0.add(const Duration(seconds: 125)))]);
      expect(m['c1']!.name, 'Call_1.m4a');
    });

    test('a contact-name file with a yyMMddHHmm stamp is not mistaken for a phone number', () {
      final m = matchRecordings([pending('c1', t0, 60)], [file('Suguna Akka IGO Office-2610051711.mp3', t0.add(const Duration(seconds: 65)))]);
      expect(m['c1']!.name, 'Suguna Akka IGO Office-2610051711.mp3');
      // A real number in the name still has to be the call's number.
      expect(matchRecordings([pending('c1', t0, 60)], [file('Ravi-9876543210.mp3', t0.add(const Duration(seconds: 65)))]), isEmpty);
    });

    test('ignores files far from the call, and calls with no talk time', () {
      expect(matchRecordings([pending('c1', t0, 60)], [file('a.m4a', t0.add(const Duration(minutes: 30)))]), isEmpty);
      expect(matchRecordings([pending('c1', t0, 0)], [file('a.m4a', t0)]), isEmpty);
    });

    test('a file named with another number is never used; one with this number wins', () {
      final m = matchRecordings(
        [pending('c1', t0, 60)],
        [
          file('+919999999999_20261001.m4a', t0.add(const Duration(seconds: 60))),
          file('9800000001_20261001.m4a', t0.add(const Duration(seconds: 150))),
        ],
      );
      expect(m['c1']!.name, '9800000001_20261001.m4a');
    });

    test('back-to-back calls each get their own file', () {
      final c2Start = t0.add(const Duration(minutes: 2));
      final m = matchRecordings(
        [pending('c1', t0, 60), pending('c2', c2Start, 60)],
        [file('one.m4a', t0.add(const Duration(seconds: 61))), file('two.m4a', c2Start.add(const Duration(seconds: 62)))],
      );
      expect(m['c1']!.name, 'one.m4a');
      expect(m['c2']!.name, 'two.m4a');
    });

    test('date stamps in file names are not mistaken for phone numbers', () {
      final m = matchRecordings([pending('c1', t0, 60)], [file('Call recording_20261001_100100.m4a', t0.add(const Duration(seconds: 61)))]);
      expect(m, hasLength(1));
    });
  });

  test('CallRecording parses the function payload and picks a file extension', () {
    final r = CallRecording.fromJson({
      'id': 'r1',
      'call_id': 'c1',
      'mime_type': 'audio/amr',
      'size_bytes': 1200,
      'duration_seconds': 61,
      'original_file_name': null,
      'call': {'direction': 'inbound', 'started_at': '2026-10-01T10:00:00Z', 'duration_seconds': 60},
    })!;
    expect(r.direction, 'inbound');
    expect(r.extension, 'amr');
    expect(CallRecording.fromJson({'id': 'r1'}), isNull);
  });

  test('local copies are named by call id with a safe extension', () {
    expect(localRecordingName('c-1', 'Call 1.M4A'), 'c-1.m4a');
    expect(localRecordingName('c-1', 'noext'), 'c-1.m4a');
    expect(localRecordingName('../x', 'a.weird ext'), 'x.m4a');
  });
}
