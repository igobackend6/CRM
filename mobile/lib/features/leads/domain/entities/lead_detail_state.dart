import 'allocation.dart';
import 'interaction.dart';
import 'lead.dart';

enum LeadDetailStatus { loading, success, notFound, error }

class LeadDetailState {
  const LeadDetailState._({
    required this.status,
    this.lead,
    this.interactions = const [],
    this.allocations = const [],
    this.errorMessage,
  });

  const LeadDetailState.loading() : this._(status: LeadDetailStatus.loading);
  const LeadDetailState.success(Lead lead, List<Interaction> interactions, List<Allocation> allocations)
      : this._(status: LeadDetailStatus.success, lead: lead, interactions: interactions, allocations: allocations);
  const LeadDetailState.notFound() : this._(status: LeadDetailStatus.notFound);
  const LeadDetailState.error(String message) : this._(status: LeadDetailStatus.error, errorMessage: message);

  final LeadDetailStatus status;
  final Lead? lead;
  final List<Interaction> interactions;
  final List<Allocation> allocations;
  final String? errorMessage;

  LeadDetailState copyWithLead(Lead newLead) =>
      LeadDetailState._(status: status, lead: newLead, interactions: interactions, allocations: allocations, errorMessage: null);

  LeadDetailState copyWithLeadAndAllocations(Lead newLead, List<Allocation> newAllocations) => LeadDetailState._(
        status: status,
        lead: newLead,
        interactions: interactions,
        allocations: newAllocations,
        errorMessage: null,
      );

  LeadDetailState copyWithError(String message) =>
      LeadDetailState._(status: status, lead: lead, interactions: interactions, allocations: allocations, errorMessage: message);
}
