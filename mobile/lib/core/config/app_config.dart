import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_flavor.dart';

/// Centralized, environment-driven app configuration.
///
/// Values are loaded once at startup (see `main.dart`) from the `.env` file
/// matching the active [AppFlavor]. Nothing here is hardcoded, and nothing
/// here is a service-role or otherwise privileged secret — only client-safe
/// values belong in this class.
class AppConfig {
  AppConfig._();

  static late final AppFlavor flavor;
  static bool _loaded = false;

  static Future<void> load({
    AppFlavor flavor = AppFlavor.development,
  }) async {
    AppConfig.flavor = flavor;
    await dotenv.load(fileName: 'env/.env.${flavor.name}');
    _loaded = true;
  }

  static String _require(String key) {
    if (!_loaded) {
      throw StateError(
        'AppConfig.load() must complete before reading configuration.',
      );
    }
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }
    return value;
  }

  static String get supabaseUrl => _require('SUPABASE_URL');

  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String get apiBaseUrl => _require('API_BASE_URL');

  static bool get isProduction => flavor == AppFlavor.production;
}
