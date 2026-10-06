import 'sim_card.dart';

/// "This is the SIM the CRM should treat as this employee's business calling SIM" — on this phone.
///
/// Saved per signed-in employee on this install (see SimSelectionStorage). The stable interface the
/// future Call History Sync reads: match call-log entries on [subscriptionId]. Keeps no phone
/// number and no hardware identifier.
class BusinessSimSelection {
  const BusinessSimSelection({
    required this.subscriptionId,
    required this.deviceInstallId,
    required this.selectedAt,
    this.slotIndex,
    this.carrierName,
    this.displayName,
  });

  factory BusinessSimSelection.fromSim(SimCard sim, {required String deviceInstallId, required DateTime selectedAt}) =>
      BusinessSimSelection(
        subscriptionId: sim.subscriptionId,
        deviceInstallId: deviceInstallId,
        selectedAt: selectedAt,
        slotIndex: sim.slotIndex,
        carrierName: sim.carrierName,
        displayName: sim.displayName,
      );

  final int subscriptionId;

  /// A random ID created once per app install — not derived from the phone's hardware.
  final String deviceInstallId;
  final DateTime selectedAt;

  // What the SIM looked like when chosen, so "previously selected SIM" can still be named after
  // it is removed.
  final int? slotIndex;
  final String? carrierName;
  final String? displayName;

  /// e.g. "Jio • SIM 1"; parts that weren't reported are left out.
  String get summary {
    final sim = slotIndex == null ? 'SIM' : 'SIM ${slotIndex! + 1}';
    final operator = carrierName ?? displayName;
    return operator == null ? sim : '$operator • $sim';
  }

  bool matches(SimCard sim) => sim.subscriptionId == subscriptionId;

  Map<String, Object?> toJson() => {
        'subscriptionId': subscriptionId,
        'deviceInstallId': deviceInstallId,
        'selectedAt': selectedAt.toUtc().toIso8601String(),
        'slotIndex': slotIndex,
        'carrierName': carrierName,
        'displayName': displayName,
      };

  /// Null when the saved value is unusable (so a corrupted save means "nothing selected").
  static BusinessSimSelection? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['subscriptionId'];
    final install = json['deviceInstallId'];
    final at = DateTime.tryParse(json['selectedAt']?.toString() ?? '');
    if (id is! int || install is! String || install.isEmpty || at == null) return null;
    final slot = json['slotIndex'];
    final carrier = json['carrierName'];
    final display = json['displayName'];
    return BusinessSimSelection(
      subscriptionId: id,
      deviceInstallId: install,
      selectedAt: at.toLocal(),
      slotIndex: slot is int ? slot : null,
      carrierName: carrier is String ? carrier : null,
      displayName: display is String ? display : null,
    );
  }
}
