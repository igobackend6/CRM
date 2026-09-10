import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/allocation.dart';
import '../../domain/entities/interaction.dart';
import '../../domain/entities/lead_detail_state.dart';
import '../../domain/entities/tag.dart';
import '../../domain/repositories/lead_repository.dart';
import 'lead_request_context.dart';

/// One instance per lead (see leads_providers.dart's `.family`). Loads
/// the lead plus its basic interaction history (Phase 5 §2) and
/// allocation/assignment history (Phase 6 §2B), and exposes tag add/
/// remove (§6), delete (§4/§8), and assign/reassign/unassign (Phase 6
/// §2A) actions.
class LeadDetailController extends StateNotifier<LeadDetailState> with RealtimeRefreshMixin<LeadDetailState> {
  LeadDetailController(this._repository, this._ref, this.leadId) : super(const LeadDetailState.loading()) {
    // Same reasoning as LeadListController: react to workspace selection
    // rather than loading once at construction time.
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
      if (next.status == WorkspaceStatus.selected) load();
    }, fireImmediately: true);
    // Phase 21B — this exact lead changing elsewhere (reassigned,
    // status changed, edited by a teammate) reloads it live; an
    // allocation on this lead does the same (its allocation history is
    // part of this screen's state).
    subscribeRealtime(_ref, const {'leads', 'allocations'}, _onRealtimeEvent);
  }

  final LeadRepository _repository;
  final Ref _ref;
  final String leadId;

  void _onRealtimeEvent(RealtimeRecordEvent event) {
    final affectsThisLead = event.table == 'leads' ? event.id == leadId : event.record['lead_id'] == leadId;
    if (!affectsThisLead) return;
    debouncedRealtimeRefresh(load);
  }

  @override
  void onRealtimeResync() => debouncedRealtimeRefresh(load);

  Future<void> load() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = const LeadDetailState.loading();
    try {
      final lead = await _repository.getLead(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: leadId);

      List<Interaction> interactions = const [];
      try {
        interactions = await _repository.listInteractions(
          accessToken: context.accessToken,
          workspaceId: context.workspaceId,
          leadId: leadId,
        );
      } catch (e) {
        // Interaction history is supplementary — failing to load it
        // should not block showing the lead itself.
        AppLogger.warning('Could not load interaction history for lead $leadId: $e');
      }

      List<Allocation> allocations = const [];
      try {
        allocations = await _repository.listAllocations(
          accessToken: context.accessToken,
          workspaceId: context.workspaceId,
          leadId: leadId,
        );
      } catch (e) {
        // Same reasoning: allocation history is supplementary.
        AppLogger.warning('Could not load allocation history for lead $leadId: $e');
      }

      state = LeadDetailState.success(lead, interactions, allocations);
    } on NotFoundException {
      state = const LeadDetailState.notFound();
    } on AppException catch (e) {
      state = LeadDetailState.error(e.message);
    } catch (e) {
      AppLogger.error('Failed to load lead $leadId', error: e);
      state = const LeadDetailState.error('Could not load this lead.');
    }
  }

  Future<bool> addTag(Tag tag) async {
    final context = resolveLeadContext(_ref.read);
    final lead = state.lead;
    if (context == null || lead == null) return false;
    try {
      await _repository.attachTag(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: leadId, tagId: tag.id);
      state = state.copyWithLead(lead.copyWithTags([...lead.tags, tag]));
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }

  Future<bool> removeTag(Tag tag) async {
    final context = resolveLeadContext(_ref.read);
    final lead = state.lead;
    if (context == null || lead == null) return false;
    try {
      await _repository.detachTag(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: leadId, tagId: tag.id);
      state = state.copyWithLead(lead.copyWithTags(lead.tags.where((t) => t.id != tag.id).toList()));
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }

  /// Assign, reassign, or unassign ([memberId] null) this lead. Refreshes
  /// both the lead (new assignee) and the allocation history (Phase 6
  /// §10: "Refresh lead assignment after a successful mutation") in one
  /// round trip's worth of follow-up calls, without reloading anything
  /// else (tags/interactions are untouched by an assignment change).
  Future<bool> assignLead(String? memberId) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;
    try {
      final updatedLead = await _repository.assignLead(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        memberId: memberId,
      );

      var allocations = state.allocations;
      try {
        allocations = await _repository.listAllocations(
          accessToken: context.accessToken,
          workspaceId: context.workspaceId,
          leadId: leadId,
        );
      } catch (e) {
        AppLogger.warning('Assigned lead $leadId, but could not refresh its allocation history: $e');
      }

      state = state.copyWithLeadAndAllocations(updatedLead, allocations);
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }

  /// Phase 18 — converts this lead to a customer in place. On success,
  /// swaps in the updated lead (isCustomer=true) so the screen's
  /// existing declarative rebuild (same as assignLead above) hides the
  /// "Convert to Customer" action and reveals the Customer 360 entry
  /// point, without a second full reload.
  Future<bool> convertToCustomer() async {
    final context = resolveLeadContext(_ref.read);
    final lead = state.lead;
    if (context == null || lead == null) return false;
    try {
      final updatedLead = await _repository.convertLead(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
      );
      state = state.copyWithLead(updatedLead);
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }

  Future<bool> deleteLead() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;
    try {
      await _repository.deleteLead(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: leadId);
      return true;
    } on AppException catch (e) {
      state = state.copyWithError(e.message);
      return false;
    }
  }

  @override
  void dispose() {
    disposeRealtime();
    super.dispose();
  }
}
