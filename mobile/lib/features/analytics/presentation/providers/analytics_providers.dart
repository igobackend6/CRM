import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../reports/domain/entities/call_trends.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/file_saver.dart';
import '../../domain/call_analytics_period.dart';

/// "All" counts every call; "Unique" counts distinct leads called. The
/// backend returns both numbers for every bucket, so this is a purely
/// client-side switch — flipping it never re-fetches.
enum CallCounting {
  all,
  unique;

  String get label => this == CallCounting.all ? 'All' : 'Unique';
}

// All four are `.autoDispose`: leaving Call Analytics resets it to
// "Today / Overall / All" the next time it opens, which is what a fresh
// analytics visit should show (unlike `reportDateFilterProvider`, which
// is deliberately kept across the Reports tabs).
final callAnalyticsPeriodProvider = StateProvider.autoDispose<CallAnalyticsPeriod>((ref) => CallAnalyticsPeriod.today());

final callTrendDirectionProvider = StateProvider.autoDispose<CallTrendDirection>((ref) => CallTrendDirection.all);

final callCountingProvider = StateProvider.autoDispose<CallCounting>((ref) => CallCounting.all);

/// The caller's own call trends — re-fetched whenever the workspace,
/// period, or Overall/Outbound/Inbound direction changes (the backend
/// buckets per direction; All/Unique needs no new request).
final callTrendsProvider = FutureProvider.autoDispose<CallTrends>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  final period = ref.watch(callAnalyticsPeriodProvider);
  final direction = ref.watch(callTrendDirectionProvider);
  if (workspace == null || user == null) return CallTrends.empty;
  return ref.watch(reportsRepositoryProvider).getCallTrends(
        accessToken: user.accessToken,
        workspaceId: workspace.workspace.id,
        since: period.since,
        until: period.until,
        granularity: period.granularity,
        direction: direction,
      );
});

/// Provider seam over `file_picker`'s save dialog (see `FileSaver`).
final fileSaverProvider = Provider<FileSaver>((ref) => FilePickerFileSaver());
