import 'call.dart';

enum CallFormStatus { idle, submitting, success, error }

/// Mirrors FollowUpFormState (followups feature) — manual call-log
/// creation (Phase 9 §4).
class CallFormState {
  const CallFormState._({required this.status, this.call, this.errorMessage});

  const CallFormState.idle() : this._(status: CallFormStatus.idle);
  const CallFormState.submitting() : this._(status: CallFormStatus.submitting);
  const CallFormState.success(Call call) : this._(status: CallFormStatus.success, call: call);
  const CallFormState.error(String message) : this._(status: CallFormStatus.error, errorMessage: message);

  final CallFormStatus status;
  final Call? call;
  final String? errorMessage;
}
