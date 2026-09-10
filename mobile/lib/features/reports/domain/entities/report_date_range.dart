/// Phase 21C §"Date Range Support" — the canonical range picker every
/// report screen shares, mirroring the backend's own canonical
/// `app/core/date_ranges.py` (a deliberately separate, wider set than
/// the dashboard's own `DashboardDateRange` — see that module's
/// docstring for why extending the dashboard's set wasn't the right
/// move). Same UTC-only timezone behavior as the rest of this app: there
/// is no per-user timezone preference anywhere in this schema, so
/// "yesterday"/"last week"/"last month" mean the calendar unit in UTC.
enum ReportDateRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom,
  allTime;

  /// The exact `range` query value the backend accepts
  /// (backend/app/core/date_ranges.py's `REPORT_DATE_RANGES`).
  String get apiValue => switch (this) {
        ReportDateRange.today => 'today',
        ReportDateRange.yesterday => 'yesterday',
        ReportDateRange.thisWeek => 'this_week',
        ReportDateRange.lastWeek => 'last_week',
        ReportDateRange.thisMonth => 'this_month',
        ReportDateRange.lastMonth => 'last_month',
        ReportDateRange.custom => 'custom',
        ReportDateRange.allTime => 'all_time',
      };

  String get label => switch (this) {
        ReportDateRange.today => 'Today',
        ReportDateRange.yesterday => 'Yesterday',
        ReportDateRange.thisWeek => 'This week',
        ReportDateRange.lastWeek => 'Last week',
        ReportDateRange.thisMonth => 'This month',
        ReportDateRange.lastMonth => 'Last month',
        ReportDateRange.custom => 'Custom',
        ReportDateRange.allTime => 'All time',
      };
}

/// The chip row's selection plus the custom-range bounds, when set. A
/// single object (rather than three separate providers) so selecting
/// "Custom" and picking dates is one atomic state change — a report
/// provider watching this never sees a half-updated custom range (e.g.
/// a new `since` paired with the previous `until`).
class ReportDateFilter {
  const ReportDateFilter({this.range = ReportDateRange.allTime, this.customSince, this.customUntil});

  final ReportDateRange range;
  final DateTime? customSince;
  final DateTime? customUntil;

  ReportDateFilter copyWith({ReportDateRange? range, DateTime? customSince, DateTime? customUntil}) => ReportDateFilter(
        range: range ?? this.range,
        customSince: customSince ?? this.customSince,
        customUntil: customUntil ?? this.customUntil,
      );

  // Value equality — TeamReportController compares `previous != next` on
  // this provider (presentation/controllers/team_report_controller.dart)
  // to decide whether to re-fetch; without this, two filters with
  // identical fields but different object identities would always
  // compare unequal, triggering a redundant re-fetch on every rebuild
  // that happens to construct a new instance with the same values.
  @override
  bool operator ==(Object other) =>
      other is ReportDateFilter && other.range == range && other.customSince == customSince && other.customUntil == customUntil;

  @override
  int get hashCode => Object.hash(range, customSince, customUntil);
}
