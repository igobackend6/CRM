import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/native_dialer_models.dart';

/// The CRM's own phone-app features, from Android's Telecom framework
/// (android/.../DialerChannel.kt). Behind an abstraction so tests can fake it and no other code
/// touches the platform channel. Phone numbers are never logged.
abstract class NativeDialerService {
  Future<DialerRoleStatus> status();

  /// Shows Android's "Set as default Phone app" dialog; true if the CRM is the Phone app afterwards.
  Future<bool> requestDefaultDialer();

  /// Android's Default apps page, where the member chooses another Phone app (Android has no API
  /// for an app to hand the role back).
  Future<bool> openDefaultAppsSettings();

  Future<List<PhoneAccountInfo>> phoneAccounts();

  Future<bool> hasCallPermission();

  Future<bool> requestCallPermission();

  /// Places a normal carrier call through Telecom, on [subscriptionId]'s SIM when given.
  Future<PlaceCallResult> placeCall(String number, {int? subscriptionId});

  /// Hands the dialer a short list of the member's leads so an incoming call can show who it is
  /// even when the app isn't running.
  Future<void> updateLeadCache(List<({String name, String phone, String? status})> leads);

  /// A number another app asked the dialer to show (a tel: link), returned once.
  Future<String?> takeDialNumber();

  /// Live updates about every call (ringing, dialling, active, ended).
  Stream<NativeCallEvent> get callEvents;
}

class MethodChannelNativeDialerService implements NativeDialerService {
  static const _channel = MethodChannel('com.crmapp.mobile/dialer');
  static const _events = EventChannel('com.crmapp.mobile/dialer_events');

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<DialerRoleStatus> status() async {
    if (!_supported) return const DialerRoleStatus(available: false);
    try {
      return DialerRoleStatus.fromPlatform(await _channel.invokeMethod<Map<Object?, Object?>>('status'));
    } on Exception catch (e) {
      // Includes MissingPluginException (no native side, e.g. in tests).
      AppLogger.warning('Reading the default-dialer status failed: ${e.runtimeType}');
      return const DialerRoleStatus(available: false);
    }
  }

  @override
  Future<bool> requestDefaultDialer() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestDefaultDialer') ?? false;
    } on Exception catch (e) {
      AppLogger.warning('Requesting the default-dialer role failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> openDefaultAppsSettings() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openDefaultAppsSettings') ?? false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<List<PhoneAccountInfo>> phoneAccounts() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('getPhoneAccounts') ?? const [];
      return [for (final item in raw) ?PhoneAccountInfo.fromPlatform(item)];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<bool> hasCallPermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasCallPermission') ?? false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> requestCallPermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestCallPermission') ?? false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<PlaceCallResult> placeCall(String number, {int? subscriptionId}) async {
    if (!_supported) return PlaceCallResult.unavailable;
    try {
      final result = await _channel.invokeMethod<String>('placeCall', {'number': number, 'subscriptionId': subscriptionId});
      return switch (result) {
        'placed' => PlaceCallResult.placed,
        'invalid_number' => PlaceCallResult.invalidNumber,
        'permission_denied' => PlaceCallResult.permissionDenied,
        'unavailable' => PlaceCallResult.unavailable,
        _ => PlaceCallResult.failed,
      };
    } on Exception catch (e) {
      AppLogger.warning('Placing a call failed: ${e.runtimeType}');
      return PlaceCallResult.failed;
    }
  }

  @override
  Future<void> updateLeadCache(List<({String name, String phone, String? status})> leads) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('updateLeadCache', {
        'leads': [for (final l in leads) {'name': l.name, 'phone': l.phone, 'status': l.status}],
      });
    } on Exception {
      // The call screen then shows just the number.
    }
  }

  @override
  Future<String?> takeDialNumber() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('takeDialNumber');
    } on Exception {
      return null;
    }
  }

  @override
  Stream<NativeCallEvent> get callEvents {
    if (!_supported) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .map(NativeCallEvent.fromPlatform)
        .where((e) => e != null)
        .cast<NativeCallEvent>()
        // No native side (tests) or a stream hiccup must never surface as an app error.
        .handleError((Object _) {});
  }
}
