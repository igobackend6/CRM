import 'call.dart';

enum CallDetailStatus { loading, success, notFound, error }

/// Mirrors FollowUpDetailState's status handling (followups feature),
/// scoped to a single call (Phase 9 §3).
class CallDetailState {
  const CallDetailState._({required this.status, this.call, this.errorMessage});

  const CallDetailState.loading() : this._(status: CallDetailStatus.loading);
  const CallDetailState.success(Call call) : this._(status: CallDetailStatus.success, call: call);
  const CallDetailState.notFound() : this._(status: CallDetailStatus.notFound);
  const CallDetailState.error(String message) : this._(status: CallDetailStatus.error, errorMessage: message);

  final CallDetailStatus status;
  final Call? call;
  final String? errorMessage;
}
