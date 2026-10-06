/// Whether the CRM is the phone's default Phone app, and whether this phone offers that role at all.
class DialerRoleStatus {
  const DialerRoleStatus({this.isDefault = false, this.available = true});

  final bool isDefault;

  /// False on phones that don't let apps become the Phone app (the switch is then disabled).
  final bool available;

  static DialerRoleStatus fromPlatform(Object? raw) {
    if (raw is! Map) return const DialerRoleStatus(available: false);
    return DialerRoleStatus(isDefault: raw['isDefault'] == true, available: raw['available'] != false);
  }
}

/// One SIM the phone can place a call on (Android calls it a "phone account").
class PhoneAccountInfo {
  const PhoneAccountInfo({required this.id, required this.label, this.subscriptionId, this.index = 0});

  /// Android's identifier for the account — never shown, never stored.
  final String id;
  final String label;

  /// The subscription ID the Connected SIM screen uses, when Android reports it (Android 11+).
  final int? subscriptionId;
  final int index;

  static PhoneAccountInfo? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final label = raw['label'];
    final sub = raw['subscriptionId'];
    final index = raw['index'];
    return PhoneAccountInfo(
      id: id,
      label: label is String && label.isNotEmpty ? label : 'SIM',
      subscriptionId: sub is int ? sub : null,
      index: index is int ? index : 0,
    );
  }
}

enum NativeCallDirection { incoming, outgoing }

enum NativeCallState { newCall, ringing, dialing, connecting, active, holding, disconnecting, disconnected, unknown }

/// How a call ended. Mirrors the CRM's existing call states: completed → ENDED, missed → MISSED,
/// rejected/cancelled → CANCELLED, busy/failed → FAILED.
enum NativeCallStatus { completed, missed, rejected, busy, failed, cancelled }

/// One update about a call, from Android's phone stack.
class NativeCallEvent {
  const NativeCallEvent({
    required this.callId,
    required this.direction,
    required this.state,
    required this.startedAt,
    this.phoneNumber,
    this.status,
    this.answeredAt,
    this.endedAt,
  });

  final String callId;
  final String? phoneNumber;
  final NativeCallDirection direction;
  final NativeCallState state;

  /// Set once the call has ended.
  final NativeCallStatus? status;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  bool get isEnded => state == NativeCallState.disconnected || endedAt != null;

  int get durationSeconds {
    final from = answeredAt;
    final to = endedAt;
    if (from == null || to == null) return 0;
    final seconds = to.difference(from).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  static NativeCallEvent? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['callId'];
    final started = raw['startedAt'];
    if (id is! String || started is! int) return null;
    DateTime? time(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final number = raw['phoneNumber'];
    return NativeCallEvent(
      callId: id,
      phoneNumber: number is String && number.isNotEmpty ? number : null,
      direction: raw['direction'] == 'incoming' ? NativeCallDirection.incoming : NativeCallDirection.outgoing,
      state: _stateOf(raw['state']),
      status: _statusOf(raw['status']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      answeredAt: time(raw['answeredAt']),
      endedAt: time(raw['endedAt']),
    );
  }

  static NativeCallState _stateOf(Object? v) => switch (v) {
        'new' => NativeCallState.newCall,
        'ringing' => NativeCallState.ringing,
        'dialing' => NativeCallState.dialing,
        'connecting' || 'selecting_account' => NativeCallState.connecting,
        'active' => NativeCallState.active,
        'holding' => NativeCallState.holding,
        'disconnecting' => NativeCallState.disconnecting,
        'disconnected' => NativeCallState.disconnected,
        _ => NativeCallState.unknown,
      };

  static NativeCallStatus? _statusOf(Object? v) => switch (v) {
        'completed' => NativeCallStatus.completed,
        'missed' => NativeCallStatus.missed,
        'rejected' => NativeCallStatus.rejected,
        'busy' => NativeCallStatus.busy,
        'failed' => NativeCallStatus.failed,
        'cancelled' => NativeCallStatus.cancelled,
        _ => null,
      };
}

/// What happened when the CRM asked Android to place a call.
enum PlaceCallResult { placed, invalidNumber, permissionDenied, unavailable, failed }
