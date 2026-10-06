import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android bridge for call-log sync (android/.../CallSyncChannel.kt). Behind an abstraction
/// so tests can fake it and nothing outside the call-sync repository touches the platform.
abstract class CallLogPlatformSource {
  /// 'granted' | 'notRequested' | 'denied' | 'permanentlyDenied' | 'unavailable'.
  Future<Object?> permissionStatus();

  Future<Object?> requestPermission();

  /// Call-log rows since [sinceMillis], oldest first.
  Future<Object?> readCallLog(int sinceMillis);

  /// Opens Android's folder picker. Null when cancelled, else {uri, name}.
  Future<Object?> pickRecordingFolder();

  Future<bool> hasFolderAccess(String uri);

  /// Audio files in the picked folder modified since [sinceMillis].
  Future<Object?> listRecordings(String folderUri, int sinceMillis);

  Future<Uint8List> readFile(String uri);

  /// The app's own folder for downloaded recordings.
  Future<String> recordingsDirectory();

  /// The CRM's own call recorder: {microphone, microphoneAskedBefore, microphoneRationale,
  /// accessibility, folderWritable}.
  Future<Object?> recorderStatus();

  Future<Object?> requestMicrophone();

  /// Android Settings > Accessibility, where the employee turns the recorder on.
  Future<bool> openAccessibilitySettings();

  /// What the recorder should do (it runs natively, even with the app closed).
  Future<Object?> configureRecorder({required bool enabled, int? subscriptionId, String? folderUri, bool speaker = true});

  /// Sets the single "call history not synced" reminder alarm (replacing any earlier one). It fires
  /// even with the app closed, then repeats every [hours] hours until it is moved or cancelled.
  Future<void> scheduleNotSyncReminder({required int triggerAtMillis, required int hours});

  Future<void> cancelNotSyncReminder();

  /// A phone alert for the "call back" follow-up of [leadId], at [triggerAtMillis] (a newer one for
  /// the same lead replaces the older). Tapping it opens that lead.
  Future<void> scheduleCallBack({required String leadId, required int triggerAtMillis, required String title, required String text});

  Future<void> cancelCallBack(String leadId);

  Future<void> cancelAllCallBacks();

  /// The lead a tapped call-back notification asked to open (once), or null.
  Future<String?> takeLaunchLead();

  /// A recording shared into the app (Share > Sales CRM), copied to the app's cache; returned once.
  Future<Object?> takeSharedAudio();

  /// Shows the reminder right now, to check notifications work on this phone. False if not shown.
  Future<bool> showNotSyncReminderNow({required int hours});

  /// Whether Android lets the app show notifications.
  Future<bool> notificationsAllowed();

  /// Shows the system permission dialog where Android has one (13+); answers whether allowed after.
  Future<bool> requestNotifications();

  /// The app's notification page in Android Settings.
  Future<bool> openNotificationSettings();
}

class MethodChannelCallLogSource implements CallLogPlatformSource {
  static const _channel = MethodChannel('com.crmapp.mobile/call_sync');

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _ensure() {
    if (!_supported) throw PlatformException(code: 'unavailable');
  }

  @override
  Future<Object?> permissionStatus() async => _supported ? _channel.invokeMethod<String>('getPermissionStatus') : 'unavailable';

  @override
  Future<Object?> requestPermission() async => _supported ? _channel.invokeMethod<String>('requestPermission') : 'unavailable';

  @override
  Future<Object?> readCallLog(int sinceMillis) async {
    _ensure();
    return _channel.invokeMethod<List<Object?>>('readCallLog', {'sinceMillis': sinceMillis});
  }

  @override
  Future<Object?> pickRecordingFolder() async {
    _ensure();
    return _channel.invokeMethod<Map<Object?, Object?>>('pickRecordingFolder');
  }

  @override
  Future<bool> hasFolderAccess(String uri) async =>
      _supported && (await _channel.invokeMethod<bool>('hasFolderAccess', {'uri': uri}) ?? false);

  @override
  Future<Object?> listRecordings(String folderUri, int sinceMillis) async {
    _ensure();
    return _channel.invokeMethod<List<Object?>>('listRecordings', {'uri': folderUri, 'sinceMillis': sinceMillis});
  }

  @override
  Future<Uint8List> readFile(String uri) async {
    _ensure();
    final bytes = await _channel.invokeMethod<Uint8List>('readFile', {'uri': uri});
    if (bytes == null) throw PlatformException(code: 'read_failed');
    return bytes;
  }

  @override
  Future<Object?> recorderStatus() async => _supported ? _channel.invokeMethod<Map<Object?, Object?>>('recorderStatus') : null;

  @override
  Future<Object?> requestMicrophone() async {
    _ensure();
    return _channel.invokeMethod<Map<Object?, Object?>>('requestMicrophone');
  }

  @override
  Future<bool> openAccessibilitySettings() async =>
      _supported && (await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false);

  @override
  Future<Object?> configureRecorder({required bool enabled, int? subscriptionId, String? folderUri, bool speaker = true}) async {
    if (!_supported) return null;
    return _channel.invokeMethod<Map<Object?, Object?>>(
      'configureRecorder',
      {'enabled': enabled, 'subscriptionId': subscriptionId, 'folderUri': folderUri, 'speaker': speaker},
    );
  }

  @override
  Future<void> scheduleNotSyncReminder({required int triggerAtMillis, required int hours}) async {
    if (!_supported) return;
    await _channel.invokeMethod<bool>('scheduleNotSyncReminder', {'triggerAtMillis': triggerAtMillis, 'hours': hours});
  }

  @override
  Future<void> cancelNotSyncReminder() async {
    if (!_supported) return;
    await _channel.invokeMethod<bool>('cancelNotSyncReminder');
  }

  @override
  Future<void> scheduleCallBack({required String leadId, required int triggerAtMillis, required String title, required String text}) async {
    if (!_supported) return;
    await _channel.invokeMethod<bool>(
      'scheduleCallBack',
      {'leadId': leadId, 'triggerAtMillis': triggerAtMillis, 'title': title, 'text': text},
    );
  }

  @override
  Future<void> cancelCallBack(String leadId) async {
    if (!_supported) return;
    await _channel.invokeMethod<bool>('cancelCallBack', {'leadId': leadId});
  }

  @override
  Future<void> cancelAllCallBacks() async {
    if (!_supported) return;
    await _channel.invokeMethod<bool>('cancelAllCallBacks');
  }

  @override
  Future<Object?> takeSharedAudio() async => _supported ? _channel.invokeMethod<Map<Object?, Object?>>('takeSharedAudio') : null;

  @override
  Future<String?> takeLaunchLead() async => _supported ? _channel.invokeMethod<String>('takeLaunchLead') : null;

  @override
  Future<bool> showNotSyncReminderNow({required int hours}) async =>
      _supported && (await _channel.invokeMethod<bool>('showNotSyncReminderNow', {'hours': hours}) ?? false);

  @override
  Future<bool> notificationsAllowed() async => _supported && (await _channel.invokeMethod<bool>('notificationsAllowed') ?? false);

  @override
  Future<bool> requestNotifications() async => _supported && (await _channel.invokeMethod<bool>('requestNotifications') ?? false);

  @override
  Future<bool> openNotificationSettings() async =>
      _supported && (await _channel.invokeMethod<bool>('openNotificationSettings') ?? false);

  @override
  Future<String> recordingsDirectory() async {
    _ensure();
    final dir = await _channel.invokeMethod<String>('recordingsDirectory');
    if (dir == null) throw PlatformException(code: 'unavailable');
    return dir;
  }
}
