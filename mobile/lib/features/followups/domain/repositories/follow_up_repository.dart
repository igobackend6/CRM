import '../entities/follow_up.dart';
import '../entities/follow_up_draft.dart';
import '../entities/follow_up_page.dart';

abstract class FollowUpRepository {
  Future<FollowUpPage> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    int limit = 20,
    int offset = 0,
  });

  Future<FollowUp> getFollowUp({required String accessToken, required String workspaceId, required String followUpId});

  Future<FollowUp> createFollowUp({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required FollowUpDraft draft,
  });

  Future<FollowUp> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required FollowUpDraft draft,
  });

  /// Complete/cancel/reopen (Phase 7 §2E) — a focused status-only PATCH,
  /// kept separate from [updateFollowUp] so the quick actions on the
  /// detail screen don't need to resend the whole draft.
  Future<FollowUp> updateFollowUpStatus({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required String status,
  });

  Future<List<FollowUp>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId});
}
