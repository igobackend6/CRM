import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/device_token_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/noop_fcm_token_source.dart';
import '../../data/push_repository_impl.dart';
import '../../domain/fcm_token_source.dart';
import '../../domain/repositories/push_repository.dart';
import '../push_registrar.dart';

/// Swap this for a `FirebaseFcmTokenSource` once a Firebase project is
/// configured — see docs/setup/push-notifications.md. Nothing else in
/// the push feature changes.
final fcmTokenSourceProvider = Provider<FcmTokenSource>((ref) => const NoopFcmTokenSource());

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepositoryImpl(DioDeviceTokenApiDataSource()),
);

/// App-lifetime. Booted from the router's auth listener (app_router.dart),
/// same as `realtimeServiceProvider`.
final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final registrar = PushRegistrar(
    initialAuth: ref.read(authControllerProvider),
    authChanges: ref.read(authControllerProvider.notifier).stream,
    source: ref.watch(fcmTokenSourceProvider),
    repository: ref.watch(pushRepositoryProvider),
  );
  ref.onDispose(registrar.dispose);
  return registrar;
});
