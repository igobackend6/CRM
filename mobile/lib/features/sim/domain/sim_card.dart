/// One active SIM subscription exactly as Android reported it. Every field except
/// [subscriptionId] can be missing — the screen says "unavailable" rather than guessing.
class SimCard {
  const SimCard({
    required this.subscriptionId,
    this.slotIndex,
    this.carrierName,
    this.displayName,
    this.phoneNumber,
    this.simState,
    this.isActive = true,
  });

  /// Android's subscription ID: stable for a given SIM on this phone, and new for a new SIM. It is
  /// the key a selection is matched on (and what the call log's phone-account field refers to).
  final int subscriptionId;

  /// 0-based physical slot, or null when Android doesn't say (some eSIMs).
  final int? slotIndex;
  final String? carrierName;
  final String? displayName;

  /// Only when the carrier stored it on the SIM and the number permission is allowed. Shown, never
  /// saved or logged.
  final String? phoneNumber;

  /// "ready", "pinRequired", ... or null when not reported.
  final String? simState;
  final bool isActive;

  /// "SIM 1" / "SIM 2" from the slot; plain "SIM" when the slot is unknown.
  String get simLabel => slotIndex == null ? 'SIM' : 'SIM ${slotIndex! + 1}';

  String? get slotLabel => slotIndex == null ? null : 'Slot ${slotIndex! + 1}';

  /// The operator to show: carrier first, else the SIM's display name.
  String? get operatorName => carrierName ?? displayName;

  /// A short human description of a non-ready SIM state, or null when ready/unknown.
  String? get stateProblem => switch (simState) {
        'pinRequired' => 'SIM PIN required',
        'pukRequired' => 'SIM PUK required',
        'networkLocked' => 'Network locked',
        'notReady' => 'Not ready',
        'disabled' => 'SIM disabled',
        'cardError' => 'SIM card error',
        'restricted' => 'SIM restricted',
        'absent' => 'SIM not inserted',
        _ => null,
      };
}
