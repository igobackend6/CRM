import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/workspace/domain/entities/workspace_state.dart';
import '../../features/workspace/presentation/providers/workspace_providers.dart';
import '../../services/supabase/supabase_service.dart';
import 'realtime_event_source.dart';
import 'realtime_service.dart';

/// A plain (non-autoDispose) `Provider`, deliberately: one [RealtimeService]
/// lives for the whole app session, not per-screen (Phase 21B STEP 3 "do
/// NOT create one unmanaged channel per widget"). It's instantiated once
/// at app boot — see `core/router/app_router.dart`'s
/// `_RouterRefreshNotifier`, the app's one existing cross-cutting
/// auth/workspace listener — and lives for the container's lifetime from
/// then on, exactly like `SupabaseService`/`authRepositoryProvider`.
///
/// Typed as [RealtimeEventSource], not the concrete [RealtimeService]:
/// every consumer (`RealtimeRefreshMixin`) only ever needs `events`/
/// `resynced`, so tests override this provider with a lightweight fake
/// that never touches `supabase_flutter` (see
/// `test/core/realtime/fake_realtime_service.dart`) instead of needing a
/// real, initialized `SupabaseClient`.
final realtimeServiceProvider = Provider<RealtimeEventSource>((ref) {
  final service = RealtimeService(SupabaseService.client);

  // The one listener that drives every lifecycle transition Phase 21B
  // STEP 10 asks for: initial start (workspace resolves to `selected`),
  // workspace switch (a different `selected.workspace.id` — handled
  // idempotently inside RealtimeChannelManager.subscribeToWorkspace), and
  // logout (WorkspaceController.reset() already reacts to
  // authControllerProvider turning non-authenticated and flips its own
  // state back to `loading`, whose `.selected` is null — see
  // workspace_controller.dart — so no separate auth listener is needed
  // here).
  ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) {
    final workspaceId = next.selected?.workspace.id;
    if (workspaceId != null) {
      service.start(workspaceId);
    } else {
      service.stop();
    }
  }, fireImmediately: true);

  ref.onDispose(service.dispose);
  return service;
});
