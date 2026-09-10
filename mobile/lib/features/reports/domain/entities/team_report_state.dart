import 'team_report.dart';

enum TeamReportStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Same loading/success/empty/error + pull-to-refresh + offset-pagination
/// shape as every other paginated list state in this app
/// (ActivityListState, CallListState) — the team report's member rows are
/// paginated, but `totals` (workspace-wide, never paginated — Phase 21C
/// §"Pagination") lives here too since it's fetched in the same request.
class TeamReportState {
  const TeamReportState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.totals = TeamTotals.zero,
    this.errorMessage,
  });

  const TeamReportState.initial() : this._(status: TeamReportStatus.initial);

  final TeamReportStatus status;
  final List<TeamMemberReportRow> items;
  final int total;
  final int limit;
  final TeamTotals totals;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  TeamReportState copyWith({
    TeamReportStatus? status,
    List<TeamMemberReportRow>? items,
    int? total,
    TeamTotals? totals,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TeamReportState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      totals: totals ?? this.totals,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
