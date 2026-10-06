/// A synced CRM call that still needs its recording uploaded.
class PendingRecording {
  const PendingRecording({
    required this.callId,
    required this.startMillis,
    required this.durationSeconds,
    this.phoneKey,
  });

  final String callId;
  final int startMillis;
  final int durationSeconds;

  /// Last 10 digits of the number, to recognise it in a file name.
  final String? phoneKey;

  int get endMillis => startMillis + durationSeconds * 1000;

  Map<String, Object?> toJson() => {'callId': callId, 'start': startMillis, 'duration': durationSeconds, 'phoneKey': phoneKey};

  static PendingRecording? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['callId'];
    final start = json['start'];
    final duration = json['duration'];
    if (id is! String || start is! int || duration is! int) return null;
    final key = json['phoneKey'];
    return PendingRecording(callId: id, startMillis: start, durationSeconds: duration, phoneKey: key is String ? key : null);
  }
}

/// An audio file in the employee's call-recordings folder.
class RecordingFile {
  const RecordingFile({required this.uri, required this.name, required this.mimeType, required this.size, required this.lastModifiedMillis});

  final String uri;
  final String name;
  final String mimeType;
  final int size;
  final int lastModifiedMillis;

  static RecordingFile? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final uri = raw['uri'];
    final name = raw['name'];
    final mime = raw['mimeType'];
    final size = raw['size'];
    final modified = raw['lastModified'];
    if (uri is! String || name is! String || mime is! String || size is! int || modified is! int) return null;
    return RecordingFile(uri: uri, name: name, mimeType: mime, size: size, lastModifiedMillis: modified);
  }
}

/// How far a file's last-modified time may be from the call's end (recorders finish writing a
/// moment after hang-up; some stamp the start instead).
const recordingTimeTolerance = Duration(minutes: 3);

/// Pairs pending calls with recording files. The phone's recorder doesn't tell us which call a
/// file belongs to, so this uses what is reliable:
///  * the file was last written around the call's end (or start) — within [recordingTimeTolerance];
///  * a file whose name carries a different phone number is never used; one carrying this call's
///    number is preferred.
/// Each file and each call is used at most once; ties go to the closest time.
Map<String, RecordingFile> matchRecordings(List<PendingRecording> calls, List<RecordingFile> files) {
  final tolerance = recordingTimeTolerance.inMilliseconds;
  final candidates = <({PendingRecording call, RecordingFile file, int score})>[];
  for (final call in calls) {
    if (call.durationSeconds <= 0) continue;
    for (final file in files) {
      final numbers = _numbersIn(file.name);
      final named = call.phoneKey != null && numbers.contains(call.phoneKey);
      if (numbers.isNotEmpty && !named) continue;
      final gap = [
        (file.lastModifiedMillis - call.endMillis).abs(),
        (file.lastModifiedMillis - call.startMillis).abs(),
      ].reduce((a, b) => a < b ? a : b);
      // The recording can't have been finished before the call even started.
      if (gap > tolerance || file.lastModifiedMillis < call.startMillis - tolerance) continue;
      candidates.add((call: call, file: file, score: named ? gap - tolerance : gap));
    }
  }
  candidates.sort((a, b) => a.score.compareTo(b.score));
  final result = <String, RecordingFile>{};
  final usedFiles = <String>{};
  for (final c in candidates) {
    if (result.containsKey(c.call.callId) || usedFiles.contains(c.file.uri)) continue;
    result[c.call.callId] = c.file;
    usedFiles.add(c.file.uri);
  }
  return result;
}

/// Last-10-digit keys of any phone numbers (10–13 digit runs) in a file name. Date/time stamps
/// like 20261001_163000 are split by separators, and runs of 14+ digits (timestamps) are ignored.
Set<String> _numbersIn(String name) {
  final keys = <String>{};
  for (final m in RegExp(r'\+?\d[\d ]{8,15}\d').allMatches(name)) {
    final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 13) continue;
    if (_looksLikeStamp(digits)) continue;
    keys.add(digits.substring(digits.length - 10));
  }
  return keys;
}

/// Some phone recorders name a file `<contact name>-yyMMddHHmm.mp3` (e.g. `Suguna-2610051711.mp3`):
/// a 10-digit date stamp, not a phone number. Indian mobile numbers start with 6-9, so a run that
/// starts with 1 or 2 and reads as a valid year-month-day-hour-minute is a time stamp.
bool _looksLikeStamp(String digits) =>
    digits.length == 10 && RegExp(r'^[12]\d(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])([01]\d|2[0-3])[0-5]\d$').hasMatch(digits);
