import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';

/// Single point of Supabase initialization for the whole app.
///
/// Called once from `main.dart`, before `runApp`. Only ever configured with
/// the public anon key read from [AppConfig] — the service-role key never
/// exists in this codebase. Do not call `Supabase.initialize` anywhere else.
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    AppLogger.info('Supabase initialized for flavor: ${AppConfig.flavor.name}');
  }

  static SupabaseClient get client => Supabase.instance.client;
}
