import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/dialer/domain/native_dialer_models.dart';
import 'package:mobile/features/dialer/domain/phone_key.dart';

void main() {
  group('phoneKey', () {
    test('every way of writing the same Indian number gives the same key', () {
      for (final n in ['+91 98765 43210', '91 9876543210', '9876543210', '09876543210', '(+91) 98765-43210']) {
        expect(phoneKey(n), '9876543210', reason: n);
      }
    });

    test('too short, empty or null has no key', () {
      expect(phoneKey('12345'), isNull);
      expect(phoneKey(''), isNull);
      expect(phoneKey(null), isNull);
    });

    test('a different number has a different key', () => expect(phoneKey('9876543211'), isNot(phoneKey('9876543210'))));
  });

  group('NativeCallEvent', () {
    final started = DateTime(2026, 10, 3, 10).millisecondsSinceEpoch;

    test('reads what Android sends', () {
      final e = NativeCallEvent.fromPlatform({
        'callId': 'c1',
        'phoneNumber': '+919876543210',
        'direction': 'incoming',
        'state': 'active',
        'startedAt': started,
        'answeredAt': started + 2000,
      })!;
      expect(e.direction, NativeCallDirection.incoming);
      expect(e.state, NativeCallState.active);
      expect(e.isEnded, isFalse);
      expect(e.durationSeconds, 0);
      expect(e.status, isNull);
    });

    test('an ended call has a status and a duration from answer to end', () {
      final e = NativeCallEvent.fromPlatform({
        'callId': 'c1',
        'direction': 'outgoing',
        'state': 'disconnected',
        'status': 'completed',
        'startedAt': started,
        'answeredAt': started + 5000,
        'endedAt': started + 65000,
      })!;
      expect(e.isEnded, isTrue);
      expect(e.status, NativeCallStatus.completed);
      expect(e.durationSeconds, 60);
    });

    test('an unanswered call has no talk time, whatever the clock says', () {
      final e = NativeCallEvent.fromPlatform({'callId': 'c', 'direction': 'incoming', 'state': 'disconnected', 'status': 'missed', 'startedAt': started, 'endedAt': started + 30000})!;
      expect(e.durationSeconds, 0);
      expect(e.status, NativeCallStatus.missed);
    });

    test('every ending maps to a status, and junk is refused', () {
      for (final (raw, expected) in [
        ('missed', NativeCallStatus.missed),
        ('rejected', NativeCallStatus.rejected),
        ('busy', NativeCallStatus.busy),
        ('failed', NativeCallStatus.failed),
        ('cancelled', NativeCallStatus.cancelled),
      ]) {
        expect(NativeCallEvent.fromPlatform({'callId': 'c', 'direction': 'outgoing', 'state': 'disconnected', 'status': raw, 'startedAt': started})!.status, expected);
      }
      expect(NativeCallEvent.fromPlatform({'callId': 'c'}), isNull);
      expect(NativeCallEvent.fromPlatform('x'), isNull);
    });

    test('Android\'s state names map to ours', () {
      NativeCallState of(String s) => NativeCallEvent.fromPlatform({'callId': 'c', 'direction': 'outgoing', 'state': s, 'startedAt': started})!.state;
      expect(of('ringing'), NativeCallState.ringing);
      expect(of('dialing'), NativeCallState.dialing);
      expect(of('selecting_account'), NativeCallState.connecting);
      expect(of('holding'), NativeCallState.holding);
      expect(of('???'), NativeCallState.unknown);
    });
  });

  group('platform data', () {
    test('role status: a missing answer means "not available"', () {
      expect(DialerRoleStatus.fromPlatform(null).available, isFalse);
      final s = DialerRoleStatus.fromPlatform({'isDefault': true, 'available': true});
      expect(s.isDefault, isTrue);
    });

    test('phone accounts need an id; a missing label falls back', () {
      expect(PhoneAccountInfo.fromPlatform({'label': 'x'}), isNull);
      final a = PhoneAccountInfo.fromPlatform({'id': 'a1', 'subscriptionId': 3, 'index': 1})!;
      expect(a.label, 'SIM');
      expect(a.subscriptionId, 3);
    });
  });
}
