import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The raw Android bridge (android/.../SimChannel.kt). Behind an abstraction so `flutter test` can
/// fake it — and so nothing outside the SIM repository talks to the platform directly.
abstract class SimPlatformSource {
  /// 'granted' | 'notRequested' | 'denied' | 'permanentlyDenied' | 'unavailable'.
  Future<Object?> permissionStatus();

  /// Shows the system dialog when allowed; answers with the status afterwards.
  Future<Object?> requestPermission();

  /// A list of maps (subscriptionId, slotIndex, carrierName, displayName, phoneNumber, simState,
  /// isActive). Throws [PlatformException] with code 'permission_denied' / 'unavailable' /
  /// 'read_failed'.
  Future<Object?> activeSubscriptions();

  Future<bool> openAppSettings();
}

class MethodChannelSimSource implements SimPlatformSource {
  static const _channel = MethodChannel('com.crmapp.mobile/sim');

  // SIM subscriptions are an Android API; everywhere else the feature is simply unavailable.
  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<Object?> permissionStatus() async => _supported ? _channel.invokeMethod<String>('getPermissionStatus') : 'unavailable';

  @override
  Future<Object?> requestPermission() async => _supported ? _channel.invokeMethod<String>('requestPermission') : 'unavailable';

  @override
  Future<Object?> activeSubscriptions() async {
    if (!_supported) throw PlatformException(code: 'unavailable');
    return _channel.invokeMethod<List<Object?>>('getActiveSubscriptions');
  }

  @override
  Future<bool> openAppSettings() async => _supported && (await _channel.invokeMethod<bool>('openAppSettings') ?? false);
}
