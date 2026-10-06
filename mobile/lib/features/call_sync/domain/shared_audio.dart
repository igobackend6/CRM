import 'recording_match.dart';

/// A call recording that was shared into the app (Share > Sales CRM), already copied into the app's cache.
class SharedAudio {
  const SharedAudio({required this.path, required this.name, required this.mimeType, required this.sizeBytes, this.durationMillis});

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  /// How long the recording runs, when the phone could tell.
  final int? durationMillis;

  int? get durationSeconds => durationMillis == null ? null : (durationMillis! / 1000).round();

  /// When the call was recorded, if the file name says so: Google Phone names its recordings
  /// `record-<epoch milliseconds>.wav`, and that moment is the start of the call.
  DateTime? get recordedAt {
    final m = RegExp(r'(?<!\d)(1[5-9]\d{11})(?!\d)').firstMatch(name);
    final millis = m == null ? null : int.tryParse(m.group(1)!);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static SharedAudio? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final name = raw['name'];
    final mime = raw['mimeType'];
    final size = raw['size'];
    final duration = raw['durationMillis'];
    if (path is! String || path.isEmpty || size is! num) return null;
    return SharedAudio(
      path: path,
      name: name is String && name.isNotEmpty ? name : 'shared recording',
      mimeType: mime is String ? mime : 'audio/mp4',
      sizeBytes: size.toInt(),
      durationMillis: duration is num ? duration.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) => other is SharedAudio && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A synced call a shared recording might belong to.
class RecordingCandidate {
  const RecordingCandidate({required this.call, required this.differenceSeconds, required this.likely});

  final PendingRecording call;

  /// How far the call's talk time is from the recording's length (null when the length is unknown).
  final int? differenceSeconds;

  /// Close enough in length that this is probably the call.
  final bool likely;
}

/// Orders the calls still waiting for a recording by how well they fit [audio].
///
/// When the file name carries the moment the call started (Google Phone's `record-<millis>.wav`),
/// that is exact: the call that started then comes first and is the likely one, and if no waiting
/// call started then (it may not have synced yet) nothing is pre-selected, so a wrong call is never
/// guessed. Without a time, a recording can be shorter than its call (recording started part-way in)
/// but never longer, so every call at least as long as the recording (give or take a few seconds)
/// is a fit, the most recent fit comes first, and it is [RecordingCandidate.likely] when it started
/// within the last [_likelyWindow].
List<RecordingCandidate> rankCandidates(List<PendingRecording> pending, SharedAudio audio, {DateTime? now}) {
  final seconds = audio.durationSeconds;
  final recordedAt = audio.recordedAt?.millisecondsSinceEpoch;
  if (recordedAt != null) {
    final byTime = [for (final c in pending) if (c.durationSeconds > 0) c]
      ..sort((a, b) => (a.startMillis - recordedAt).abs().compareTo((b.startMillis - recordedAt).abs()));
    return [
      for (var i = 0; i < byTime.length; i++)
        RecordingCandidate(
          call: byTime[i],
          differenceSeconds: seconds == null ? null : (seconds - byTime[i].durationSeconds).abs(),
          likely: i == 0 && (byTime[i].startMillis - recordedAt).abs() <= recordingTimeTolerance.inMilliseconds,
        ),
    ];
  }
  bool fits(PendingRecording c) => seconds == null || seconds <= c.durationSeconds + _toleranceSeconds(c.durationSeconds);
  final candidates = [for (final call in pending) if (call.durationSeconds > 0) call];
  final fitting = [for (final c in candidates) if (fits(c)) c]..sort((a, b) => b.startMillis.compareTo(a.startMillis));
  final others = [for (final c in candidates) if (!fits(c)) c]
    ..sort((a, b) {
      final da = (seconds! - a.durationSeconds).abs(), db = (seconds - b.durationSeconds).abs();
      return da != db ? da.compareTo(db) : b.startMillis.compareTo(a.startMillis);
    });
  final clock = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final newestFit = fitting.firstOrNull;
  final newestIsRecent = seconds != null && newestFit != null && clock - newestFit.startMillis <= _likelyWindow.inMilliseconds;
  return [
    for (final c in [...fitting, ...others])
      RecordingCandidate(
        call: c,
        differenceSeconds: seconds == null ? null : (seconds - c.durationSeconds).abs(),
        likely: newestIsRecent && identical(c, newestFit),
      ),
  ];
}

const _likelyWindow = Duration(hours: 12);

int _toleranceSeconds(int callSeconds) {
  final relative = (callSeconds * 0.12).round();
  return relative < 6 ? 6 : relative;
}
