import 'realtime_event.dart';

/// What a feature controller (via `RealtimeRefreshMixin`) actually needs
/// from the app-wide Realtime layer — deliberately narrow, and
/// deliberately its own type (rather than depending on the concrete
/// `RealtimeService` directly), so tests can override
/// `realtimeServiceProvider` with a lightweight fake that has no
/// dependency on `supabase_flutter`/a real `SupabaseClient` at all. See
/// `test/core/realtime/fake_realtime_service.dart`.
abstract class RealtimeEventSource {
  Stream<RealtimeRecordEvent> get events;
  Stream<void> get resynced;
}
