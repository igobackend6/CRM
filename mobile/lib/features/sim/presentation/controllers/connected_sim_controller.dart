import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/sim_repository.dart';
import '../../domain/business_sim_selection.dart';
import '../../domain/sim_card.dart';
import '../../domain/sim_number.dart';
import '../../domain/sim_permission_status.dart';

enum ConnectedSimStatus { loading, ready, permissionRequired, permissionPermanentlyDenied, unavailable, error }

class ConnectedSimState {
  const ConnectedSimState({
    this.status = ConnectedSimStatus.loading,
    this.sims = const [],
    this.selection,
    this.numbers = const {},
    this.lastDetectedAt,
    this.refreshing = false,
    this.requestingPermission = false,
    this.notice,
  });

  final ConnectedSimStatus status;

  /// The SIMs found by the latest detection (empty = no active SIM).
  final List<SimCard> sims;

  /// The saved business-SIM choice — kept even when that SIM is gone, so the screen can say so.
  final BusinessSimSelection? selection;

  /// Mobile numbers the employee entered and submitted, by subscription ID.
  final Map<int, String> numbers;
  final DateTime? lastDetectedAt;
  final bool refreshing;
  final bool requestingPermission;

  /// A one-off message for a snackbar (e.g. a failed save); cleared once shown.
  final String? notice;

  /// The SIM's number: the one the employee submitted, else the one Android reported.
  String? numberFor(SimCard sim) => numbers[sim.subscriptionId] ?? sim.phoneNumber;

  SimCard? get selectedSim {
    final s = selection;
    if (s == null) return null;
    for (final sim in sims) {
      if (s.matches(sim)) return sim;
    }
    return null;
  }

  /// A SIM was chosen before but isn't in the phone now — the employee must pick again.
  bool get selectionUnavailable => status == ConnectedSimStatus.ready && selection != null && selectedSim == null;

  ConnectedSimState copyWith({
    ConnectedSimStatus? status,
    List<SimCard>? sims,
    BusinessSimSelection? selection,
    bool clearSelection = false,
    Map<int, String>? numbers,
    DateTime? lastDetectedAt,
    bool? refreshing,
    bool? requestingPermission,
    String? notice,
    bool clearNotice = false,
  }) =>
      ConnectedSimState(
        status: status ?? this.status,
        sims: sims ?? this.sims,
        selection: clearSelection ? null : (selection ?? this.selection),
        numbers: numbers ?? this.numbers,
        lastDetectedAt: lastDetectedAt ?? this.lastDetectedAt,
        refreshing: refreshing ?? this.refreshing,
        requestingPermission: requestingPermission ?? this.requestingPermission,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Settings > Connected SIM Details. Detects the SIMs, handles the phone permission, and saves the
/// employee's business SIM. [profileId] is the signed-in employee (null if signed out).
class ConnectedSimController extends StateNotifier<ConnectedSimState> {
  ConnectedSimController(this._repository, this._profileId, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(const ConnectedSimState());

  final SimRepository _repository;
  final String? _profileId;
  final DateTime Function() _clock;

  static const readFailedMessage = 'Unable to read SIM information.';
  static const saveFailedMessage = 'Couldn\'t save your SIM choice. Try again.';
  static const numberRequiredMessage = 'Enter the mobile number for this SIM.';
  static const numberInvalidMessage = 'Enter a valid 10-digit mobile number.';
  static const numberSaveFailedMessage = 'Couldn\'t save the number. Try again.';

  Future<void> load() async {
    state = ConnectedSimState(selection: state.selection, numbers: state.numbers);
    BusinessSimSelection? selection;
    var numbers = const <int, String>{};
    final profileId = _profileId;
    if (profileId != null) {
      try {
        selection = await _repository.loadSelection(profileId);
        numbers = await _repository.loadNumbers(profileId);
      } catch (e) {
        AppLogger.warning('Loading the saved SIM details failed: ${e.runtimeType}');
      }
    }
    if (!mounted) return;
    state = selection == null
        ? state.copyWith(clearSelection: true, numbers: numbers)
        : state.copyWith(selection: selection, numbers: numbers);

    final permission = await _repository.permissionStatus();
    if (!mounted) return;
    if (permission == SimPermissionStatus.granted) {
      await _detect();
    } else {
      _showPermission(permission);
    }
  }

  Future<void> requestPermission() async {
    if (state.requestingPermission) return;
    state = state.copyWith(requestingPermission: true);
    final permission = await _repository.requestPermission();
    if (!mounted) return;
    state = state.copyWith(requestingPermission: false);
    if (permission == SimPermissionStatus.granted) {
      state = state.copyWith(status: ConnectedSimStatus.loading);
      await _detect();
    } else {
      _showPermission(permission);
    }
  }

  /// Re-reads the SIMs. The saved choice is never dropped: if its SIM is gone the screen shows
  /// "Selected SIM unavailable" until another is picked.
  Future<void> refresh() async {
    if (state.refreshing || state.requestingPermission) return;
    if (state.status != ConnectedSimStatus.ready) return load();
    state = state.copyWith(refreshing: true);
    await _detect();
  }

  /// Back from another app (e.g. Android Settings after allowing the permission, or a SIM swap).
  Future<void> onResumed() async {
    if (state.requestingPermission || state.refreshing || state.status == ConnectedSimStatus.loading) return;
    return refresh();
  }

  Future<void> select(SimCard sim) async {
    final profileId = _profileId;
    if (profileId == null) {
      state = state.copyWith(notice: saveFailedMessage);
      return;
    }
    if (state.selection?.matches(sim) ?? false) return;
    // Calls are recorded against this SIM's number, so it must be known first.
    if (state.numberFor(sim) == null) {
      state = state.copyWith(notice: 'Enter and submit the mobile number for ${sim.simLabel} first.');
      return;
    }
    final previous = state.selection;
    // Show the choice straight away; the save below confirms or rolls it back.
    state = state.copyWith(
      selection: BusinessSimSelection.fromSim(sim, deviceInstallId: previous?.deviceInstallId ?? '', selectedAt: _clock()),
    );
    try {
      final saved = await _repository.select(profileId, sim);
      if (!mounted) return;
      state = state.copyWith(selection: saved);
    } catch (e) {
      AppLogger.warning('Saving the SIM selection failed: ${e.runtimeType}');
      if (!mounted) return;
      state = previous == null
          ? state.copyWith(clearSelection: true, notice: saveFailedMessage)
          : state.copyWith(selection: previous, notice: saveFailedMessage);
    }
  }

  /// Validates and saves the mobile number typed for [sim]. Returns an error message to show
  /// under the field, or null once saved.
  Future<String?> submitNumber(SimCard sim, String raw) async {
    if (raw.trim().isEmpty) return numberRequiredMessage;
    final number = normalizeSimNumber(raw);
    if (number == null) return numberInvalidMessage;
    final profileId = _profileId;
    if (profileId == null) return numberSaveFailedMessage;
    try {
      await _repository.saveNumber(profileId, sim.subscriptionId, number);
    } catch (e) {
      AppLogger.warning('Saving a SIM number failed: ${e.runtimeType}');
      return numberSaveFailedMessage;
    }
    if (!mounted) return null;
    state = state.copyWith(
      numbers: {...state.numbers, sim.subscriptionId: number},
      notice: 'Mobile number saved for ${sim.simLabel}.',
    );
    return null;
  }

  Future<bool> openAppSettings() => _repository.openAppSettings();

  void clearNotice() => state = state.copyWith(clearNotice: true);

  Future<void> _detect() async {
    try {
      final sims = await _repository.detectActiveSims();
      if (!mounted) return;
      state = state.copyWith(status: ConnectedSimStatus.ready, sims: sims, lastDetectedAt: _clock(), refreshing: false);
    } on SimReadException catch (e) {
      if (!mounted) return;
      switch (e.failure) {
        case SimReadFailure.permissionDenied:
          // Allowed a moment ago but revoked since (e.g. from Android Settings).
          final permission = await _repository.permissionStatus();
          if (!mounted) return;
          state = state.copyWith(refreshing: false);
          if (permission == SimPermissionStatus.granted) {
            state = state.copyWith(status: ConnectedSimStatus.error);
          } else {
            _showPermission(permission);
          }
        case SimReadFailure.unavailable:
          state = state.copyWith(status: ConnectedSimStatus.unavailable, refreshing: false);
        case SimReadFailure.readFailed:
          // A failed refresh keeps the list it already had.
          state = state.status == ConnectedSimStatus.ready
              ? state.copyWith(refreshing: false, notice: readFailedMessage)
              : state.copyWith(status: ConnectedSimStatus.error, refreshing: false);
      }
    }
  }

  void _showPermission(SimPermissionStatus permission) {
    state = state.copyWith(
      status: switch (permission) {
        SimPermissionStatus.permanentlyDenied => ConnectedSimStatus.permissionPermanentlyDenied,
        SimPermissionStatus.unavailable => ConnectedSimStatus.unavailable,
        _ => ConnectedSimStatus.permissionRequired,
      },
      sims: const [],
    );
  }
}
