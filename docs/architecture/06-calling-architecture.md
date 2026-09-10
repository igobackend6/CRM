# 06 — Calling, Recording, Realtime & Notification Architecture

## 1. Calling Architecture

```
Native Android calling layer (Kotlin: TelephonyManager/TelecomManager,
  PhoneStateListener or CallScreeningService)
  |  (stable contract)
Flutter MethodChannel (commands: dial, endCall, getState, getRecordingCapability)
Flutter EventChannel (stream: call state transitions, incoming-call events)
  |
Call Service (Dart, services/calling/)
  |
Call Repository (domain boundary)
  |
Supabase (call row write) / Python API (event ingestion, analytics)
```

The native layer is a **dedicated Android bridge/service**, not logic embedded in Flutter widgets — so calling behavior is testable and replaceable independent of UI.

## 2. Call State Machine

```
IDLE -> DIALING -> RINGING -> CONNECTED -> ENDED
                 \-> FAILED
       DIALING/RINGING -> CANCELLED (user hangs up before connect)
       RINGING (inbound, unanswered) -> MISSED
```

- Every transition is timestamped; `calls.duration_seconds` derives from `CONNECTED -> ENDED` delta, not wall-clock start-to-end.
- State transitions are the single source for call logging — the UI reflects state, it doesn't independently decide when a call "happened."

## 3. App Lifecycle Handling

- **Foreground**: full UI reflects live state via `EventChannel` stream.
- **Background**: native layer continues tracking state (Android service), writes/queues the resulting `calls` row; Flutter reconciles on next foreground via `getState`.
- **App killed**: native service (where technically permitted by Android version/OEM constraints) persists the call outcome locally and syncs on next app launch; this is a best-effort guarantee, documented as such — not claimed as 100% reliable across all OEMs.
- **Permission denial** (phone/mic/contacts): calling features degrade to click-to-call-via-dialer-intent (hands off to the system dialer) rather than crashing; recording is simply marked `permission_denied`.
- **Dual SIM / SIM unavailable**: native layer exposes available SIM slots; user selects or a default is configured per workspace; absence of SIM disables native dialing and falls back to system dialer intent.
- **Unsupported devices**: capability-detected at runtime (`getRecordingCapability`), never assumed from a device/OS version allowlist alone.

## 4. Call Recording (independent capability)

Recording is modeled as **decoupled from call logging** — a call row is always created regardless of recording outcome.

```
call_recordings.status: supported | unsupported | permission_denied | failed | unavailable | processing | ready
```

- CRM call logging (`calls` table) never blocks on recording.
- Recording upload → (Phase 21+23) transcription/AI pipeline is background-job driven, never synchronous with the call itself.

## 5. Auto-Dialer (Phase 20, architecture noted here for consistency)

```
Lead Queue (server-filtered to leads the user may call — RLS-backed)
  -> state machine: QUEUED -> DIALING -> (call state machine) -> OUTCOME_CAPTURE -> NEXT
  -> pause/resume/skip controlled client-side, but queue membership itself
     is never client-computed — always sourced from a permission-filtered query
```

The dialer reuses the same `Call Service`/state machine as manual calling — no parallel calling implementation.

## 6. Realtime Architecture

Supabase Realtime channels are opened per active screen/provider, filtered by `workspace_id` (+ `assigned_to` for reps), and torn down when the screen disposes:

| Channel | Consumers | Purpose |
|---|---|---|
| `leads` | Leads list, Allocations, Dashboard | live allocation/status updates |
| `follow_ups` | Follow-ups, Calendar, Dashboard | reminders, reassignment |
| `notifications` | App shell (badge), Notifications screen | inbox |
| `agent_presence` | Team screen | live rep status |
| `calls` | Manager "live activity" view only | team call monitoring |

No screen subscribes to a table it isn't actively displaying.

## 7. Notification Architecture

```
Trigger event (lead assigned, follow-up due/overdue, reassignment, system event)
  -> Python backend service (or DB trigger for simple cases) writes `notifications` row
  -> Background worker / DB trigger dispatches FCM push (dedup, respects mute settings later)
  -> Flutter: foreground = in-app banner + Riverpod inbox update;
              background/terminated = system notification -> tap deep-links via GoRouter
```

`notifications` table is the durable record (so the in-app inbox is always correct even if a push is missed); FCM is a best-effort delivery channel layered on top, not the source of truth.
