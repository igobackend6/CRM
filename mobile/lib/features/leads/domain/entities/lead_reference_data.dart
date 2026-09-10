import 'lead_source.dart';
import 'lead_status.dart';

/// Statuses + sources for the current workspace, loaded once and shared
/// by the filter UI and the create/edit form (Phase 5 §5).
class LeadReferenceData {
  const LeadReferenceData({required this.statuses, required this.sources});

  final List<LeadStatus> statuses;
  final List<LeadSource> sources;
}
