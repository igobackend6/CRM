import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../sim/domain/sim_permission_status.dart';
import '../../../settings/domain/app_settings.dart' show kDefaultNotSyncHours;
import '../../data/call_sync_api.dart';
import '../../data/call_sync_repository.dart';
import '../../data/call_sync_store.dart';
import '../../domain/recorder_status.dart';
import '../../domain/shared_audio.dart';

class CallSyncState {
  const CallSyncState({
    this.loaded = false,
    this.permission = SimPermissionStatus.notRequested,
    this.progress = const CallSyncProgress(),
    this.folderAccessible = true,
    this.recorder = const RecorderStatus(),
    this.notificationsAllowed = true,
    this.syncing = false,
    this.blocker,
    this.errorMessage,
  });

  final bool loaded;
  final SimPermissionStatus permission;
  final CallSyncProgress progress;

  /// False when the picked folder's access was revoked (folder moved/deleted, app data cleared).
  final bool folderAccessible;

  /// The CRM's own call recorder (permissions / accessibility / folder).
  final RecorderStatus recorder;

  /// Whether Android lets the app show notifications (the not-synced reminder needs it).
  final bool notificationsAllowed;
  final bool syncing;

  /// Why the last sync couldn't run, if it couldn't.
  final CallSyncBlocker? blocker;

  /// A friendly message about the last failed sync.
  final String? errorMessage;

  CallSyncSummary? get lastSummary => progress.lastSummary;
  RecordingFolder? get folder => progress.folder;
  bool get recordCalls => progress.recordCalls;
  bool get neverAttendedOn => progress.neverAttendedOn;
  bool get recordOnSpeaker => progress.recordOnSpeaker;

  CallSyncState copyWith({
    bool? loaded,
    SimPermissionStatus? permission,
    CallSyncProgress? progress,
    bool? folderAccessible,
    RecorderStatus? recorder,
    bool? notificationsAllowed,
    bool? syncing,
    CallSyncBlocker? blocker,
    bool clearBlocker = false,
    String? errorMessage,
    bool clearError = false,
  }) =>
      CallSyncState(
        loaded: loaded ?? this.loaded,
        permission: permission ?? this.permission,
        progress: progress ?? this.progress,
        folderAccessible: folderAccessible ?? this.folderAccessible,
        recorder: recorder ?? this.recorder,
        notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
        syncing: syncing ?? this.syncing,
        blocker: clearBlocker ? null : (blocker ?? this.blocker),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Runs call-history sync for the signed-in employee in the selected workspace — on demand
/// (Sync now / Re-sync) and automatically (app open, back in the app, every few minutes while open).
class CallSyncController extends StateNotifier<CallSyncState> {
  CallSyncController(
    this._repository,
    this._profileId,
    this._workspaceId, {
    this.notSyncHours = kDefaultNotSyncHours,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(const CallSyncState());

  final CallSyncRepository _repository;
  final String? _profileId;
  final String? _workspaceId;
  final DateTime Function() _clock;

  /// Settings > Not Sync Notification: remind after this many hours without a successful sync.
  final int notSyncHours;

  DateTime? _lastAuto;

  /// Automatic runs are at most this often (resume + timer would otherwise stack up).
  static const autoInterval = Duration(minutes: 2);

  bool get _ready => _profileId != null && _workspaceId != null;

  Future<void> load() async {
    if (!_ready) {
      state = state.copyWith(loaded: true);
      return;
    }
    try {
      final permission = await _repository.permissionStatus();
      final progress = await _repository.progress(_profileId!, _workspaceId!);
      final folder = progress.folder;
      final accessible = folder == null || await _repository.hasFolderAccess(folder);
      // Also keeps the native recorder's configuration in step (SIM may have changed).
      final recorder = await _repository.applyRecorderConfig(_profileId, _workspaceId);
      if (!mounted) return;
      final notifications = await _repository.notificationsAllowed();
      if (!mounted) return;
      state = state.copyWith(
        loaded: true,
        permission: permission,
        progress: progress,
        folderAccessible: accessible,
        recorder: recorder,
        notificationsAllowed: notifications,
      );
      await _moveReminder();
    } catch (e) {
      AppLogger.warning('Loading call-sync state failed: ${e.runtimeType}');
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  Future<void> requestPermission() async {
    final permission = await _repository.requestPermission();
    if (!mounted) return;
    state = state.copyWith(permission: permission);
    if (permission == SimPermissionStatus.granted) {
      await syncNow();
    } else {
      await _moveReminder();
    }
  }

  /// Settings > Never Attended Call Reminder > Remind Me. Turning it on starts from now (earlier
  /// unanswered calls get no reminder) and asks Android to allow the phone alert.
  Future<void> setNeverAttendedReminder(bool enabled) async {
    if (!_ready) return;
    await _repository.setNeverAttendedReminder(_profileId!, _workspaceId!, enabled);
    final progress = await _repository.progress(_profileId, _workspaceId);
    if (!mounted) return;
    state = state.copyWith(progress: progress);
    if (enabled && !state.notificationsAllowed) await requestNotifications();
  }

  /// A recording shared into the app (Share > Sales CRM), returned once; null if none.
  Future<SharedAudio?> takeSharedAudio() => _repository.takeSharedAudio();

  /// Waits for a sync already running (up to half a minute), then syncs. Used when a recording
  /// arrives for a call that may only just have ended.
  Future<bool> syncWhenIdle() async {
    for (var i = 0; i < 60 && state.syncing && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return syncNow();
  }

  /// The lead a tapped call-back notification asked to open (returned once), or null.
  Future<String?> takeLaunchLead() => _repository.takeLaunchLead();

  /// Keeps the "call history not synced" reminder alarm in step with the last successful sync.
  Future<void> _moveReminder() async {
    if (!_ready) return;
    await _repository.updateNotSyncReminder(_profileId!, _workspaceId!, notSyncHours);
  }

  /// Settings > Not Sync Notification: ask Android to let the app show the reminder.
  Future<void> requestNotifications() async {
    final allowed = await _repository.requestNotifications();
    if (mounted) state = state.copyWith(notificationsAllowed: allowed);
  }

  /// Settings > Not Sync Notification > Send test reminder. Returns whether it was shown.
  Future<bool> sendTestReminder() async {
    final shown = await _repository.sendTestReminder(notSyncHours);
    if (!shown && mounted) await refreshNotificationsAllowed();
    return shown;
  }

  Future<void> refreshNotificationsAllowed() async {
    final allowed = await _repository.notificationsAllowed();
    if (mounted) state = state.copyWith(notificationsAllowed: allowed);
  }

  Future<bool> openNotificationSettings() => _repository.openNotificationSettings();

  Future<void> pickRecordingFolder() async {
    if (!_ready) return;
    try {
      final folder = await _repository.pickRecordingFolder(_profileId!, _workspaceId!);
      if (folder == null || !mounted) return;
      final recorder = await _repository.applyRecorderConfig(_profileId, _workspaceId);
      if (!mounted) return;
      state = state.copyWith(progress: state.progress.copyWith(folder: folder), folderAccessible: true, recorder: recorder);
      // Pick up the recordings of calls already synced.
      await syncNow();
    } catch (e) {
      AppLogger.warning('Choosing the recordings folder failed: ${e.runtimeType}');
      if (mounted) state = state.copyWith(errorMessage: 'Couldn\'t open that folder. Try another one.');
    }
  }

  /// Sync now. [fromStart] re-reads the whole call log and every recording (Re-sync).
  /// Returns false when it couldn't run.
  Future<bool> syncNow({bool fromStart = false}) async {
    if (!_ready || state.syncing) return false;
    final ok = await _sync(fromStart);
    // Success or not: a failed run leaves the reminder counting from the last good sync.
    await _moveReminder();
    return ok;
  }

  Future<bool> _sync(bool fromStart) async {
    state = state.copyWith(syncing: true, clearError: true, clearBlocker: true);
    try {
      await _repository.sync(profileId: _profileId!, workspaceId: _workspaceId!, fromStart: fromStart);
      final progress = await _repository.progress(_profileId, _workspaceId);
      if (mounted) state = state.copyWith(syncing: false, progress: progress, permission: SimPermissionStatus.granted);
      return true;
    } on CallSyncBlockedException catch (e) {
      if (!mounted) return false;
      final permission = await _repository.permissionStatus();
      if (mounted) state = state.copyWith(syncing: false, blocker: e.blocker, permission: permission);
      return false;
    } on CallSyncApiException catch (e) {
      if (mounted) state = state.copyWith(syncing: false, errorMessage: _messageFor(e));
      return false;
    } catch (e) {
      AppLogger.warning('Call sync failed: ${e.runtimeType}');
      if (mounted) {
        state = state.copyWith(syncing: false, errorMessage: 'Couldn\'t reach the server. Calls stay on your phone and sync next time.');
      }
      return false;
    }
  }

  /// Settings > Sync Call History > Record calls.
  Future<void> setRecordCalls(bool enabled) async {
    if (!_ready) return;
    final recorder = await _repository.setRecordCalls(_profileId!, _workspaceId!, enabled);
    final progress = await _repository.progress(_profileId, _workspaceId);
    if (mounted) state = state.copyWith(recorder: recorder, progress: progress);
  }

  /// Settings > Sync Call History > Record calls > Auto speaker.
  Future<void> setRecordOnSpeaker(bool enabled) async {
    if (!_ready) return;
    final recorder = await _repository.setRecordOnSpeaker(_profileId!, _workspaceId!, enabled);
    final progress = await _repository.progress(_profileId, _workspaceId);
    if (mounted) state = state.copyWith(recorder: recorder, progress: progress);
  }

  Future<void> requestMicrophone() async {
    final recorder = await _repository.requestMicrophone();
    if (mounted) state = state.copyWith(recorder: recorder);
  }

  Future<bool> openAccessibilitySettings() => _repository.openAccessibilitySettings();

  /// The app's page in Android Settings (for a permission refused for good).
  Future<bool> openAppSettings() => _repository.openAppSettings();

  /// A quiet background-style run: skipped when one ran recently or sync isn't set up yet.
  Future<void> autoSync() async {
    if (!_ready || state.syncing) return;
    final now = _clock();
    if (_lastAuto != null && now.difference(_lastAuto!) < autoInterval) return;
    _lastAuto = now;
    if (!state.loaded) await load();
    if (!mounted || state.permission != SimPermissionStatus.granted) return;
    await syncNow();
  }

  static String _messageFor(CallSyncApiException e) => switch (e.code) {
        'forbidden' => 'You don\'t have permission to sync calls in this workspace.',
        'unauthorized' => 'Your session expired. Sign in again to sync calls.',
        _ => 'Call sync failed on the server. It will try again automatically.',
      };
}
