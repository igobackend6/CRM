import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../../sim/data/sim_repository.dart';
import '../../sim/domain/sim_card.dart';
import '../../sim/domain/sim_permission_status.dart';
import '../domain/call_recording.dart';
import '../domain/device_call.dart';
import '../domain/recorder_status.dart';
import '../domain/shared_audio.dart';
import '../domain/recording_match.dart';
import '../domain/unattended_calls.dart';
import 'call_back_follow_ups.dart';
import 'call_log_platform_source.dart';
import 'call_sync_api.dart';
import 'call_sync_store.dart';

enum CallSyncBlocker { noBusinessSim, permissionNeeded, unavailable }

/// Sync can't run until the employee fixes something (shown on the Sync Call History screen).
class CallSyncBlockedException implements Exception {
  const CallSyncBlockedException(this.blocker);

  final CallSyncBlocker blocker;

  @override
  String toString() => 'CallSyncBlockedException(${blocker.name})';
}

/// Downloads a recording URL to a local file (behind an abstraction for tests).
abstract class RecordingDownloader {
  Future<void> download(String url, String path);
}

class DioRecordingDownloader implements RecordingDownloader {
  DioRecordingDownloader([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<void> download(String url, String path) => _dio.download(url, path);
}

/// Settings > Sync Call History and the lead screen's recordings.
///
/// Reads the business SIM's calls from the phone's call log, sends those to lead numbers to the
/// `call-sync` Edge Function (other numbers never leave the phone), then uploads the matching
/// recordings from the employee's chosen folder and keeps a copy in the app's own storage.
class CallSyncRepository {
  CallSyncRepository({
    required this._source,
    required this._api,
    required this._store,
    required this._sims,
    RecordingDownloader? downloader,
    CallBackFollowUps? callBackFollowUps,
    DateTime Function()? clock,
  })  : _downloader = downloader ?? DioRecordingDownloader(),
        _followUps = callBackFollowUps,
        _clock = clock ?? DateTime.now;

  final CallLogPlatformSource _source;
  final CallSyncApi _api;
  final CallSyncStore _store;
  final SimRepository _sims;
  final RecordingDownloader _downloader;
  final CallBackFollowUps? _followUps;
  final DateTime Function() _clock;

  static const _batchSize = 200;

  /// A call-back reminder is due this long after the unanswered call (or in a few minutes, if that
  /// moment has passed by the time the call is synced).
  static const callBackDelay = Duration(minutes: 30);
  static const callBackMinimumLead = Duration(minutes: 5);

  /// Only calls from this far back are synced — on the first sync, on Re-sync, and if the app
  /// wasn't opened for a while. Older calls stay on the phone.
  static const syncWindow = Duration(days: 7);

  Future<SimPermissionStatus> permissionStatus() async {
    try {
      return SimPermissionStatus.fromPlatform(await _source.permissionStatus());
    } on MissingPluginException {
      return SimPermissionStatus.unavailable;
    } catch (e) {
      AppLogger.warning('Call-log permission check failed: ${e.runtimeType}');
      return SimPermissionStatus.denied;
    }
  }

  Future<SimPermissionStatus> requestPermission() async {
    try {
      return SimPermissionStatus.fromPlatform(await _source.requestPermission());
    } on MissingPluginException {
      return SimPermissionStatus.unavailable;
    } catch (e) {
      AppLogger.warning('Call-log permission request failed: ${e.runtimeType}');
      return permissionStatus();
    }
  }

  Future<CallSyncProgress> progress(String profileId, String workspaceId) => _store.load(profileId, workspaceId);

  /// Opens the folder picker and remembers the choice. Null when cancelled.
  Future<RecordingFolder?> pickRecordingFolder(String profileId, String workspaceId) async {
    final picked = RecordingFolder.fromJson(await _source.pickRecordingFolder());
    if (picked == null) return null;
    final progress = await _store.load(profileId, workspaceId);
    await _store.save(profileId, workspaceId, progress.copyWith(folder: picked));
    return picked;
  }

  Future<bool> hasFolderAccess(RecordingFolder folder) async {
    try {
      return await _source.hasFolderAccess(folder.uri);
    } catch (_) {
      return false;
    }
  }

  /// One sync run, covering at most the past [syncWindow]. [fromStart] re-reads that whole window
  /// and rescans its recordings (Re-sync).
  /// Throws [CallSyncBlockedException] or [CallSyncApiException]; nothing is marked done unless
  /// the server accepted it, so a failed run is simply retried next time.
  Future<CallSyncSummary> sync({required String profileId, required String workspaceId, bool fromStart = false}) async {
    final selection = await _sims.loadSelection(profileId);
    if (selection == null) throw const CallSyncBlockedException(CallSyncBlocker.noBusinessSim);
    final permission = await permissionStatus();
    if (permission == SimPermissionStatus.unavailable) throw const CallSyncBlockedException(CallSyncBlocker.unavailable);
    if (permission != SimPermissionStatus.granted) throw const CallSyncBlockedException(CallSyncBlocker.permissionNeeded);

    var progress = await _store.load(profileId, workspaceId);
    final now = _clock();
    final windowStart = now.subtract(syncWindow).millisecondsSinceEpoch;
    final resumeFrom = fromStart ? 0 : progress.lastCallMillis;
    final since = resumeFrom > windowStart ? resumeFrom : windowStart;

    final List<DeviceCall> calls;
    try {
      calls = [
        for (final row in (await _source.readCallLog(since) as List? ?? const []))
          ?DeviceCall.fromPlatform(row),
      ];
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') throw const CallSyncBlockedException(CallSyncBlocker.permissionNeeded);
      if (e.code == 'unavailable') throw const CallSyncBlockedException(CallSyncBlocker.unavailable);
      rethrow;
    }

    // Business SIM only. A call Android couldn't tie to a SIM counts only on a single-SIM phone.
    List<SimCard> active;
    try {
      active = await _sims.detectActiveSims();
    } catch (_) {
      active = const [];
    }
    final business = [
      for (final c in calls)
        if (c.subscriptionId == selection.subscriptionId || (c.subscriptionId == null && active.length <= 1)) c,
    ];

    final installId = await _sims.installId();
    final byKey = <String, DeviceCall>{};
    final entries = <Map<String, Object?>>[];
    for (final c in business) {
      final entry = c.toSyncEntry(installId);
      if (entry == null) continue;
      byKey[entry['key']! as String] = c;
      entries.add(entry);
    }

    final synced = <SyncedCall>[];
    var skipped = business.length - entries.length;
    for (var i = 0; i < entries.length; i += _batchSize) {
      final result = await _api.syncCalls(workspaceId, entries.sublist(i, (i + _batchSize).clamp(0, entries.length)));
      synced.addAll(result.synced);
      skipped += result.unmatched + result.invalid;
    }
    // Counts only — never numbers.
    AppLogger.info('Call sync: read ${business.length}, synced ${synced.length}, skipped $skipped');

    final pending = {for (final p in progress.pending) p.callId: p};
    for (final s in synced) {
      final call = byKey[s.key];
      if (call == null || call.durationSeconds <= 0 || progress.uploaded.contains(s.callId)) continue;
      pending.putIfAbsent(
        s.callId,
        () => PendingRecording(
          callId: s.callId,
          startMillis: call.dateMillis,
          durationSeconds: call.durationSeconds,
          phoneKey: phoneKeyOf(call.number),
        ),
      );
    }
    // A call that left the window without a recording file showing up is given up on.
    pending.removeWhere((_, p) => p.startMillis < windowStart);

    final callBacks = await _remindCallBacks(
      workspaceId: workspaceId,
      progress: progress,
      synced: synced,
      byKey: byKey,
      fromStart: fromStart,
      now: now,
    );

    final newest = calls.fold<int>(since, (max, c) => c.dateMillis > max ? c.dateMillis : max);
    progress = progress.copyWith(
      lastCallMillis: newest > progress.lastCallMillis ? newest : progress.lastCallMillis,
      pending: pending.values.toList(),
      handledUnattended: callBacks.handled,
    );
    // Save the call progress first: a recording failure must not cause calls to be re-sent forever.
    await _store.save(profileId, workspaceId, progress);

    final uploadedNow = await _uploadRecordings(profileId, workspaceId, progress);
    progress = await _store.load(profileId, workspaceId);
    final summary = CallSyncSummary(
      at: now,
      callsRead: business.length,
      callsSynced: synced.length,
      callsSkipped: skipped,
      recordingsUploaded: uploadedNow,
      recordingsWaiting: progress.pending.length,
      callBacksScheduled: callBacks.scheduled,
    );
    await _store.save(profileId, workspaceId, progress.copyWith(lastSummary: summary));
    return summary;
  }

  // ---------------------------------------------------------------- Never Attended Call Reminder

  /// Turns the reminder on or off for this employee. Turning it on starts from now: calls that went
  /// unanswered before that never get a reminder. Turning it off removes the phone alerts.
  Future<void> setNeverAttendedReminder(String profileId, String workspaceId, bool enabled) async {
    final progress = await _store.load(profileId, workspaceId);
    if (enabled == progress.neverAttendedOn) return;
    await _store.save(
      profileId,
      workspaceId,
      progress.copyWith(neverAttendedOn: enabled, neverAttendedSince: enabled ? _clock().millisecondsSinceEpoch : progress.neverAttendedSince),
    );
    if (!enabled) {
      try {
        await _source.cancelAllCallBacks();
      } catch (e) {
        AppLogger.warning('Removing call-back alerts failed: ${e.runtimeType}');
      }
    }
  }

  /// The lead a tapped call-back notification asked to open (returned once), or null.
  Future<String?> takeLaunchLead() async {
    try {
      return await _source.takeLaunchLead();
    } catch (_) {
      return null;
    }
  }

  /// For the unanswered calls of this sync: a "call back" follow-up in the CRM and a phone alert at
  /// its due time. Returns how many were made and the calls now dealt with. A lead whose reminder
  /// failed stays unhandled, so the next sync tries again.
  Future<({int scheduled, Set<String> handled})> _remindCallBacks({
    required String workspaceId,
    required CallSyncProgress progress,
    required List<SyncedCall> synced,
    required Map<String, DeviceCall> byKey,
    required bool fromStart,
    required DateTime now,
  }) async {
    final followUps = _followUps;
    if (!progress.neverAttendedOn || followUps == null) return (scheduled: 0, handled: progress.handledUnattended);

    final calls = <SyncedDeviceCall>[];
    for (final s in synced) {
      final call = byKey[s.key];
      if (call != null) calls.add(SyncedDeviceCall(callId: s.callId, leadId: s.leadId, call: call));
    }
    final plan = planCallBacks(calls: calls, sinceMillis: progress.neverAttendedSince, handled: progress.handledUnattended);
    final handled = {...progress.handledUnattended, ...plan.consideredCallIds};

    // They talked to these leads since: no alert needed. (Not on Re-sync, which also re-reads old calls.)
    if (!fromStart) {
      for (final leadId in plan.answeredLeadIds) {
        try {
          await _source.cancelCallBack(leadId);
        } catch (_) {}
      }
    }

    var scheduled = 0;
    for (final callBack in plan.callBacks) {
      final latest = callBack.latest.call;
      final earliest = latest.startedAt.add(callBackDelay);
      final soonest = now.add(callBackMinimumLead);
      final note = '${latest.unattendedLabel} at ${_clock12(latest.startedAt)}. Call back.';
      try {
        final made = await followUps.schedule(
          workspaceId: workspaceId,
          leadId: callBack.leadId,
          dueAt: earliest.isAfter(soonest) ? earliest : soonest,
          notes: note,
        );
        if (made != null) {
          await _source.scheduleCallBack(
            leadId: callBack.leadId,
            triggerAtMillis: made.dueAt.millisecondsSinceEpoch,
            title: 'Call back ${made.leadName}',
            text: note,
          );
          scheduled++;
        }
      } catch (e) {
        handled.removeAll(callBack.callIds);
        AppLogger.warning('Scheduling a call-back reminder failed: ${e is CallSyncApiException ? e.code : e.runtimeType}');
      }
    }
    if (scheduled > 0) AppLogger.info('Call sync: $scheduled call-back reminder(s) scheduled');
    return (scheduled: scheduled, handled: handled);
  }

  static String _clock12(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<int> _uploadRecordings(String profileId, String workspaceId, CallSyncProgress progress) async {
    final folder = progress.folder;
    if (folder == null || progress.pending.isEmpty) return 0;
    if (!await hasFolderAccess(folder)) {
      AppLogger.warning('Call recordings folder is no longer accessible');
      return 0;
    }

    final earliest = progress.pending.map((p) => p.startMillis).reduce((a, b) => a < b ? a : b);
    final List<RecordingFile> files;
    try {
      files = [
        for (final row in (await _source.listRecordings(folder.uri, earliest - const Duration(days: 1).inMilliseconds) as List? ?? const []))
          ?RecordingFile.fromPlatform(row),
      ];
    } catch (e) {
      AppLogger.warning('Listing call recordings failed: ${e.runtimeType}');
      return 0;
    }

    final matches = matchRecordings(progress.pending, files);
    final uploaded = {...progress.uploaded};
    var count = 0;
    String? localDir;
    for (final entry in matches.entries) {
      final callId = entry.key;
      final file = entry.value;
      try {
        final bytes = await _source.readFile(file.uri);
        final pendingCall = progress.pending.firstWhere((p) => p.callId == callId);
        final isNew = await _uploadOne(
          workspaceId: workspaceId,
          callId: callId,
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType,
          durationSeconds: pendingCall.durationSeconds,
        );
        if (isNew) count++;
        uploaded.add(callId);
        // Keep the app's own copy too, so the lead screen plays it without downloading.
        localDir ??= await _keepLocalCopy(localDir, callId, file.name, bytes);
      } catch (e) {
        // Stays pending; retried on the next sync.
        AppLogger.warning('Uploading a call recording failed: ${e is CallSyncApiException ? e.code : e.runtimeType}');
      }
    }

    final stillPending = [for (final p in progress.pending) if (!uploaded.contains(p.callId)) p];
    await _store.save(profileId, workspaceId, progress.copyWith(pending: stillPending, uploaded: uploaded));
    if (count > 0) AppLogger.info('Call sync: uploaded $count recording(s)');
    return count;
  }


  /// Uploads one recording for [callId] (slot, file, database row). False when the server already
  /// had one. Throws what the API throws.
  Future<bool> _uploadOne({
    required String workspaceId,
    required String callId,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required int durationSeconds,
  }) async {
    final slot = await _api.recordingUploadSlot(
      workspaceId: workspaceId,
      callId: callId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
    if (slot.alreadyUploaded) return false;
    await _api.uploadRecording(path: slot.path!, token: slot.token!, bytes: Uint8List.fromList(bytes), mimeType: mimeType);
    await _api.completeRecording(
      workspaceId: workspaceId,
      callId: callId,
      path: slot.path!,
      mimeType: mimeType,
      originalFileName: fileName,
      durationSeconds: durationSeconds,
    );
    return true;
  }

  /// Writes the app's own copy of a recording; returns the folder used (null if it couldn't).
  Future<String?> _keepLocalCopy(String? knownDir, String callId, String fileName, List<int> bytes) async {
    try {
      final dir = knownDir ?? await _source.recordingsDirectory();
      await File('$dir/${localRecordingName(callId, fileName)}').writeAsBytes(bytes, flush: true);
      return dir;
    } catch (e) {
      AppLogger.warning('Keeping a local recording copy failed: ${e.runtimeType}');
      return knownDir;
    }
  }

  // ---------------------------------------------------------------- Share > Sales CRM

  /// A recording shared into the app (returned once), or null.
  Future<SharedAudio?> takeSharedAudio() async {
    try {
      return SharedAudio.fromPlatform(await _source.takeSharedAudio());
    } catch (e) {
      AppLogger.warning('Reading a shared recording failed: ${e.runtimeType}');
      return null;
    }
  }

  /// The synced calls still waiting for a recording, best fit for [audio] first.
  Future<List<RecordingCandidate>> recordingCandidates(String profileId, String workspaceId, SharedAudio audio) async {
    final progress = await _store.load(profileId, workspaceId);
    return rankCandidates(progress.pending, audio, now: _clock());
  }

  /// Attaches a shared recording to [callId]: uploads it, keeps a copy on the phone, and stops that
  /// call waiting for a recording. Throws what the API throws; nothing is marked done then.
  Future<void> attachSharedRecording({
    required String profileId,
    required String workspaceId,
    required String callId,
    required SharedAudio audio,
  }) async {
    final bytes = await File(audio.path).readAsBytes();
    final progress = await _store.load(profileId, workspaceId);
    final call = progress.pending.where((p) => p.callId == callId).firstOrNull;
    await _uploadOne(
      workspaceId: workspaceId,
      callId: callId,
      bytes: bytes,
      fileName: audio.name,
      mimeType: audioMimeFor(audio.name, audio.mimeType),
      durationSeconds: call?.durationSeconds ?? audio.durationSeconds ?? 0,
    );
    await _keepLocalCopy(null, callId, audio.name, bytes);
    await _store.save(
      profileId,
      workspaceId,
      progress.copyWith(
        pending: [for (final p in progress.pending) if (p.callId != callId) p],
        uploaded: {...progress.uploaded, callId},
      ),
    );
    try {
      await File(audio.path).delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Not Sync Notification

  /// Moves the "call history not synced" reminder to last successful sync + [hours] (and on, in
  /// [hours] steps, if that moment already passed — the reminder then repeats while sync is stuck).
  /// Does nothing — and removes any reminder — until sync is set up: call-history access allowed and
  /// a business SIM chosen. Call after every sync attempt, on app start and when [hours] changes.
  Future<void> updateNotSyncReminder(String profileId, String workspaceId, int hours) async {
    try {
      final permission = await permissionStatus();
      final sim = await _sims.loadSelection(profileId);
      if (permission != SimPermissionStatus.granted || sim == null) {
        await _source.cancelNotSyncReminder();
        return;
      }
      final progress = await _store.load(profileId, workspaceId);
      final now = _clock();
      final step = Duration(hours: hours);
      // Never synced yet: count from now (the first run happens as soon as the app opens).
      var next = (progress.lastSummary?.at ?? now).add(step);
      while (!next.isAfter(now)) {
        next = next.add(step);
      }
      await _source.scheduleNotSyncReminder(triggerAtMillis: next.millisecondsSinceEpoch, hours: hours);
    } catch (e) {
      AppLogger.warning('Updating the not-synced reminder failed: ${e.runtimeType}');
    }
  }

  /// Shows the reminder now so the member can see it works. False when Android didn't show it.
  Future<bool> sendTestReminder(int hours) async {
    try {
      return await _source.showNotSyncReminderNow(hours: hours);
    } catch (e) {
      AppLogger.warning('Showing the test reminder failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<bool> notificationsAllowed() async {
    try {
      return await _source.notificationsAllowed();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestNotifications() async {
    try {
      return await _source.requestNotifications();
    } catch (e) {
      AppLogger.warning('Notification permission request failed: ${e.runtimeType}');
      return notificationsAllowed();
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _source.openNotificationSettings();
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- CRM call recorder

  Future<RecorderStatus> recorderStatus() async {
    try {
      return RecorderStatus.fromPlatform(await _source.recorderStatus());
    } catch (e) {
      AppLogger.warning('Reading recorder status failed: ${e.runtimeType}');
      return RecorderStatus.unsupported;
    }
  }

  Future<RecorderStatus> requestMicrophone() async {
    try {
      return RecorderStatus.fromPlatform(await _source.requestMicrophone());
    } catch (e) {
      AppLogger.warning('Microphone request failed: ${e.runtimeType}');
      return recorderStatus();
    }
  }

  Future<bool> openAppSettings() => _sims.openAppSettings();

  Future<bool> openAccessibilitySettings() async {
    try {
      return await _source.openAccessibilitySettings();
    } catch (_) {
      return false;
    }
  }

  /// Turns the CRM's recorder on/off for this employee and tells the native recorder what to
  /// record: calls on the business SIM, into the chosen folder. Off when either is missing.
  Future<RecorderStatus> setRecordCalls(String profileId, String workspaceId, bool enabled) async {
    final progress = await _store.load(profileId, workspaceId);
    await _store.save(profileId, workspaceId, progress.copyWith(recordCalls: enabled));
    return applyRecorderConfig(profileId, workspaceId);
  }

  /// "Auto speaker" on/off (see [CallSyncProgress.recordOnSpeaker]).
  Future<RecorderStatus> setRecordOnSpeaker(String profileId, String workspaceId, bool enabled) async {
    final progress = await _store.load(profileId, workspaceId);
    await _store.save(profileId, workspaceId, progress.copyWith(recordOnSpeaker: enabled));
    return applyRecorderConfig(profileId, workspaceId);
  }

  /// Re-sends the recorder configuration (after the SIM or folder changed, or on app start).
  Future<RecorderStatus> applyRecorderConfig(String profileId, String workspaceId) async {
    final progress = await _store.load(profileId, workspaceId);
    final sim = await _sims.loadSelection(profileId);
    final folder = progress.folder;
    final enabled = progress.recordCalls && sim != null && folder != null;
    try {
      await _source.configureRecorder(
        enabled: enabled,
        subscriptionId: sim?.subscriptionId,
        folderUri: folder?.uri,
        speaker: progress.recordOnSpeaker,
      );
    } catch (e) {
      AppLogger.warning('Configuring the call recorder failed: ${e.runtimeType}');
    }
    return recorderStatus();
  }

  /// The recordings of these calls, by call id (calls without one are left out).
  Future<Map<String, CallRecording>> recordingsByCall(String workspaceId, List<String> callIds) async {
    final result = <String, CallRecording>{};
    for (var i = 0; i < callIds.length; i += 100) {
      final batch = callIds.sublist(i, (i + 100).clamp(0, callIds.length));
      for (final r in await _api.recordingsForCalls(workspaceId, batch)) {
        result[r.callId] = r;
      }
    }
    return result;
  }

  /// Every recording of a lead, oldest call first.
  Future<List<CallRecording>> leadRecordings(String workspaceId, String leadId) => _api.leadRecordings(workspaceId, leadId);

  /// The recording on this phone, downloading it into the app's storage the first time.
  Future<File> localRecording(String workspaceId, CallRecording recording) async {
    final dir = await _source.recordingsDirectory();
    final file = File('$dir/${localRecordingName(recording.callId, recording.originalFileName ?? 'recording.${recording.extension}')}');
    if (await file.exists() && await file.length() > 0) return file;
    final url = await _api.recordingUrl(workspaceId, recording.id);
    final partial = File('${file.path}.part');
    await _downloader.download(url, partial.path);
    return partial.rename(file.path);
  }

  Future<bool> hasLocalRecording(CallRecording recording) async {
    try {
      final dir = await _source.recordingsDirectory();
      return File('$dir/${localRecordingName(recording.callId, recording.originalFileName ?? 'recording.${recording.extension}')}').exists();
    } catch (_) {
      return false;
    }
  }
}

/// `<call id>.<ext>` — one local copy per call, whatever the original name.
String localRecordingName(String callId, String originalName) {
  final dot = originalName.lastIndexOf('.');
  final ext = dot < 0 ? 'm4a' : originalName.substring(dot + 1).toLowerCase();
  final safeExt = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'm4a';
  final safeId = callId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
  return '$safeId.$safeExt';
}

/// A mime type the server accepts (`audio/<kind>`) for a recording: from the file's extension, since
/// the sender's guess is sometimes a wildcard (`audio/*`) or wrong.
String audioMimeFor(String fileName, String claimed) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  const byExtension = {
    'm4a': 'audio/mp4',
    'mp4': 'audio/mp4',
    'aac': 'audio/mp4',
    'amr': 'audio/amr',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    '3gp': 'audio/3gpp',
  };
  final known = byExtension[ext];
  if (known != null) return known;
  return RegExp(r'^audio/[a-z0-9.+-]+$', caseSensitive: false).hasMatch(claimed) ? claimed : 'audio/mp4';
}
