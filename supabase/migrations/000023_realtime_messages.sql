-- Phase 21B — Supabase Realtime. `leads`, `follow_ups`, `notifications`,
-- `allocations` were already enabled by 000016_realtime.sql. `messages`
-- is the one addition this phase makes, for Phase 16's internal
-- messaging to update live (conversation list + open conversation).
--
-- `conversations` is deliberately NOT added: its own `updated_at` is
-- only ever touched as a side effect of a `messages` insert
-- (ConversationRepository.touch, backend/app/repositories/messaging.py),
-- so a `messages` change is already a sufficient live-update signal for
-- both the conversation list and the open conversation — publishing
-- `conversations` too would be a second replication stream for no
-- second signal (docs/architecture/database.md §15: "not broadcast to
-- every table").
--
-- `calls`/`interactions` remain excluded, same reasoning 000016 already
-- documented — a manager "live activity" view is a later-phase feature,
-- not part of this foundation.

alter publication supabase_realtime add table messages;
