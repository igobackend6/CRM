import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/call_sync_api.dart';
import '../../data/call_sync_repository.dart';
import '../../domain/shared_audio.dart';

class RecordingImportState {
  const RecordingImportState({
    this.loading = true,
    this.candidates = const [],
    this.selectedCallId,
    this.attaching = false,
    this.done = false,
    this.errorMessage,
  });

  /// Bringing the CRM's calls up to date and looking for the call this recording belongs to.
  final bool loading;
  final List<RecordingCandidate> candidates;
  final String? selectedCallId;
  final bool attaching;
  final bool done;
  final String? errorMessage;

  RecordingImportState copyWith({
    bool? loading,
    List<RecordingCandidate>? candidates,
    String? selectedCallId,
    bool clearSelection = false,
    bool? attaching,
    bool? done,
    String? errorMessage,
    bool clearError = false,
  }) =>
      RecordingImportState(
        loading: loading ?? this.loading,
        candidates: candidates ?? this.candidates,
        selectedCallId: clearSelection ? null : (selectedCallId ?? this.selectedCallId),
        attaching: attaching ?? this.attaching,
        done: done ?? this.done,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Share > Sales CRM: works out which synced call a shared recording belongs to and attaches it.
class RecordingImportController extends StateNotifier<RecordingImportState> {
  RecordingImportController(
    this._repository,
    this._profileId,
    this._workspaceId,
    this.audio, {
    required this._syncFirst,
  }) : super(const RecordingImportState());

  final CallSyncRepository _repository;
  final String? _profileId;
  final String? _workspaceId;
  final SharedAudio audio;
  final Future<void> Function() _syncFirst;

  bool get _ready => _profileId != null && _workspaceId != null;

  /// Syncs first (the call may have ended seconds ago), then lists the calls waiting for a recording.
  Future<void> load() async {
    if (!_ready) {
      state = state.copyWith(loading: false, errorMessage: 'Sign in to add a recording.');
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _syncFirst();
    } catch (e) {
      AppLogger.warning('Syncing before importing a recording failed: ${e.runtimeType}');
    }
    try {
      var candidates = await _repository.recordingCandidates(_profileId!, _workspaceId!, audio);
      // The file says exactly when its call started. If no synced call started then, the call has
      // probably not reached the CRM yet (the phone's call log can lag): sync again a few times
      // rather than offer the wrong call.
      for (var attempt = 0; attempt < _extraSyncs && audio.recordedAt != null && !candidates.any((c) => c.likely) && mounted; attempt++) {
        await Future<void>.delayed(_retryDelay);
        try {
          await _syncFirst();
        } catch (e) {
          AppLogger.warning('Syncing before importing a recording failed: ${e.runtimeType}');
        }
        candidates = await _repository.recordingCandidates(_profileId, _workspaceId, audio);
      }
      if (!mounted) return;
      final likely = candidates.where((c) => c.likely).firstOrNull;
      state = state.copyWith(
        loading: false,
        candidates: candidates,
        selectedCallId: likely?.call.callId,
        clearSelection: likely == null,
      );
    } catch (e) {
      AppLogger.warning('Listing calls for a shared recording failed: ${e.runtimeType}');
      if (mounted) state = state.copyWith(loading: false, errorMessage: 'Couldn\'t look up your calls. Try again.');
    }
  }

  static const _extraSyncs = 3;
  static const _retryDelay = Duration(seconds: 5);

  void select(String callId) => state = state.copyWith(selectedCallId: callId, clearError: true);

  Future<void> attach() async {
    final callId = state.selectedCallId;
    if (callId == null || state.attaching || !_ready) return;
    state = state.copyWith(attaching: true, clearError: true);
    try {
      await _repository.attachSharedRecording(profileId: _profileId!, workspaceId: _workspaceId!, callId: callId, audio: audio);
      if (mounted) state = state.copyWith(attaching: false, done: true);
    } on CallSyncApiException catch (e) {
      if (mounted) state = state.copyWith(attaching: false, errorMessage: _messageFor(e));
    } catch (e) {
      AppLogger.warning('Attaching a shared recording failed: ${e.runtimeType}');
      if (mounted) state = state.copyWith(attaching: false, errorMessage: 'Couldn\'t add the recording. Check your connection and try again.');
    }
  }

  static String _messageFor(CallSyncApiException e) => switch (e.code) {
        'forbidden' => 'You can only add recordings to your own calls.',
        'invalid_file' => 'This file can\'t be used as a call recording (it must be audio, up to 50 MB).',
        'unauthorized' => 'Your session expired. Sign in again.',
        _ => 'Couldn\'t add the recording. Try again.',
      };
}
