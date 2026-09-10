-- Realtime is enabled only for tables with a genuine live-update need
-- (docs/architecture/database.md "Realtime Strategy") — not broadcast to
-- every table. calls and audit_logs are deliberately excluded (a
-- manager "live activity" view is a later-phase feature, not part of
-- this foundation); agent_presence itself is deferred entirely (Phase
-- 17, Team).

alter publication supabase_realtime add table leads;
alter publication supabase_realtime add table follow_ups;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table allocations;
