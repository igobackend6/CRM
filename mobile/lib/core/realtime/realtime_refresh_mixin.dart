import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'realtime_event.dart';
import 'realtime_providers.dart';

/// Phase 21B "feature subscriptions" layer — the reusable piece every
/// realtime-aware `StateNotifier` controller mixes in, so the
/// subscribe/debounce/dispose boilerplate is written once instead of
/// once per feature. A controller using this never touches
/// `supabase_flutter` or the shared channel directly; it only reacts to
/// [RealtimeRecordEvent]s already filtered to the tables it declared.
mixin RealtimeRefreshMixin<T> on StateNotifier<T> {
  StreamSubscription<RealtimeRecordEvent>? _realtimeEventSub;
  StreamSubscription<void>? _realtimeResyncSub;
  Timer? _realtimeDebounce;

  /// Subscribes to the app-wide realtime event stream, filtered to
  /// [tables], and to the reconnect ("resynced") signal — call once from
  /// the controller's constructor.
  void subscribeRealtime(Ref ref, Set<String> tables, void Function(RealtimeRecordEvent event) onEvent) {
    final service = ref.read(realtimeServiceProvider);
    _realtimeEventSub = service.events.where((e) => tables.contains(e.table)).listen(onEvent);
    _realtimeResyncSub = service.resynced.listen((_) => onRealtimeResync());
  }

  /// Called once whenever the realtime channel (re)connects (including
  /// its very first connect). Defaults to no-op; override to trigger a
  /// refresh so a reconnect after a dropped connection reconciles any
  /// state that changed while disconnected (STEP 11).
  void onRealtimeResync() {}

  /// Coalesces bursts of realtime events into a single call to [refresh]
  /// (STEP 9 "prevent event storms") — the default 500ms window is short
  /// enough to feel live, long enough to merge a rapid sequence (e.g. a
  /// bulk action) into one request.
  void debouncedRealtimeRefresh(Future<void> Function() refresh, {Duration duration = const Duration(milliseconds: 500)}) {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(duration, refresh);
  }

  /// Call from the controller's own `dispose()`, alongside `super.dispose()`.
  void disposeRealtime() {
    _realtimeEventSub?.cancel();
    _realtimeResyncSub?.cancel();
    _realtimeDebounce?.cancel();
  }
}
