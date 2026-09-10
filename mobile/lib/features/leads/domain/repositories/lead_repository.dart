import '../../../customer360/domain/entities/timeline_item.dart';
import '../../../customer360/domain/entities/timeline_page.dart';
import '../entities/allocation.dart';
import '../entities/bulk_action_result.dart';
import '../entities/interaction.dart';
import '../entities/lead.dart';
import '../entities/lead_bulk_action.dart';
import '../entities/lead_draft.dart';
import '../entities/lead_import_state.dart';
import '../entities/lead_page.dart';
import '../entities/lead_source.dart';
import '../entities/lead_status.dart';
import '../entities/member_summary.dart';
import '../entities/tag.dart';

/// Every method takes the caller's own accessToken explicitly (matching
/// AuthRepository/MeApiDataSource's convention — see Phase 4) rather
/// than the repository holding one internally, so a request always uses
/// the freshest token from the caller's current session.
abstract class LeadRepository {
  Future<LeadPage> listLeads({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? statusId,
    // Phase 14 §"Advanced Lead Search, Filters & Saved Views".
    String? sourceId,
    String? assignedMemberId,
    String? priority,
    bool? isCustomer,
    DateTime? createdFrom,
    DateTime? createdTo,
    String? tagId,
    int limit = 20,
    int offset = 0,
  });

  Future<Lead> getLead({required String accessToken, required String workspaceId, required String leadId});

  Future<Lead> createLead({required String accessToken, required String workspaceId, required LeadDraft draft});

  Future<Lead> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required LeadDraft draft,
  });

  Future<void> deleteLead({required String accessToken, required String workspaceId, required String leadId});

  // ---- conversion (Phase 18) ----

  /// Converts an existing lead in place (sets `is_customer`); the lead's
  /// id and every related record are preserved. Returns the updated
  /// lead. Throws [ConflictException]-shaped [AppException] if the lead
  /// has already been converted.
  Future<Lead> convertLead({required String accessToken, required String workspaceId, required String leadId});

  Future<List<LeadStatus>> listStatuses({required String accessToken, required String workspaceId});

  Future<List<LeadSource>> listSources({required String accessToken, required String workspaceId});

  Future<List<Tag>> listTags({required String accessToken, required String workspaceId});

  Future<Tag> createTag({required String accessToken, required String workspaceId, required String name, String? color});

  Future<List<Tag>> listLeadTags({required String accessToken, required String workspaceId, required String leadId});

  Future<Tag> attachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId});

  Future<void> detachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId});

  Future<List<Interaction>> listInteractions({required String accessToken, required String workspaceId, required String leadId});

  // ---- assignment (Phase 6) ----

  Future<List<MemberSummary>> listWorkspaceMembers({required String accessToken, required String workspaceId});

  /// [memberId] null unassigns the lead. Returns the updated lead.
  Future<Lead> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  });

  Future<List<Allocation>> listAllocations({required String accessToken, required String workspaceId, required String leadId});

  // ---- bulk actions & CSV import (Phase 13) ----

  Future<BulkActionResult> bulkAction({
    required String accessToken,
    required String workspaceId,
    required List<String> leadIds,
    required LeadBulkAction action,
    String? memberId,
    String? statusId,
  });

  Future<LeadImportResult> importLeads({required String accessToken, required String workspaceId, required String csvContent});

  // ---- unified activity feed & notes (Phase 15) ----

  /// The same unified, merged (calls/follow-ups/notes/allocations/
  /// documents), server-paginated activity feed Customer 360's
  /// `CustomerRepository.getTimeline` already provides — generalized to
  /// any lead, not just customers. Returns the exact same [TimelinePage]/
  /// [TimelineItem] shapes so both screens share one UI.
  Future<TimelinePage> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  });

  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  });
}
