import '../../sim/domain/sim_number.dart';

/// One row of the phone's call log, as Android reported it (CallSyncChannel.readCallLog).
class DeviceCall {
  const DeviceCall({
    required this.id,
    required this.type,
    required this.dateMillis,
    required this.durationSeconds,
    this.number,
    this.subscriptionId,
  });

  /// CallLog.Calls._ID — stable for this call on this phone.
  final int id;
  final String? number;

  /// CallLog.Calls.TYPE (see [typeIncoming] ...).
  final int type;

  /// When the call started (ms since epoch).
  final int dateMillis;

  /// Talk time in seconds (0 for missed / unanswered).
  final int durationSeconds;

  /// The SIM it used, when Android could tell.
  final int? subscriptionId;

  static const typeIncoming = 1;
  static const typeOutgoing = 2;
  static const typeMissed = 3;
  static const typeVoicemail = 4;
  static const typeRejected = 5;
  static const typeBlocked = 6;
  static const typeAnsweredExternally = 7;

  /// The call went unanswered — missed, rejected, or an outgoing call nobody picked up.
  bool get isUnattended => switch (crmKind?.state) {
        'MISSED' || 'CANCELLED' => true,
        _ => false,
      };

  /// "Missed call" / "Declined call" / "Call not answered" — for the reminder's text.
  String get unattendedLabel => switch (crmKind) {
        (direction: 'outbound', state: _) => 'Call not answered',
        (direction: _, state: 'CANCELLED') => 'Declined call',
        _ => 'Missed call',
      };

  /// Two people actually talked.
  bool get isConnected => crmKind?.state == 'ENDED';

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(dateMillis);

  /// (direction, state) for the CRM, or null for calls that aren't synced (blocked, answered on
  /// another device, unknown types).
  ({String direction, String state})? get crmKind => switch (type) {
        typeIncoming => (direction: 'inbound', state: durationSeconds > 0 ? 'ENDED' : 'MISSED'),
        typeOutgoing => (direction: 'outbound', state: durationSeconds > 0 ? 'ENDED' : 'CANCELLED'),
        typeMissed || typeVoicemail => (direction: 'inbound', state: 'MISSED'),
        typeRejected => (direction: 'inbound', state: 'CANCELLED'),
        _ => null,
      };

  /// The number in E.164 (+91...), or null when it is hidden/unusable.
  String? get normalizedNumber {
    final raw = number;
    if (raw == null || raw.trim().isEmpty) return null;
    return normalizeSimNumber(raw);
  }

  /// The JSON the call-sync Edge Function expects, or null if this call isn't synced.
  Map<String, Object?>? toSyncEntry(String installId) {
    final kind = crmKind;
    final phone = normalizedNumber;
    if (kind == null || phone == null) return null;
    return {
      'key': '$installId:$id',
      'phone': phone,
      'direction': kind.direction,
      'state': kind.state,
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }

  static DeviceCall? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final type = raw['type'];
    final date = raw['date'];
    final duration = raw['duration'];
    if (id is! int || type is! int || date is! int) return null;
    final number = raw['number'];
    final sub = raw['subscriptionId'];
    return DeviceCall(
      id: id,
      type: type,
      dateMillis: date,
      durationSeconds: duration is int && duration > 0 ? duration : 0,
      number: number is String ? number : null,
      subscriptionId: sub is int ? sub : null,
    );
  }
}

/// The last 10 digits of a number — the same rule the server uses to match leads.
String? phoneKeyOf(String? number) {
  if (number == null) return null;
  final digits = number.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 10 ? digits.substring(digits.length - 10) : null;
}
