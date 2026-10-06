/// Where the CRM's own call recorder stands (Settings > Sync Call History > Record calls).
class RecorderStatus {
  const RecorderStatus({
    this.supported = true,
    this.microphone = false,
    this.microphonePermanentlyDenied = false,
    this.accessibility = false,
    this.folderWritable = false,
  });

  /// False off Android.
  final bool supported;
  final bool microphone;

  /// Refused for good: only Android Settings can allow it now.
  final bool microphonePermanentlyDenied;

  /// The "Sales CRM call recorder" accessibility service is turned on.
  final bool accessibility;

  /// The recordings folder can be written to (picked with write access).
  final bool folderWritable;

  /// Everything the recorder needs is in place.
  bool get ready => supported && microphone && accessibility && folderWritable;

  static const unsupported = RecorderStatus(supported: false);

  static RecorderStatus fromPlatform(Object? raw) {
    if (raw is! Map) return unsupported;
    bool flag(String key) => raw[key] == true;
    final mic = flag('microphone');
    return RecorderStatus(
      microphone: mic,
      // Asked before and Android no longer offers the rationale -> "Don't ask again".
      microphonePermanentlyDenied: !mic && flag('microphoneAskedBefore') && !flag('microphoneRationale'),
      accessibility: flag('accessibility'),
      folderWritable: flag('folderWritable'),
    );
  }
}
