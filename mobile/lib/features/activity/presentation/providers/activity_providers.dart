import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/activity_api_data_source.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../data/activity_repository_impl.dart';
import '../../domain/entities/activity_range.dart';
import '../../domain/entities/activity_summary.dart';
import '../../domain/repositories/activity_repository.dart';
import '../controllers/activity_controller.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) => ActivityRepositoryImpl(DioActivityApiDataSource()));

/// App-lifetime. Booted from the router's auth listener (app_router.dart),
/// same as `pushRegistrarProvider`/`realtimeServiceProvider`. Its state is
/// whether the member is on a break.
final activityControllerProvider = StateNotifierProvider<ActivityController, ActivityStatus>((ref) {
  return ActivityController(ref.watch(activityRepositoryProvider), ref);
});

/// The window chosen on the Login Analytics dropdown. `.autoDispose`, like
/// Call Analytics' own filters: leaving the screen resets it to Today.
final activityRangeProvider = StateProvider.autoDispose<ActivityRange>((ref) => ActivityRange.today);

/// The caller's own login / talk / wrap-up / break / idle totals for the
/// chosen range — computed by the backend from the stored sessions, breaks
/// and calls (so it includes the session in progress).
final activitySummaryProvider = FutureProvider.autoDispose<ActivitySummary>((ref) async {
  final context = resolveLeadContext(ref.read);
  if (context == null) return ActivitySummary.empty;
  final period = ref.watch(activityRangeProvider).period(DateTime.now());
  return ref.watch(activityRepositoryProvider).getSummary(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        since: period.since,
        until: period.until,
      );
});
