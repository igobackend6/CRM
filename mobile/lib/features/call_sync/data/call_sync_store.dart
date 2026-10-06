import 'dart:convert';

import '../../../services/storage/secure_storage_service.dart';
import '../domain/recording_match.dart';

/// Saves call-sync progress on this phone as one string — the same shape as the app's other
/// local stores.
abstract class CallSyncStorage {
  Future<String?> read();

  Future<void> write(String json);
}

class SecureCallSyncStorage implements CallSyncStorage {
  SecureCallSyncStorage([SecureStorageService? storage]) : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  static const _key = 'call_sync';

  @override
  Future<String?> read() => _storage.read(_key);

  @override
  Future<void> write(String json) => _storage.write(_key, json);
}

/// The folder the employee picked for call recordings.
class RecordingFolder {
  const RecordingFolder({required this.uri, required this.name});

  final String uri;
  final String name;

  Map<String, Object?> toJson() => {'uri': uri, 'name': name};

  static RecordingFolder? fromJson(Object? json) {
    if (json is! Map || json['uri'] is! String) return null;
    return RecordingFolder(uri: json['uri'] as String, name: json['name'] is String ? json['name'] as String : 'Selected folder');
  }
}

/// What the last sync did — shown on Settings > Sync Call History.
class CallSyncSummary {
  const CallSyncSummary({
    required this.at,
    this.callsRead = 0,
    this.callsSynced = 0,
    this.callsSkipped = 0,
    this.recordingsUploaded = 0,
    this.recordingsWaiting = 0,
    this.callBacksScheduled = 0,
  });

  final DateTime at;

  /// Business-SIM calls read from the phone in this run.
  final int callsRead;

  /// Of those, calls to lead numbers now in the CRM.
  final int callsSynced;

  /// Calls to numbers that aren't leads — left on the phone.
  final int callsSkipped;
  final int recordingsUploaded;

  /// Synced calls whose recording hasn't been found/uploaded yet.
  final int recordingsWaiting;

  /// "Call back" reminders created in this run (Never Attended Call Reminder).
  final int callBacksScheduled;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'read': callsRead,
        'synced': callsSynced,
        'skipped': callsSkipped,
        'uploaded': recordingsUploaded,
        'waiting': recordingsWaiting,
        'callBacks': callBacksScheduled,
      };

  static CallSyncSummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (at == null) return null;
    int n(Object? v) => v is int ? v : 0;
    return CallSyncSummary(
      at: at.toLocal(),
      callsRead: n(json['read']),
      callsSynced: n(json['synced']),
      callsSkipped: n(json['skipped']),
      recordingsUploaded: n(json['uploaded']),
      recordingsWaiting: n(json['waiting']),
      callBacksScheduled: n(json['callBacks']),
    );
  }
}

/// Call-sync progress for one employee in one workspace on this phone.
class CallSyncProgress {
  const CallSyncProgress({
    this.lastCallMillis = 0,
    this.recordCalls = false,
    this.recordOnSpeaker = true,
    this.neverAttendedOn = false,
    this.neverAttendedSince = 0,
    this.handledUnattended = const {},
    this.folder,
    this.pending = const [],
    this.uploaded = const {},
    this.lastSummary,
  });

  /// Start time of the newest call-log row already sent (0 = never synced: send everything).
  final int lastCallMillis;

  /// Settings > Sync Call History > Record calls (the CRM's own recorder).
  final bool recordCalls;

  /// "Auto speaker": while a call is recorded, the call is put on the loudspeaker so the microphone
  /// also hears the customer (the recorder can't tap the call audio itself).
  final bool recordOnSpeaker;

  /// Settings > Never Attended Call Reminder > Remind Me. Only calls after [neverAttendedSince]
  /// (when it was turned on) get a reminder.
  final bool neverAttendedOn;
  final int neverAttendedSince;

  /// Unattended calls already dealt with (reminder made, or not needed) — never judged twice.
  final Set<String> handledUnattended;
  final RecordingFolder? folder;
  final List<PendingRecording> pending;

  /// CRM call ids whose recording is uploaded (so it's never uploaded twice).
  final Set<String> uploaded;
  final CallSyncSummary? lastSummary;

  CallSyncProgress copyWith({
    int? lastCallMillis,
    bool? recordCalls,
    bool? recordOnSpeaker,
    bool? neverAttendedOn,
    int? neverAttendedSince,
    Set<String>? handledUnattended,
    RecordingFolder? folder,
    List<PendingRecording>? pending,
    Set<String>? uploaded,
    CallSyncSummary? lastSummary,
  }) =>
      CallSyncProgress(
        lastCallMillis: lastCallMillis ?? this.lastCallMillis,
        recordCalls: recordCalls ?? this.recordCalls,
        recordOnSpeaker: recordOnSpeaker ?? this.recordOnSpeaker,
        neverAttendedOn: neverAttendedOn ?? this.neverAttendedOn,
        neverAttendedSince: neverAttendedSince ?? this.neverAttendedSince,
        handledUnattended: handledUnattended ?? this.handledUnattended,
        folder: folder ?? this.folder,
        pending: pending ?? this.pending,
        uploaded: uploaded ?? this.uploaded,
        lastSummary: lastSummary ?? this.lastSummary,
      );

  Map<String, Object?> toJson() => {
        'lastCall': lastCallMillis,
        'recordCalls': recordCalls,
        'recordOnSpeaker': recordOnSpeaker,
        'neverAttended': neverAttendedOn,
        'neverAttendedSince': neverAttendedSince,
        // Bounded: only the most recent matter (a call is only judged within the 7-day window).
        'handledUnattended': handledUnattended.length > 500 ? handledUnattended.skip(handledUnattended.length - 500).toList() : handledUnattended.toList(),
        'folder': folder?.toJson(),
        'pending': [for (final p in pending) p.toJson()],
        // Bounded: the newest 2000 are plenty to avoid re-uploads (the server also refuses doubles).
        'uploaded': uploaded.length > 2000 ? uploaded.skip(uploaded.length - 2000).toList() : uploaded.toList(),
        'summary': lastSummary?.toJson(),
      };

  static CallSyncProgress fromJson(Object? json) {
    if (json is! Map) return const CallSyncProgress();
    final last = json['lastCall'];
    return CallSyncProgress(
      lastCallMillis: last is int ? last : 0,
      recordCalls: json['recordCalls'] == true,
      // On unless the member turned it off (also for saves from before this option existed).
      recordOnSpeaker: json['recordOnSpeaker'] != false,
      neverAttendedOn: json['neverAttended'] == true,
      neverAttendedSince: json['neverAttendedSince'] is int ? json['neverAttendedSince'] as int : 0,
      handledUnattended: {for (final id in (json['handledUnattended'] is List ? json['handledUnattended'] as List : const [])) if (id is String) id},
      folder: RecordingFolder.fromJson(json['folder']),
      pending: [
        for (final p in (json['pending'] is List ? json['pending'] as List : const []))
          ?PendingRecording.fromJson(p),
      ],
      uploaded: {for (final id in (json['uploaded'] is List ? json['uploaded'] as List : const [])) if (id is String) id},
      lastSummary: CallSyncSummary.fromJson(json['summary']),
    );
  }
}

/// Reads/writes [CallSyncProgress] per employee+workspace inside one stored document.
class CallSyncStore {
  CallSyncStore(this._storage);

  final CallSyncStorage _storage;

  static String _scope(String profileId, String workspaceId) => '$profileId|$workspaceId';

  Future<Map<String, Object?>> _doc() async {
    final raw = await _storage.read();
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  Future<CallSyncProgress> load(String profileId, String workspaceId) async =>
      CallSyncProgress.fromJson((await _doc())[_scope(profileId, workspaceId)]);

  Future<void> save(String profileId, String workspaceId, CallSyncProgress progress) async {
    final doc = await _doc();
    doc[_scope(profileId, workspaceId)] = progress.toJson();
    await _storage.write(jsonEncode(doc));
  }
}
