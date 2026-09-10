import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/customer_detail_state.dart';
import '../../domain/repositories/customer_repository.dart';

/// One instance per customer (customer360_providers.dart's `.family`).
/// Loads only the customer profile (Phase 8 §2) — Documents/Timeline/
/// Follow-ups are each their own lazily-loaded section, fetched only
/// when CustomerDetailScreen actually builds them (mirrors
/// LeadDetailController/FollowUpListController's "react to workspace
/// selection" pattern, not a constructor-time load).
class CustomerDetailController extends StateNotifier<CustomerDetailState> {
  CustomerDetailController(this._repository, this._ref, this.customerId) : super(const CustomerDetailState.loading()) {
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) load();
    }, fireImmediately: true);
  }

  final CustomerRepository _repository;
  final Ref _ref;
  final String customerId;

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = const CustomerDetailState.loading();
    try {
      final customer = await _repository.getCustomer(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        customerId: customerId,
      );
      state = CustomerDetailState.success(customer);
    } on NotFoundException {
      // Covers both "no such lead" and "lead exists but is not a
      // customer" — the backend deliberately returns the same 404 for
      // both (services/customer360/service.py's _require_customer).
      state = const CustomerDetailState.notFound();
    } on AppException catch (e) {
      state = CustomerDetailState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to load customer $customerId', error: e);
      state = const CustomerDetailState.error('Could not load this customer.');
    }
  }
}
