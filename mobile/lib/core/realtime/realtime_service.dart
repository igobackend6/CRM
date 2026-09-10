import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import 'realtime_channel_manager.dart';
import 'realtime_event.dart';
import 'realtime_event_source.dart';

/// Phase 21B — the app-wide "RealtimeService" layer. One instance lives
/// for the app's lifetime (see `realtime_providers.dart`); it owns the
/// single [RealtimeChannelManager] and reacts to app lifecycle and
/// workspace selection so every feature subscription
/// (`RealtimeRefreshMixin`) only ever has to listen to [events]/[resynced]
/// — it never touches `supabase_flutter` or manages its own channel.
class RealtimeService implements RealtimeEventSource {
  RealtimeService(SupabaseClient client) : _manager = RealtimeChannelManager(client) {
    _lifecycleListener = AppLifecycleListener(
      onResume: _handleResume,
      onInactive: _handlePause,
      onHide: _handlePause,
      onPause: _handlePause,
      onDetach: _handlePause,
    );
  }

  final RealtimeChannelManager _manager;
  late final AppLifecycleListener _lifecycleListener;

  String? _targetWorkspaceId;
  bool _backgrounded = false;
  int _retryAttempt = 0;
  Timer? _reconnectTimer;

  final _resyncController = StreamController<void>.broadcast();

  /// Every insert/update/delete on a subscribed table, for the currently
  /// subscribed workspace.
  @override
  Stream<RealtimeRecordEvent> get events => _manager.events;

  /// Fires whenever the channel (re)connects — including the very first
  /// connect, and any reconnect after a dropped connection (STEP 11:
  /// "After reconnect: resubscribe, refresh affected state..."). Feature
  /// controllers treat this as "refresh once, just in case something was
  /// missed while disconnected."
  @override
  Stream<void> get resynced => _resyncController.stream;

  /// Starts (or switches to) live updates for [workspaceId] — called
  /// whenever `workspaceControllerProvider` resolves to a selected
  /// workspace. STEP 10 "workspace switch": if a different workspace was
  /// previously active, its channel is torn down first by
  /// [RealtimeChannelManager.subscribeToWorkspace] before the new one
  /// opens, so events never leak across workspaces.
  void start(String workspaceId) {
    _targetWorkspaceId = workspaceId;
    _retryAttempt = 0;
    _reconnectTimer?.cancel();
    if (_backgrounded) return; // resubscribes on resume instead
    _manager.subscribeToWorkspace(workspaceId, onStatusChange: _onStatusChange);
  }

  /// Stops live updates entirely — called on logout (STEP 10 "Logout:
  /// unsubscribe everything, dispose channels, clear realtime state") and
  /// whenever no workspace is selected.
  void stop() {
    _targetWorkspaceId = null;
    _retryAttempt = 0;
    _reconnectTimer?.cancel();
    _manager.unsubscribe();
  }

  void _onStatusChange(RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _retryAttempt = 0;
        _reconnectTimer?.cancel();
        _resyncController.add(null);
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        _scheduleReconnect();
      case RealtimeSubscribeStatus.closed:
        break;
    }
  }

  /// STEP 11 reconnect/failure handling — capped exponential backoff (the
  /// underlying `realtime_client` websocket already retries the socket
  /// itself; this is a second-layer retry for a channel that failed to
  /// (re)join after the socket came back).
  void _scheduleReconnect() {
    final workspaceId = _targetWorkspaceId;
    if (workspaceId == null || _backgrounded) return;
    _reconnectTimer?.cancel();
    _retryAttempt = _retryAttempt >= 5 ? 5 : _retryAttempt + 1;
    _reconnectTimer = Timer(Duration(seconds: _retryAttempt * 2), () {
      _manager.unsubscribe();
      _manager.subscribeToWorkspace(workspaceId, onStatusChange: _onStatusChange);
    });
  }

  void _handlePause() {
    if (_backgrounded) return;
    _backgrounded = true;
    _reconnectTimer?.cancel();
    // STEP 10 Background: "safely pause/reduce subscriptions" — fully
    // unsubscribing while backgrounded is the simplest safe choice; a
    // background app has no UI to live-patch anyway, and mobile OSes
    // frequently suspend the socket regardless.
    _manager.unsubscribe();
  }

  void _handleResume() {
    if (!_backgrounded) return;
    _backgrounded = false;
    final workspaceId = _targetWorkspaceId;
    if (workspaceId != null) {
      AppLogger.info('App resumed; resubscribing Realtime for workspace $workspaceId');
      _manager.subscribeToWorkspace(workspaceId, onStatusChange: _onStatusChange);
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _lifecycleListener.dispose();
    _manager.dispose();
    unawaited(_resyncController.close());
  }
}
