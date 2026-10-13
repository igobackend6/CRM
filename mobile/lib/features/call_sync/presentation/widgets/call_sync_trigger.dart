import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart' show routerProvider;
import '../../../../core/router/route_paths.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../../dialer/domain/native_dialer_models.dart';
import '../../../dialer/presentation/providers/native_dialer_providers.dart';
import '../../../calls/presentation/providers/call_providers.dart' show callListControllerProvider;
import '../../../../services/api/api_client.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../providers/call_sync_providers.dart';

/// Keeps call history syncing on its own while the app is in use: when the app opens, each time
/// the employee comes back to it (e.g. after a call in the phone's dialer), and every
/// [interval] while it stays open. Does nothing until sync is set up (permission + business SIM).
class CallSyncTrigger extends ConsumerStatefulWidget {
  const CallSyncTrigger({super.key, required this.child, this.interval = const Duration(minutes: 10)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<CallSyncTrigger> createState() => _CallSyncTriggerState();
}

class _CallSyncTriggerState extends ConsumerState<CallSyncTrigger> with WidgetsBindingObserver {
  Timer? _timer;

  StreamSubscription<NativeCallEvent>? _calls;

  @override
  void initState() {
    super.initState();
    // Android's phone stack tells us when a call ends (only while the CRM is the Phone app).
    _calls = ref.read(nativeDialerServiceProvider).callEvents.listen(_onCallEvent, onError: (Object _) {});
    WidgetsBinding.instance.addObserver(this);
    unawaited(ApiClient.warmUp());
    _timer = Timer.periodic(widget.interval, (_) => _run());
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _onCallEvent(NativeCallEvent event) {
    if (!event.isEnded) return;
    // The phone's call log gets the new row a moment after hang-up: sync then, which adds the call
    // to the lead's history (the same, duplicate-proof route as every other call).
    Timer(const Duration(seconds: 4), () {
      if (mounted) unawaited(ref.read(callSyncControllerProvider.notifier).syncWhenIdle());
    });
  }

  @override
  void dispose() {
    _calls?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      _run();
      // Back from the background (maybe on another network): re-read Home so nothing stays on an error
      // or stale numbers, and wake the backend if it went to sleep.
      refreshHomeData(ref.invalidate);
      unawaited(ApiClient.warmUp());
    }
  }

  void _run() {
    if (!mounted) return;
    unawaited(ref.read(callSyncControllerProvider.notifier).autoSync());
    unawaited(_openTappedLead());
    unawaited(_openSharedRecording());
    unawaited(_openDialedNumber());
    unawaited(_refreshDialerLeads());
  }

  /// Another app (a tel: link, or the Dial action) asked for the dialer: show it with that number.
  Future<void> _openDialedNumber() async {
    if (!ref.read(authControllerProvider).isAuthenticated || ref.read(workspaceControllerProvider).selected == null) return;
    final number = await ref.read(nativeDialerServiceProvider).takeDialNumber();
    if (number == null || !mounted) return;
    ref.read(routerProvider).push(RoutePaths.dialer, extra: number);
  }

  Future<void> _refreshDialerLeads() async {
    if (!ref.read(authControllerProvider).isAuthenticated) return;
    final isDefault = ref.read(defaultDialerControllerProvider).isDefault;
    if (isDefault) await refreshDialerLeadCache(ref.read);
  }

  /// A recording was shared into the app (Share > Sales CRM): open the screen that attaches it.
  Future<void> _openSharedRecording() async {
    if (!ref.read(authControllerProvider).isAuthenticated || ref.read(workspaceControllerProvider).selected == null) return;
    final audio = await ref.read(callSyncControllerProvider.notifier).takeSharedAudio();
    if (audio == null || !mounted) return;
    ref.read(pendingSharedAudioProvider.notifier).state = audio;
    ref.read(routerProvider).push(RoutePaths.importRecording);
  }

  /// A tapped "call back" notification asked for a lead: open it (once).
  Future<void> _openTappedLead() async {
    // On a cold start the sign-in is still being restored; leave the target for the next call.
    if (!ref.read(authControllerProvider).isAuthenticated || ref.read(workspaceControllerProvider).selected == null) return;
    final leadId = await ref.read(callSyncControllerProvider.notifier).takeLaunchLead();
    if (leadId == null || !mounted) return;
    ref.read(routerProvider).push(RoutePaths.leadDetail(leadId));
  }

  @override
  Widget build(BuildContext context) {
    // Sign-in / workspace changes rebuild the controller; run once for the new one.
    ref.listen(callSyncControllerProvider.notifier, (_, _) => _run());
    // New calls were just synced: Home's numbers, pipeline, follow-ups and call list and the Calls page
    // are re-read, so what they show matches the phone without reopening the app.
    ref.listen(callSyncControllerProvider.select((s) => s.syncing), (was, now) {
      if (was == true && now == false) refreshHomeData(ref.invalidate);
    });
    return widget.child;
  }
}

/// Re-reads everything Home and the Calls page show (Overview, Analytics, Pipeline distribution,
/// Follow-ups, recent Calls, Activity). Called after calls sync and after the after-call pop-up saves.
void refreshHomeData(void Function(ProviderOrFamily) invalidate) {
  invalidate(dashboardSummaryProvider);
  invalidate(dashboardPendingFollowUpsProvider);
  invalidate(dashboardRecentCallsProvider);
  invalidate(activityListControllerProvider);
  invalidate(callListControllerProvider);
}
