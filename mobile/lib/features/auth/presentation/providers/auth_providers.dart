import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/me_api_data_source.dart';
import '../../../../services/supabase/supabase_service.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/entities/auth_state.dart';
import '../../domain/repositories/auth_repository.dart';
import '../controllers/auth_controller.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(SupabaseService.client);
});

final meApiDataSourceProvider = Provider<MeApiDataSource>((ref) {
  return DioMeApiDataSource();
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider), ref.watch(meApiDataSourceProvider));
});
