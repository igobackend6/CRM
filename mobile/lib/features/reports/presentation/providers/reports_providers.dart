import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/reports_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/reports_repository_impl.dart';
import '../../domain/entities/personal_report.dart';
import '../../domain/entities/pipeline_report.dart';
import '../../domain/entities/report_date_range.dart';
import '../../domain/entities/team_report_state.dart';
import '../../domain/repositories/reports_repository.dart';
import '../controllers/team_report_controller.dart';

final reportsApiDataSourceProvider = Provider<ReportsApiDataSource>((ref) => DioReportsApiDataSource());

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepositoryImpl(ref.watch(reportsApiDataSourceProvider));
});

/// The shared date-range filter every report tab reads (Phase 21C
/// §"Date Range Support": "one canonical date-range implementation
/// across reports") — plain `StateProvider`, not `.autoDispose`, so
/// switching tabs (Personal/Team/Pipeline) doesn't reset the user's
/// chosen range, same lifetime reasoning as `dashboardDateRangeProvider`.
final reportDateFilterProvider = StateProvider<ReportDateFilter>((ref) => const ReportDateFilter());

/// Personal report (Phase 21C §"Personal Reports") — re-fetched whenever
/// the workspace or the selected date range changes.
final personalReportProvider = FutureProvider.autoDispose<PersonalReport>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  final filter = ref.watch(reportDateFilterProvider);
  if (workspace == null || user == null) return PersonalReport.empty;
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.getPersonalReport(
    accessToken: user.accessToken,
    workspaceId: workspace.workspace.id,
    range: filter.range.apiValue,
    since: filter.customSince,
    until: filter.customUntil,
  );
});

/// Pipeline report (Phase 21C §"Pipeline Reports") — manager/admin/ceo
/// only server-side (`Permission.REPORTS_READ`); a team_mate's request
/// still reaches this provider (the tab is visually present) but the
/// repository call 403s, surfaced by the screen's own error/retry view
/// exactly like any other permission-denied fetch in this app.
final pipelineReportProvider = FutureProvider.autoDispose<PipelineReport>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  final filter = ref.watch(reportDateFilterProvider);
  if (workspace == null || user == null) return PipelineReport.empty;
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.getPipelineReport(
    accessToken: user.accessToken,
    workspaceId: workspace.workspace.id,
    range: filter.range.apiValue,
    since: filter.customSince,
    until: filter.customUntil,
  );
});

/// Team report (Phase 21C §"Team Reports") — a `StateNotifier` rather
/// than a plain `FutureProvider` because its member rows are paginated
/// (offset/limit "load more"), same reasoning as `activityListControllerProvider`.
final teamReportControllerProvider = StateNotifierProvider.autoDispose<TeamReportController, TeamReportState>((ref) {
  return TeamReportController(ref.watch(reportsRepositoryProvider), ref);
});
