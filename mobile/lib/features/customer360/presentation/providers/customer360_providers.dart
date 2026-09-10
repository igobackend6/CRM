import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/customer_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../followups/domain/entities/follow_up.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/customer_repository_impl.dart';
import '../../domain/entities/customer_detail_state.dart';
import '../../domain/entities/timeline_list_state.dart';
import '../../domain/repositories/customer_repository.dart';
import '../controllers/customer_detail_controller.dart';
import '../controllers/customer_timeline_controller.dart';

final customerApiDataSourceProvider = Provider<CustomerApiDataSource>((ref) => DioCustomerApiDataSource());

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepositoryImpl(ref.watch(customerApiDataSourceProvider));
});

final customerDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<CustomerDetailController, CustomerDetailState, String>((ref, customerId) {
  return CustomerDetailController(ref.watch(customerRepositoryProvider), ref, customerId);
});

final customerTimelineControllerProvider =
    StateNotifierProvider.autoDispose.family<CustomerTimelineController, TimelineListState, String>((ref, customerId) {
  return CustomerTimelineController(ref.watch(customerRepositoryProvider), ref, customerId);
});

/// Follow-Ups section (Phase 8 §2 "Follow-Ups") — reuses the existing
/// [FollowUp] entity and Follow-Up Detail screen (Phase 7), fetched
/// lazily only when CustomerDetailScreen builds this section, same
/// pattern as followups' own `leadFollowUpsProvider`.
final customerFollowUpsProvider = FutureProvider.autoDispose.family<List<FollowUp>, String>((ref, customerId) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(customerRepositoryProvider);
  return repository.listFollowUps(accessToken: user.accessToken, workspaceId: workspace.workspace.id, customerId: customerId);
});
