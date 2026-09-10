import '../../../followups/domain/entities/follow_up.dart';
import '../../../leads/domain/entities/lead.dart';
import '../entities/timeline_item.dart';
import '../entities/timeline_page.dart';

// Documents are no longer served through this repository — Phase 21A
// moved them to a dedicated, lead-scoped feature (features/documents/)
// shared by both Lead Detail and Customer 360, since is_customer=false
// leads also need document upload/download/delete (this repository's
// GET /customers/{id}/documents route requires is_customer, which real
// leads-that-aren't-customers-yet don't satisfy). The backend route
// itself is untouched (still tested, still correct) — it's just no
// longer this app's document data source.
abstract class CustomerRepository {
  Future<Lead> getCustomer({required String accessToken, required String workspaceId, required String customerId});

  Future<TimelinePage> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  });

  Future<List<FollowUp>> listFollowUps({required String accessToken, required String workspaceId, required String customerId});

  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  });
}
