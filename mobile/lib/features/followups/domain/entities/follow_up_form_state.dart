import 'follow_up.dart';

enum FollowUpFormStatus { idle, submitting, success, error }

/// Mirrors LeadFormState (leads feature) — shared by create and edit.
class FollowUpFormState {
  const FollowUpFormState._({required this.status, this.followUp, this.errorMessage});

  const FollowUpFormState.idle() : this._(status: FollowUpFormStatus.idle);
  const FollowUpFormState.submitting() : this._(status: FollowUpFormStatus.submitting);
  const FollowUpFormState.success(FollowUp followUp) : this._(status: FollowUpFormStatus.success, followUp: followUp);
  const FollowUpFormState.error(String message) : this._(status: FollowUpFormStatus.error, errorMessage: message);

  final FollowUpFormStatus status;
  final FollowUp? followUp;
  final String? errorMessage;
}
