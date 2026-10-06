/// A recording stored in the CRM (call_recordings + its call), as the call-sync Edge Function's
/// `lead_recordings` action returns it.
class CallRecording {
  const CallRecording({
    required this.id,
    required this.callId,
    required this.callStartedAt,
    required this.direction,
    this.mimeType,
    this.sizeBytes,
    this.durationSeconds,
    this.callDurationSeconds,
    this.originalFileName,
  });

  final String id;
  final String callId;
  final DateTime callStartedAt;

  /// 'inbound' / 'outbound'.
  final String direction;
  final String? mimeType;
  final int? sizeBytes;
  final int? durationSeconds;
  final int? callDurationSeconds;
  final String? originalFileName;

  /// File extension for the local copy.
  String get extension {
    final name = originalFileName;
    if (name != null && name.contains('.')) {
      final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    }
    return switch (mimeType) {
      'audio/amr' => 'amr',
      'audio/mpeg' => 'mp3',
      'audio/wav' => 'wav',
      'audio/ogg' => 'ogg',
      'audio/3gpp' => '3gp',
      _ => 'm4a',
    };
  }

  static CallRecording? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final callId = json['call_id'];
    final call = json['call'];
    if (id is! String || callId is! String || call is! Map) return null;
    final started = DateTime.tryParse(call['started_at']?.toString() ?? '');
    if (started == null) return null;
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return CallRecording(
      id: id,
      callId: callId,
      callStartedAt: started.toLocal(),
      direction: call['direction'] == 'inbound' ? 'inbound' : 'outbound',
      mimeType: json['mime_type'] is String ? json['mime_type'] as String : null,
      sizeBytes: asInt(json['size_bytes']),
      durationSeconds: asInt(json['duration_seconds']),
      callDurationSeconds: asInt(call['duration_seconds']),
      originalFileName: json['original_file_name'] is String ? json['original_file_name'] as String : null,
    );
  }
}
