# 02 — Flutter Architecture

## 1. Folder Structure (feature-first)

```
lib/
  core/
    config/            # env, flavors, app config
    constants/
    errors/            # Failure types, exception mapping
    router/            # GoRouter setup, route guards
    theme/
    utils/
    network/           # Dio client, interceptors, connectivity
    storage/            # secure storage, local cache (Hive/Drift)
    permissions/        # OS permission helpers (contacts, phone, mic, storage)
    widgets/            # shared design-system widgets
  features/
    auth/
    dashboard/
    leads/
    customers/
    allocations/
    calling/
    call_logs/
    followups/
    calendar/
    notifications/
    documents/
    messaging/
    rechurn/
    reports/
    team/
    settings/
    profile/
  services/
    supabase/           # typed Supabase client wrappers
    api/                 # Dio-based Python API client
    calling/             # MethodChannel/EventChannel bridge to native
    notifications/       # FCM handlers, local notification scheduling
    realtime/            # Supabase Realtime channel managers
    analytics/           # event logging wrapper
```

Each non-trivial feature (leads, calling, followups, dashboard) internally follows:

```
features/leads/
  presentation/   # screens, widgets, Riverpod providers/controllers
  domain/         # entities, use cases, repository interfaces
  data/           # repository impl, DTOs, Supabase/API data sources
```

Simple features (settings, profile) may skip the domain layer and go presentation → data directly — don't force ceremony where there's no real business logic.

## 2. State Management Flow

```
UI (ConsumerWidget)
  -> Provider (state exposure)
    -> Controller/Notifier (Riverpod StateNotifier/AsyncNotifier — orchestration)
      -> Use Case (domain logic, only where logic is non-trivial)
        -> Repository (interface in domain/, impl in data/)
          -> Remote/Local Data Source
            -> Supabase client  OR  Python API (Dio)
```

Rules:
- No Supabase/Dio calls inside widgets or providers directly — always through a repository.
- Controllers expose `AsyncValue<T>` states so screens render loading/error/data uniformly.
- Use cases are added only when there's real orchestration (e.g., "convert lead to customer" touches leads + interactions + notifications); trivial CRUD skips the use-case layer and controller calls the repository directly.

## 3. Navigation

GoRouter with:
- Auth guard redirect (unauthenticated → `/login`; authenticated hitting `/login` → `/dashboard`).
- Permission-aware route guards (redirect or show "not permitted" for routes gated by RBAC, e.g. Reports for `team_mate`).
- Deep link support reserved for notification taps (open a specific lead/follow-up).

## 4. Networking & Offline Handling

- `Dio` client in `core/network` with interceptors: auth header injection (Supabase JWT), retry-with-backoff on transient failures, logging (dev only).
- `connectivity_plus` monitors connection state; a global `ConnectivityProvider` drives an offline banner in the app shell.
- **Cached reads**: last-known lists (leads, dashboard KPIs, follow-ups) cached locally (Hive or Drift — decided in Phase 4 based on query complexity needs) and served when offline, clearly marked "showing cached data."
- **Pending writes**: only *safe, idempotent* writes (e.g., call outcome logging, note creation) are queued locally and retried on reconnect; nothing that risks silent duplication (e.g., lead creation) is queued blindly — those show an explicit "failed, retry" state instead.
- Realtime channels auto-resubscribe on reconnect; a manual pull-to-refresh always available as fallback.

## 5. Local Storage

- `flutter_secure_storage`: Supabase session tokens, any locally cached auth-adjacent secrets.
- Local DB (Hive/Drift, finalized Phase 4): cached list data, pending-write queue, last-sync timestamps per resource.

## 6. Push Notifications

- FCM for delivery; Python backend orchestrates *what* gets sent (dedup, batching, quiet hours later), Flutter only registers device tokens and renders/handles taps.
- Foreground: in-app banner + Riverpod-driven inbox update.
- Background/terminated: system notification → deep link into the relevant screen on tap.

## 7. Calling Integration (Flutter side)

`services/calling/` exposes a Dart-facing `CallService` backed by a `MethodChannel` (commands: dial, endCall, getState) and `EventChannel` (stream: call state transitions, incoming call events). Flutter never talks to Android telephony APIs directly — see `06-calling-architecture.md`.

## 8. Testing Layers

- Unit: use cases, repositories (mocked data sources), controllers/notifiers.
- Widget: screen states (loading/empty/error/data) per feature.
- Integration: critical flows (login → dashboard, create lead → allocate → call → follow-up) using `integration_test`.
