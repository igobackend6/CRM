import '../../../leads/domain/entities/lead.dart';

enum CustomerDetailStatus { loading, success, notFound, error }

/// Customer 360's header/profile state — just the underlying [Lead]
/// (Phase 8 §"Customer model": a customer IS a lead with
/// is_customer=true, so this reuses the existing Lead entity rather than
/// a duplicate Customer model). Documents/follow-ups/timeline are each
/// their own lazily-loaded section state (see document_list_state.dart,
/// timeline_list_state.dart, followup_providers.dart's
/// leadFollowUpsProvider) — mirrors LeadDetailScreen's own pattern of
/// not loading every related section eagerly.
class CustomerDetailState {
  const CustomerDetailState._({required this.status, this.customer, this.errorMessage});

  const CustomerDetailState.loading() : this._(status: CustomerDetailStatus.loading);
  const CustomerDetailState.success(Lead customer) : this._(status: CustomerDetailStatus.success, customer: customer);
  const CustomerDetailState.notFound() : this._(status: CustomerDetailStatus.notFound);
  const CustomerDetailState.error(String message) : this._(status: CustomerDetailStatus.error, errorMessage: message);

  final CustomerDetailStatus status;
  final Lead? customer;
  final String? errorMessage;
}
