/// Phase 15 §"Activity Filters" — lightweight, client-side-only filters
/// over an already-loaded [TimelineItem] page (no new backend filter
/// param: "filter locally... when the loaded dataset is sufficient").
/// Shared by Customer 360's timeline and Lead Detail's activity section
/// (both enhanced by Phase 15), so this lives alongside [TimelineItem]
/// rather than being duplicated per screen.
enum ActivityFilter {
  all,
  calls,
  followUps,
  notes,
  allocations,
  documents;

  /// The `TimelineItem.type` value each filter (other than [all])
  /// matches — the exact vocabulary `interactions.type`/the backend's
  /// timeline item builders already use (call/note/follow_up/document/
  /// allocation — see TimelineItemOut's docstring).
  String? get _typeValue => switch (this) {
        ActivityFilter.all => null,
        ActivityFilter.calls => 'call',
        ActivityFilter.followUps => 'follow_up',
        ActivityFilter.notes => 'note',
        ActivityFilter.allocations => 'allocation',
        ActivityFilter.documents => 'document',
      };

  bool matches(String itemType) => this == ActivityFilter.all || itemType == _typeValue;

  String get label => switch (this) {
        ActivityFilter.all => 'All',
        ActivityFilter.calls => 'Calls',
        ActivityFilter.followUps => 'Follow-ups',
        ActivityFilter.notes => 'Notes',
        ActivityFilter.allocations => 'Allocations',
        ActivityFilter.documents => 'Documents',
      };
}
