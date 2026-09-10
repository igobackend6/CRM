/// Phase 17 §"Date Range" — the dashboard's lightweight date filter.
/// Mirrors `ActivityFilter`'s shape (activity_filter.dart) exactly: an
/// enum with an `apiValue`/`label`, rendered by a small `ChoiceChip` row
/// (`DashboardDateRangeChips`) — same pattern as `ActivityFilterChips`,
/// just a different vocabulary. `all` is the default and reproduces the
/// dashboard's pre-Phase-17 behavior unchanged (backend/app/services/
/// dashboard/service.py's own docstring on why).
enum DashboardDateRange {
  all,
  today,
  thisWeek,
  thisMonth;

  /// The exact `range` query value the backend accepts
  /// (backend/app/api/v1/dashboard.py).
  String get apiValue => switch (this) {
        DashboardDateRange.all => 'all',
        DashboardDateRange.today => 'today',
        DashboardDateRange.thisWeek => 'this_week',
        DashboardDateRange.thisMonth => 'this_month',
      };

  String get label => switch (this) {
        DashboardDateRange.all => 'All time',
        DashboardDateRange.today => 'Today',
        DashboardDateRange.thisWeek => 'This week',
        DashboardDateRange.thisMonth => 'This month',
      };
}
