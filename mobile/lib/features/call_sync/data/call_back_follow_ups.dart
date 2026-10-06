import '../../followups/domain/entities/follow_up_draft.dart';
import '../../followups/domain/repositories/follow_up_repository.dart';
import 'call_sync_api.dart';

/// A "call back" follow-up that was just created.
class ScheduledCallBack {
  const ScheduledCallBack({required this.leadName, required this.dueAt});

  final String leadName;
  final DateTime dueAt;
}

/// Creates the follow-up behind a Never Attended Call Reminder. Behind an abstraction so call sync
/// doesn't depend on how follow-ups are stored, and tests can fake it.
abstract class CallBackFollowUps {
  /// Adds a "call" follow-up for [leadId], due at [dueAt], assigned to the signed-in member. Returns
  /// null — and creates nothing — when the lead already has a pending follow-up (it covers the
  /// call-back already, so reminders never pile up).
  Future<ScheduledCallBack?> schedule({
    required String workspaceId,
    required String leadId,
    required DateTime dueAt,
    required String notes,
  });
}

/// Uses the app's existing follow-up service (the same backend rules, permissions and audit trail as
/// a follow-up added by hand) — nothing is written to the database directly.
class ApiCallBackFollowUps implements CallBackFollowUps {
  ApiCallBackFollowUps(this._repository, this._accessToken);

  final FollowUpRepository _repository;

  /// The current session's token, read when needed so a refreshed token is used.
  final String? Function() _accessToken;

  @override
  Future<ScheduledCallBack?> schedule({
    required String workspaceId,
    required String leadId,
    required DateTime dueAt,
    required String notes,
  }) async {
    final token = _accessToken();
    if (token == null) throw const CallSyncApiException('unauthorized');

    final existing = await _repository.listLeadFollowUps(accessToken: token, workspaceId: workspaceId, leadId: leadId);
    if (existing.any((f) => f.isPending)) return null;

    final created = await _repository.createFollowUp(
      accessToken: token,
      workspaceId: workspaceId,
      leadId: leadId,
      draft: FollowUpDraft(dueAt: dueAt, type: 'call', notes: notes),
    );
    return ScheduledCallBack(leadName: created.lead.name, dueAt: created.dueAt.toLocal());
  }
}
