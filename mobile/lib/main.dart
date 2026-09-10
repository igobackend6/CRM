import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/config/app_flavor.dart';
import 'core/constants/app_constants.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/supabase/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GlobalErrorHandler.install();

  final flavor = AppFlavor.fromName(
    const String.fromEnvironment(
      'FLAVOR',
      defaultValue: 'development',
    ),
  );

  await AppConfig.load(flavor: flavor);
  await SupabaseService.initialize();

  AppLogger.info('Starting ${AppConstants.appName} (${flavor.name})');

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
