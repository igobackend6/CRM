import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device_authenticator.dart';
import '../../data/settings_storage.dart';
import '../../domain/app_settings.dart';
import '../controllers/app_settings_controller.dart';

final appSettingsStorageProvider = Provider<AppSettingsStorage>((ref) => SecureAppSettingsStorage());

final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>((ref) => LocalAuthDeviceAuthenticator());

final appSettingsControllerProvider = StateNotifierProvider<AppSettingsController, AppSettings>(
  (ref) => AppSettingsController(ref.watch(appSettingsStorageProvider), ref.watch(deviceAuthenticatorProvider)),
);
