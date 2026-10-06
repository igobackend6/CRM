import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/call_sync/data/call_back_follow_ups.dart';
import 'package:mobile/features/call_sync/data/call_log_platform_source.dart';
import 'package:mobile/features/call_sync/data/call_sync_api.dart';
import 'package:mobile/features/call_sync/data/call_sync_repository.dart';
import 'package:mobile/features/call_sync/data/call_sync_store.dart';
import 'package:mobile/features/call_sync/domain/call_recording.dart';
import 'package:mobile/features/call_sync/presentation/providers/call_sync_providers.dart';
import 'package:mobile/features/call_sync/presentation/widgets/recording_player.dart';

/// A call-log row as CallSyncChannel.readCallLog sends it.
Map<String, Object?> callRow(int id, {String? number = '+919800000001', int type = 2, required DateTime at, int duration = 60, int? sub = 1}) => {
      'id': id,
      'number': number,
      'type': type,
      'date': at.millisecondsSinceEpoch,
      'duration': duration,
      'subscriptionId': sub,
    };

/// A recordings-folder file as CallSyncChannel.listRecordings sends it.
Map<String, Object?> fileRow(String name, {required DateTime modified, String mime = 'audio/mp4', int size = 1000}) => {
      'uri': 'content://rec/$name',
      'name': name,
      'mimeType': mime,
      'size': size,
      'lastModified': modified.millisecondsSinceEpoch,
    };

class FakeCallLogSource implements CallLogPlatformSource {
  FakeCallLogSource({this.permission = 'granted', List<Map<String, Object?>>? calls, List<Map<String, Object?>>? files, this.folderAccess = true, this.localDir})
      : calls = calls ?? [],
        files = files ?? [];

  Object? permission;
  Object? afterRequest = 'granted';
  List<Map<String, Object?>> calls;
  List<Map<String, Object?>> files;
  bool folderAccess;
  Object? pickedFolder = {'uri': 'content://tree/rec', 'name': 'Music/Recordings/Call Recordings'};
  String? localDir;
  Object? readCallLogError;

  final List<int> sinceAsked = [];
  final List<String> filesRead = [];

  @override
  Future<Object?> permissionStatus() async => permission;

  @override
  Future<Object?> requestPermission() async => permission = afterRequest;

  @override
  Future<Object?> readCallLog(int sinceMillis) async {
    sinceAsked.add(sinceMillis);
    if (readCallLogError != null) throw readCallLogError!;
    return [for (final c in calls) if ((c['date']! as int) >= sinceMillis) c];
  }

  @override
  Future<Object?> pickRecordingFolder() async => pickedFolder;

  @override
  Future<bool> hasFolderAccess(String uri) async => folderAccess;

  @override
  Future<Object?> listRecordings(String folderUri, int sinceMillis) async =>
      [for (final f in files) if ((f['lastModified']! as int) >= sinceMillis) f];

  @override
  Future<Uint8List> readFile(String uri) async {
    filesRead.add(uri);
    return Uint8List.fromList(List.filled(10, 1));
  }

  /// The native recorder's state.
  Map<String, Object?> recorder = {
    'microphone': false,
    'microphoneAskedBefore': false,
    'microphoneRationale': false,
    'accessibility': false,
    'folderWritable': false,
  };
  bool micGrantOnRequest = true;
  final List<Map<String, Object?>> recorderConfigs = [];
  int accessibilityOpens = 0;

  @override
  Future<Object?> recorderStatus() async => Map<String, Object?>.from(recorder);

  @override
  Future<Object?> requestMicrophone() async {
    recorder['microphoneAskedBefore'] = true;
    if (micGrantOnRequest) recorder['microphone'] = true;
    return recorderStatus();
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    accessibilityOpens++;
    return true;
  }

  @override
  Future<Object?> configureRecorder({required bool enabled, int? subscriptionId, String? folderUri, bool speaker = true}) async {
    recorderConfigs.add({'enabled': enabled, 'subscriptionId': subscriptionId, 'folderUri': folderUri, 'speaker': speaker});
    return recorderStatus();
  }

  /// The not-synced reminder alarm: each call to schedule, and how often it was cancelled.
  final List<({int triggerAtMillis, int hours})> reminders = [];
  int reminderCancels = 0;
  Object? reminderError;

  /// Android's notification permission.
  bool notificationsOn = true;
  bool grantNotificationsOnRequest = true;
  int notificationRequests = 0;
  int notificationSettingsOpens = 0;

  @override
  Future<void> scheduleNotSyncReminder({required int triggerAtMillis, required int hours}) async {
    if (reminderError != null) throw reminderError!;
    reminders.add((triggerAtMillis: triggerAtMillis, hours: hours));
  }

  @override
  Future<void> cancelNotSyncReminder() async => reminderCancels++;

  /// Never Attended Call Reminder: the phone alerts set per lead, and which were removed.
  final Map<String, ({int triggerAtMillis, String title, String text})> callBackAlerts = {};
  final List<String> cancelledCallBacks = [];
  int cancelledAllCallBacks = 0;
  String? launchLead;

  @override
  Future<void> scheduleCallBack({required String leadId, required int triggerAtMillis, required String title, required String text}) async {
    callBackAlerts[leadId] = (triggerAtMillis: triggerAtMillis, title: title, text: text);
  }

  @override
  Future<void> cancelCallBack(String leadId) async {
    cancelledCallBacks.add(leadId);
    callBackAlerts.remove(leadId);
  }

  @override
  Future<void> cancelAllCallBacks() async {
    cancelledAllCallBacks++;
    callBackAlerts.clear();
  }

  @override
  Future<String?> takeLaunchLead() async {
    final lead = launchLead;
    launchLead = null;
    return lead;
  }

  /// A recording "shared into the app" (Share > Sales CRM), handed out once.
  Object? sharedAudio;

  @override
  Future<Object?> takeSharedAudio() async {
    final audio = sharedAudio;
    sharedAudio = null;
    return audio;
  }

  int testReminders = 0;

  @override
  Future<bool> showNotSyncReminderNow({required int hours}) async {
    if (!notificationsOn) return false;
    testReminders++;
    return true;
  }

  @override
  Future<bool> notificationsAllowed() async => notificationsOn;

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    if (grantNotificationsOnRequest) notificationsOn = true;
    return notificationsOn;
  }

  @override
  Future<bool> openNotificationSettings() async {
    notificationSettingsOpens++;
    return true;
  }

  @override
  Future<String> recordingsDirectory() async {
    if (localDir == null) throw PlatformException(code: 'unavailable');
    return localDir!;
  }
}

class FakeCallSyncApi implements CallSyncApi {
  /// Phone key (last 10 digits) -> lead id. Anything else is "not a lead".
  final Map<String, String> leads = {'9800000001': 'lead-1'};
  final Map<String, String> _callIdByKey = {};
  final List<List<Map<String, Object?>>> syncBatches = [];
  final List<String> uploadedPaths = [];
  final List<String> completed = [];
  final Set<String> alreadyUploaded = {};
  Object? syncError;
  Object? uploadError;
  List<CallRecording> recordings = [];
  Object? recordingsError;
  int urlCalls = 0;

  @override
  Future<SyncCallsResult> syncCalls(String workspaceId, List<Map<String, Object?>> entries) async {
    if (syncError != null) throw syncError!;
    syncBatches.add(entries);
    final synced = <SyncedCall>[];
    var unmatched = 0;
    for (final e in entries) {
      final phone = e['phone']! as String;
      final lead = leads[phone.substring(phone.length - 10)];
      if (lead == null) {
        unmatched++;
        continue;
      }
      final key = e['key']! as String;
      final callId = _callIdByKey.putIfAbsent(key, () => 'call-${_callIdByKey.length + 1}');
      synced.add(SyncedCall(key: key, callId: callId, leadId: lead));
    }
    return SyncCallsResult(synced: synced, unmatched: unmatched, invalid: 0);
  }

  int get storedCalls => _callIdByKey.length;

  @override
  Future<RecordingUploadSlot> recordingUploadSlot({
    required String workspaceId,
    required String callId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    if (alreadyUploaded.contains(callId)) return const RecordingUploadSlot(alreadyUploaded: true);
    return RecordingUploadSlot(alreadyUploaded: false, path: '$workspaceId/$callId/x_$fileName', token: 't');
  }

  @override
  Future<void> uploadRecording({required String path, required String token, required Uint8List bytes, required String mimeType}) async {
    if (uploadError != null) throw uploadError!;
    uploadedPaths.add(path);
  }

  @override
  Future<void> completeRecording({
    required String workspaceId,
    required String callId,
    required String path,
    required String mimeType,
    required String originalFileName,
    int? durationSeconds,
  }) async {
    completed.add(callId);
    alreadyUploaded.add(callId);
  }

  @override
  Future<List<CallRecording>> leadRecordings(String workspaceId, String leadId) async {
    if (recordingsError != null) throw recordingsError!;
    return recordings;
  }

  /// Recordings the server has, by call id (for the call list's play buttons).
  Map<String, CallRecording> recordingsByCallId = {};

  @override
  Future<List<CallRecording>> recordingsForCalls(String workspaceId, List<String> callIds) async {
    if (recordingsError != null) throw recordingsError!;
    return [for (final id in callIds) ?recordingsByCallId[id]];
  }

  @override
  Future<String> recordingUrl(String workspaceId, String recordingId) async {
    urlCalls++;
    return 'https://example.test/$recordingId';
  }
}

class FakeCallSyncStorage implements CallSyncStorage {
  String? saved;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String json) async => saved = json;
}

class FakeRecordingDownloader implements RecordingDownloader {
  final List<String> downloaded = [];
  bool fail = false;

  @override
  Future<void> download(String url, String path) async {
    if (fail) throw Exception('offline');
    downloaded.add(url);
    await File(path).writeAsBytes([1, 2, 3]);
  }
}

class FakeRecordingPlayer implements RecordingPlayer {
  final _controller = StreamController<bool>.broadcast();
  final List<String> played = [];
  int pauses = 0;

  @override
  Stream<bool> get playing => _controller.stream;

  @override
  Future<void> playFile(String path) async {
    played.add(path);
    _controller.add(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    _controller.add(false);
  }

  @override
  Future<void> dispose() async => _controller.close();
}

/// Overrides that keep every call-sync provider off the platform and network.
List<Override> callSyncOverrides({
  FakeCallLogSource? source,
  FakeCallSyncApi? api,
  FakeCallSyncStorage? storage,
  FakeRecordingDownloader? downloader,
  FakeRecordingPlayer? player,
  FakeCallBackFollowUps? followUps,
}) =>
    [
      callLogSourceProvider.overrideWithValue(source ?? FakeCallLogSource(permission: 'notRequested')),
      callSyncApiProvider.overrideWithValue(api ?? FakeCallSyncApi()),
      callSyncStorageProvider.overrideWithValue(storage ?? FakeCallSyncStorage()),
      recordingDownloaderProvider.overrideWithValue(downloader ?? FakeRecordingDownloader()),
      recordingPlayerFactoryProvider.overrideWithValue(() => player ?? FakeRecordingPlayer()),
      callBackFollowUpsProvider.overrideWithValue(followUps ?? FakeCallBackFollowUps()),
    ];

/// Creates "call back" follow-ups in memory.
class FakeCallBackFollowUps implements CallBackFollowUps {
  /// Leads that already have a pending follow-up: nothing is created for them.
  final Set<String> leadsWithPending = {};
  final Map<String, String> leadNames = {};
  Object? error;
  final List<({String leadId, DateTime dueAt, String notes})> created = [];

  @override
  Future<ScheduledCallBack?> schedule({
    required String workspaceId,
    required String leadId,
    required DateTime dueAt,
    required String notes,
  }) async {
    if (error != null) throw error!;
    if (leadsWithPending.contains(leadId)) return null;
    created.add((leadId: leadId, dueAt: dueAt, notes: notes));
    return ScheduledCallBack(leadName: leadNames[leadId] ?? 'Suguna', dueAt: dueAt);
  }
}
