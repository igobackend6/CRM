import 'follow_up.dart';

enum FollowUpDetailStatus { loading, success, notFound, error }

/// Mirrors LeadDetailState's status handling (leads feature), scoped to
/// a single follow-up (Phase 7 §2B/§2D/§2E).
class FollowUpDetailState {
  const FollowUpDetailState._({required this.status, this.followUp, this.errorMessage});

  const FollowUpDetailState.loading() : this._(status: FollowUpDetailStatus.loading);
  const FollowUpDetailState.success(FollowUp followUp) : this._(status: FollowUpDetailStatus.success, followUp: followUp);
  const FollowUpDetailState.notFound() : this._(status: FollowUpDetailStatus.notFound);
  const FollowUpDetailState.error(String message) : this._(status: FollowUpDetailStatus.error, errorMessage: message);

  final FollowUpDetailStatus status;
  final FollowUp? followUp;
  final String? errorMessage;

  FollowUpDetailState copyWithFollowUp(FollowUp followUp) =>
      FollowUpDetailState._(status: FollowUpDetailStatus.success, followUp: followUp);

  FollowUpDetailState copyWithError(String message) =>
      FollowUpDetailState._(status: status, followUp: followUp, errorMessage: message);
}
