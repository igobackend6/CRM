import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/call_recording.dart';

/// A call the server accepted (new or already synced): the phone's key -> the CRM call.
class SyncedCall {
  const SyncedCall({required this.key, required this.callId, required this.leadId});

  final String key;
  final String callId;
  final String leadId;
}

class SyncCallsResult {
  const SyncCallsResult({required this.synced, required this.unmatched, required this.invalid});

  final List<SyncedCall> synced;

  /// Calls whose number isn't a lead the employee can see — never stored.
  final int unmatched;
  final int invalid;
}

/// A signed upload slot for one call's recording, or [alreadyUploaded].
class RecordingUploadSlot {
  const RecordingUploadSlot({required this.alreadyUploaded, this.path, this.token});

  final bool alreadyUploaded;
  final String? path;
  final String? token;
}

/// A failure the server explained (its `error.code`), e.g. `forbidden`, `not_found`.
class CallSyncApiException implements Exception {
  const CallSyncApiException(this.code, [this.status]);

  final String code;
  final int? status;

  @override
  String toString() => 'CallSyncApiException($code, $status)';
}

/// The `call-sync` Supabase Edge Function plus the recording upload it hands out. The signed-in
/// session's JWT goes with every call, so the server applies the employee's own RLS.
abstract class CallSyncApi {
  Future<SyncCallsResult> syncCalls(String workspaceId, List<Map<String, Object?>> entries);

  Future<RecordingUploadSlot> recordingUploadSlot({
    required String workspaceId,
    required String callId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  });

  Future<void> uploadRecording({required String path, required String token, required Uint8List bytes, required String mimeType});

  Future<void> completeRecording({
    required String workspaceId,
    required String callId,
    required String path,
    required String mimeType,
    required String originalFileName,
    int? durationSeconds,
  });

  Future<List<CallRecording>> leadRecordings(String workspaceId, String leadId);

  /// The recordings of the given calls (at most 100), for the call list's play buttons.
  Future<List<CallRecording>> recordingsForCalls(String workspaceId, List<String> callIds);

  /// A short-lived URL to download one recording.
  Future<String> recordingUrl(String workspaceId, String recordingId);
}

class SupabaseCallSyncApi implements CallSyncApi {
  SupabaseCallSyncApi(this._client);

  final SupabaseClient _client;

  static const _function = 'call-sync';
  static const _bucket = 'call-recordings';

  Future<Map<String, Object?>> _invoke(Map<String, Object?> body) async {
    try {
      final response = await _client.functions.invoke(_function, body: body);
      final data = response.data;
      if (data is Map) return Map<String, Object?>.from(data);
      throw const CallSyncApiException('bad_response');
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map && details['error'] is Map ? (details['error'] as Map)['code']?.toString() : null;
      throw CallSyncApiException(code ?? 'server_error', e.status);
    }
  }

  @override
  Future<SyncCallsResult> syncCalls(String workspaceId, List<Map<String, Object?>> entries) async {
    final data = await _invoke({'action': 'sync_calls', 'workspace_id': workspaceId, 'entries': entries});
    final synced = <SyncedCall>[];
    for (final row in (data['synced'] as List? ?? const [])) {
      if (row is Map && row['key'] is String && row['call_id'] is String && row['lead_id'] is String) {
        synced.add(SyncedCall(key: row['key'] as String, callId: row['call_id'] as String, leadId: row['lead_id'] as String));
      }
    }
    int count(Object? v) => v is num ? v.toInt() : 0;
    return SyncCallsResult(synced: synced, unmatched: count(data['unmatched']), invalid: count(data['invalid']));
  }

  @override
  Future<RecordingUploadSlot> recordingUploadSlot({
    required String workspaceId,
    required String callId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final data = await _invoke({
      'action': 'recording_upload_url',
      'workspace_id': workspaceId,
      'call_id': callId,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    });
    if (data['already_uploaded'] == true) return const RecordingUploadSlot(alreadyUploaded: true);
    final path = data['path'];
    final token = data['token'];
    if (path is! String || token is! String) throw const CallSyncApiException('bad_response');
    return RecordingUploadSlot(alreadyUploaded: false, path: path, token: token);
  }

  @override
  Future<void> uploadRecording({required String path, required String token, required Uint8List bytes, required String mimeType}) async {
    try {
      await _client.storage.from(_bucket).uploadBinaryToSignedUrl(path, token, bytes, FileOptions(contentType: mimeType));
    } on StorageException catch (e) {
      throw CallSyncApiException('upload_failed', int.tryParse(e.statusCode ?? ''));
    }
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
    await _invoke({
      'action': 'recording_complete',
      'workspace_id': workspaceId,
      'call_id': callId,
      'path': path,
      'mime_type': mimeType,
      'original_file_name': originalFileName,
      'duration_seconds': ?durationSeconds,
    });
  }

  @override
  Future<List<CallRecording>> recordingsForCalls(String workspaceId, List<String> callIds) async {
    if (callIds.isEmpty) return const [];
    final data = await _invoke({'action': 'recordings_for_calls', 'workspace_id': workspaceId, 'call_ids': callIds});
    return [
      for (final row in (data['recordings'] as List? ?? const []))
        ?CallRecording.fromJson(row),
    ];
  }

  @override
  Future<List<CallRecording>> leadRecordings(String workspaceId, String leadId) async {
    final data = await _invoke({'action': 'lead_recordings', 'workspace_id': workspaceId, 'lead_id': leadId});
    return [
      for (final row in (data['recordings'] as List? ?? const []))
        ?CallRecording.fromJson(row),
    ];
  }

  @override
  Future<String> recordingUrl(String workspaceId, String recordingId) async {
    final data = await _invoke({'action': 'recording_url', 'workspace_id': workspaceId, 'recording_id': recordingId});
    final url = data['url'];
    if (url is! String) throw const CallSyncApiException('bad_response');
    return url;
  }
}
