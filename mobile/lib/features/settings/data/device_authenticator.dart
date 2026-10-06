import 'package:local_auth/local_auth.dart';

import '../../../core/logging/app_logger.dart';

/// Asks the phone to confirm it's really the owner (fingerprint, face, or the screen-lock PIN /
/// pattern). Behind an abstraction because `flutter test` has no platform channel for it.
abstract class DeviceAuthenticator {
  /// Whether the phone has any screen lock / biometric to check against.
  Future<bool> isSupported();

  /// Shows the system prompt. False when cancelled, failed, or unavailable — never throws.
  Future<bool> authenticate(String reason);
}

class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      AppLogger.warning('Device auth support check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly stays false so the phone's PIN / pattern works when a finger or face isn't
      // available. persistAcrossBackgrounding: the prompt itself can background the app briefly.
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      AppLogger.warning('Device authentication did not complete: $e');
      return false;
    }
  }
}
