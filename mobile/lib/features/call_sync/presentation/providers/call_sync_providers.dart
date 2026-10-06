import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/supabase/supabase_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../../followups/presentation/providers/followup_providers.dart';
import '../../data/call_back_follow_ups.dart';
import '../../data/call_log_platform_source.dart';
import '../../data/call_sync_api.dart';
import '../../data/call_sync_repository.dart';
import '../../data/call_sync_store.dart';
import '../../domain/call_recording.dart';
import '../../domain/shared_audio.dart';
import '../controllers/call_sync_controller.dart';
import '../controllers/recording_import_controller.dart';
import '../widgets/recording_player.dart';

final callLogSourceProvider = Provider<CallLogPlatformSource>((ref) => MethodChannelCallLogSource());

final callSyncApiProvider = Provider<CallSyncApi>((ref) => SupabaseCallSyncApi(SupabaseService.client));

final callSyncStorageProvider = Provider<CallSyncStorage>((ref) => SecureCallSyncStorage());

final recordingDownloaderProvider = Provider<RecordingDownloader>((ref) => DioRecordingDownloader());

/// Creates the "call back" follow-ups of Never Attended Call Reminder through the existing follow-up service.
final callBackFollowUpsProvider = Provider<CallBackFollowUps>(
  (ref) => ApiCallBackFollowUps(ref.watch(followUpRepositoryProvider), () => ref.read(authControllerProvider).user?.accessToken),
);

final callSyncRepositoryProvider = Provider<CallSyncRepository>(
  (ref) => CallSyncRepository(
    source: ref.watch(callLogSourceProvider),
    api: ref.watch(callSyncApiProvider),
    store: CallSyncStore(ref.watch(callSyncStorageProvider)),
    sims: ref.watch(simRepositoryProvider),
    downloader: ref.watch(recordingDownloaderProvider),
    callBackFollowUps: ref.watch(callBackFollowUpsProvider),
  ),
);

/// Shared by Settings and the automatic trigger; rebuilt when the employee or workspace changes.
final callSyncControllerProvider = StateNotifierProvider<CallSyncController, CallSyncState>((ref) {
  final profileId = ref.watch(authControllerProvider.select((s) => s.isAuthenticated ? s.user!.id : null));
  final workspaceId = ref.watch(workspaceControllerProvider.select((w) => w.selected?.workspace.id));
  // A new hours choice rebuilds the controller, which re-reads its state and moves the reminder.
  final notSyncHours = ref.watch(appSettingsControllerProvider.select((s) => s.notSyncHours));
  return CallSyncController(ref.watch(callSyncRepositoryProvider), profileId, workspaceId, notSyncHours: notSyncHours)..load();
});

/// Which of the listed calls have a recording, by call id. Keyed on the ids joined with commas.
final callRecordingsProvider = FutureProvider.autoDispose.family<Map<String, CallRecording>, String>((ref, idsCsv) async {
  final workspaceId = ref.watch(workspaceControllerProvider.select((w) => w.selected?.workspace.id));
  if (workspaceId == null || idsCsv.isEmpty) return const {};
  try {
    return await ref.watch(callSyncRepositoryProvider).recordingsByCall(workspaceId, idsCsv.split(','));
  } catch (_) {
    // The list works without play buttons (offline, or the function is unreachable).
    return const {};
  }
});

/// A recording shared into the app that is waiting to be attached to a call.
final pendingSharedAudioProvider = StateProvider<SharedAudio?>((ref) => null);

/// Share > Sales CRM: finds the call a shared recording belongs to and attaches it.
final recordingImportControllerProvider =
    StateNotifierProvider.autoDispose.family<RecordingImportController, RecordingImportState, SharedAudio>((ref, audio) {
  final profileId = ref.watch(authControllerProvider.select((s) => s.isAuthenticated ? s.user!.id : null));
  final workspaceId = ref.watch(workspaceControllerProvider.select((w) => w.selected?.workspace.id));
  final controller = RecordingImportController(
    ref.watch(callSyncRepositoryProvider),
    profileId,
    workspaceId,
    audio,
    syncFirst: () => ref.read(callSyncControllerProvider.notifier).syncWhenIdle(),
  );
  controller.load();
  return controller;
});

/// A lead's recordings, oldest call first.
final leadRecordingsProvider = FutureProvider.autoDispose.family<List<CallRecording>, String>((ref, leadId) async {
  final workspaceId = ref.watch(workspaceControllerProvider.select((w) => w.selected?.workspace.id));
  if (workspaceId == null) return const [];
  return ref.watch(callSyncRepositoryProvider).leadRecordings(workspaceId, leadId);
});

/// A fresh audio player for the lead screen's recordings section.
final recordingPlayerFactoryProvider = Provider<RecordingPlayer Function()>((ref) => AudioplayersRecordingPlayer.new);
