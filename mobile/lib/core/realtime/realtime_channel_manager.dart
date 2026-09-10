import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import 'realtime_event.dart';

/// Phase 21B STEP 2/3 — the tables genuinely wired for live updates.
/// `calls`/`interactions` are deliberately excluded here, mirroring the
/// pre-existing, documented decision in
/// docs/architecture/database.md "§15 Realtime Strategy" (a manager
/// "live activity" view is a later-phase feature, not part of this
/// foundation) — `messages` is the one addition this phase makes to that
/// list, for Phase 16 live messaging.
const kRealtimeTables = ['leads', 'follow_ups', 'notifications', 'allocations', 'messages'];

/// Owns exactly one Postgres Changes channel per workspace — "Channel
/// Manager" in the Phase 21B architecture
/// (RealtimeService -> RealtimeChannelManager -> feature subscriptions).
/// Every feature subscribes to the single shared [events] stream instead
/// of opening its own channel, so there is never more than one
/// `RealtimeChannel`/websocket subscription alive per workspace at a
/// time, regardless of how many screens are open (STEP 3 "do NOT create
/// one unmanaged channel per widget").
class RealtimeChannelManager {
  RealtimeChannelManager(this._client);

  final SupabaseClient _client;

  RealtimeChannel? _channel;
  String? _workspaceId;

  final _eventsController = StreamController<RealtimeRecordEvent>.broadcast();

  Stream<RealtimeRecordEvent> get events => _eventsController.stream;

  String? get subscribedWorkspaceId => _workspaceId;

  /// Subscribes to [workspaceId]'s row changes across [kRealtimeTables].
  /// A no-op if already subscribed to this exact workspace (duplicate
  /// protection, STEP 3) — otherwise tears down any previous channel
  /// first (a workspace switch never leaves two channels alive at once,
  /// STEP 10 "never leak events between workspaces").
  ///
  /// Wrapped in try/catch: a failure here must never crash the app (STEP
  /// 11) — the CRM's normal API/repository calls are entirely
  /// independent of Realtime and keep working regardless.
  void subscribeToWorkspace(String workspaceId, {void Function(RealtimeSubscribeStatus status, Object? error)? onStatusChange}) {
    if (_workspaceId == workspaceId && _channel != null) return;
    unsubscribe();

    try {
      final channel = _client.channel('workspace:$workspaceId');
      for (final table in kRealtimeTables) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'workspace_id', value: workspaceId),
          callback: (payload) => _handlePayload(table, payload),
        );
      }
      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
          AppLogger.warning('Realtime channel for workspace $workspaceId: $status${error != null ? ' ($error)' : ''}');
        }
        onStatusChange?.call(status, error);
      });
      _channel = channel;
      _workspaceId = workspaceId;
    } catch (e) {
      AppLogger.error('Failed to subscribe to Realtime for workspace $workspaceId', error: e);
    }
  }

  void _handlePayload(String table, PostgresChangePayload payload) {
    final type = switch (payload.eventType) {
      PostgresChangeEvent.insert => RealtimeEventType.insert,
      PostgresChangeEvent.update => RealtimeEventType.update,
      PostgresChangeEvent.delete => RealtimeEventType.delete,
      PostgresChangeEvent.all => null,
    };
    if (type == null) return;
    _eventsController.add(RealtimeRecordEvent(table: table, type: type, record: payload.newRecord, oldRecord: payload.oldRecord));
  }

  /// Tears down the current channel, if any. Safe to call repeatedly.
  void unsubscribe() {
    final channel = _channel;
    _channel = null;
    _workspaceId = null;
    if (channel != null) {
      unawaited(
        _client.removeChannel(channel).catchError((Object e) {
          AppLogger.warning('Error removing Realtime channel: $e');
          return '';
        }),
      );
    }
  }

  void dispose() {
    unsubscribe();
    unawaited(_eventsController.close());
  }
}
