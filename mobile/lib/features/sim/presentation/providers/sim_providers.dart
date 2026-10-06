import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/sim_platform_source.dart';
import '../../data/sim_repository.dart';
import '../../data/sim_selection_storage.dart';
import '../../domain/business_sim_selection.dart';
import '../controllers/connected_sim_controller.dart';

final simPlatformSourceProvider = Provider<SimPlatformSource>((ref) => MethodChannelSimSource());

final simSelectionStorageProvider = Provider<SimSelectionStorage>((ref) => SecureSimSelectionStorage());

final simRepositoryProvider = Provider<SimRepository>(
  (ref) => SimRepository(ref.watch(simPlatformSourceProvider), ref.watch(simSelectionStorageProvider)),
);

/// Starts a fresh detection every time Connected SIM Details opens.
final connectedSimControllerProvider = StateNotifierProvider.autoDispose<ConnectedSimController, ConnectedSimState>((ref) {
  final profileId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ConnectedSimController(ref.watch(simRepositoryProvider), profileId)..load();
});

/// The signed-in employee's business SIM on this phone, or null if none chosen.
///
/// The integration point for the future Call History Sync: it should read this, then (on each
/// sync) check the subscription is still active via [SimRepository.detectActiveSims] and match
/// call-log entries on [BusinessSimSelection.subscriptionId].
final businessSimSelectionProvider = FutureProvider.autoDispose<BusinessSimSelection?>((ref) async {
  final profileId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (profileId == null) return null;
  return ref.watch(simRepositoryProvider).loadSelection(profileId);
});
