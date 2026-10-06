// Edge Function: call-sync
//
// The single server entry point for phone call-log sync and call
// recordings. Every database/storage call is made with the CALLER'S JWT,
// so the existing RLS (calls_*, call_recordings_*, storage policies from
// 000014/000028) decides what is allowed — nothing here uses the
// service-role key. Workspace and member are never trusted from the body:
// permission and member id come from has_permission / current_member_id.
//
// POST JSON { action, workspace_id, ... }:
//   sync_calls            — import call-log entries whose number matches a lead
//   recording_upload_url  — signed upload URL for one call's recording
//   recording_complete    — register the uploaded file in call_recordings
//   recording_url         — short-lived playback/download URL
//   lead_recordings       — every recording of a lead, oldest call first
//   recordings_for_calls  — the recordings of up to 100 given calls (call list play buttons)
//
// Used by the mobile app (supabase.functions.invoke) and usable by the
// admin panel (CORS enabled) to list/play recordings for a lead.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  buildRecordingPath,
  isAudioMime,
  MAX_RECORDING_BYTES,
  MAX_SYNC_ENTRIES,
  parseSyncEntry,
  type SyncEntry,
} from "./logic.ts";

const BUCKET = "call-recordings";
const SIGNED_URL_SECONDS = 300;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requireUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpError(400, "invalid_request", `${field} must be a UUID`);
  }
  return value;
}

interface Ctx {
  db: SupabaseClient;
  workspaceId: string;
  memberId: string;
}

async function context(req: Request, body: Record<string, unknown>): Promise<Ctx> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) throw new HttpError(401, "unauthorized", "Sign in again.");

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await db.auth.getUser(auth.slice("Bearer ".length));
  if (userError || !userData.user) throw new HttpError(401, "unauthorized", "Sign in again.");

  const workspaceId = requireUuid(body.workspace_id, "workspace_id");
  const { data: allowed, error: permError } = await db.rpc("has_permission", {
    p_workspace_id: workspaceId,
    p_permission_code: "calls.create",
  });
  if (permError) throw new HttpError(500, "server_error", "Could not check permissions.");
  if (allowed !== true) throw new HttpError(403, "forbidden", "You can't sync calls in this workspace.");

  const { data: memberId, error: memberError } = await db.rpc("current_member_id", { p_workspace_id: workspaceId });
  if (memberError || typeof memberId !== "string") throw new HttpError(403, "forbidden", "You aren't a member of this workspace.");

  return { db, workspaceId, memberId };
}

// ---------------------------------------------------------------------------
// sync_calls
// ---------------------------------------------------------------------------
async function syncCalls(ctx: Ctx, body: Record<string, unknown>) {
  const raw = body.entries;
  if (!Array.isArray(raw)) throw new HttpError(400, "invalid_request", "entries must be a list");
  if (raw.length > MAX_SYNC_ENTRIES) throw new HttpError(400, "invalid_request", `At most ${MAX_SYNC_ENTRIES} entries per request`);

  const entries: SyncEntry[] = [];
  let invalid = 0;
  for (const item of raw) {
    const entry = parseSyncEntry(item);
    if (entry) entries.push(entry);
    else invalid++;
  }
  if (entries.length === 0) return { synced: [], unmatched: 0, invalid };

  const { data: matches, error: matchError } = await ctx.db.rpc("match_call_leads", {
    p_workspace_id: ctx.workspaceId,
    p_phones: entries.map((e) => e.phone),
  });
  if (matchError) throw new HttpError(500, "server_error", "Could not match calls to leads.");
  const leadByPhone = new Map<string, string>();
  for (const m of (matches ?? []) as { phone_key: string; lead_id: string }[]) leadByPhone.set(m.phone_key, m.lead_id);

  const rows = [];
  let unmatched = 0;
  for (const e of entries) {
    const leadId = leadByPhone.get(e.phoneKey);
    if (!leadId) {
      unmatched++;
      continue;
    }
    rows.push({
      workspace_id: ctx.workspaceId,
      lead_id: leadId,
      agent_member_id: ctx.memberId,
      direction: e.direction,
      state: e.state,
      started_at: e.startedAt,
      connected_at: e.connectedAt,
      ended_at: e.endedAt,
      source: "device_sync",
      device_call_key: e.key,
      phone_number: e.phone,
    });
  }

  if (rows.length > 0) {
    const { error: insertError } = await ctx.db
      .from("calls")
      .upsert(rows, { onConflict: "workspace_id,device_call_key", ignoreDuplicates: true });
    if (insertError) throw new HttpError(500, "server_error", "Could not save the synced calls.");
  }

  // Already-synced calls are returned too, so the app can still attach a
  // recording that turned up after the first sync.
  const keys = rows.map((r) => r.device_call_key);
  const synced: unknown[] = [];
  for (let i = 0; i < keys.length; i += 200) {
    const { data, error } = await ctx.db
      .from("calls")
      .select("id, lead_id, device_call_key")
      .eq("workspace_id", ctx.workspaceId)
      .in("device_call_key", keys.slice(i, i + 200));
    if (error) throw new HttpError(500, "server_error", "Could not read the synced calls.");
    for (const row of data ?? []) synced.push({ key: row.device_call_key, call_id: row.id, lead_id: row.lead_id });
  }

  return { synced, unmatched, invalid };
}

// ---------------------------------------------------------------------------
// recordings
// ---------------------------------------------------------------------------

/** The caller's own call in this workspace (RLS already hides others' calls from agents). */
async function ownCall(ctx: Ctx, callId: string) {
  const { data, error } = await ctx.db
    .from("calls")
    .select("id, agent_member_id")
    .eq("workspace_id", ctx.workspaceId)
    .eq("id", callId)
    .maybeSingle();
  if (error) throw new HttpError(500, "server_error", "Could not read the call.");
  if (!data) throw new HttpError(404, "not_found", "Call not found.");
  if (data.agent_member_id !== ctx.memberId) throw new HttpError(403, "forbidden", "Only the agent who made the call can upload its recording.");
  return data;
}

async function existingRecording(ctx: Ctx, callId: string) {
  const { data, error } = await ctx.db
    .from("call_recordings")
    .select("id, call_id, storage_path, mime_type, size_bytes, duration_seconds, original_file_name, created_at")
    .eq("workspace_id", ctx.workspaceId)
    .eq("call_id", callId)
    .maybeSingle();
  if (error) throw new HttpError(500, "server_error", "Could not read recordings.");
  return data;
}

async function recordingUploadUrl(ctx: Ctx, body: Record<string, unknown>) {
  const callId = requireUuid(body.call_id, "call_id");
  const mime = typeof body.mime_type === "string" ? body.mime_type : "";
  const size = typeof body.size_bytes === "number" ? body.size_bytes : -1;
  if (!isAudioMime(mime)) throw new HttpError(400, "invalid_file", "Only audio files can be uploaded as recordings.");
  if (size <= 0 || size > MAX_RECORDING_BYTES) throw new HttpError(400, "invalid_file", "The recording is empty or too large (max 50 MB).");

  await ownCall(ctx, callId);
  const existing = await existingRecording(ctx, callId);
  if (existing) return { already_uploaded: true, recording: existing };

  const path = buildRecordingPath(ctx.workspaceId, callId, String(body.file_name ?? "recording"), crypto.randomUUID());
  const { data, error } = await ctx.db.storage.from(BUCKET).createSignedUploadUrl(path);
  if (error || !data) throw new HttpError(500, "server_error", "Could not prepare the upload.");
  return { already_uploaded: false, path: data.path, token: data.token, signed_url: data.signedUrl };
}

async function recordingComplete(ctx: Ctx, body: Record<string, unknown>) {
  const callId = requireUuid(body.call_id, "call_id");
  const path = typeof body.path === "string" ? body.path : "";
  const prefix = `${ctx.workspaceId}/${callId}/`;
  if (!path.startsWith(prefix) || path.includes("..")) throw new HttpError(400, "invalid_request", "Wrong upload path.");
  await ownCall(ctx, callId);

  // The object must really be there (the client could call this without uploading).
  const name = path.slice(prefix.length);
  const { data: listed, error: listError } = await ctx.db.storage.from(BUCKET).list(`${ctx.workspaceId}/${callId}`, { search: name });
  if (listError) throw new HttpError(500, "server_error", "Could not check the upload.");
  const object = (listed ?? []).find((o) => o.name === name);
  if (!object) throw new HttpError(400, "invalid_request", "The file wasn't uploaded.");

  const duration = typeof body.duration_seconds === "number" && body.duration_seconds >= 0 ? Math.round(body.duration_seconds) : null;
  const { data, error } = await ctx.db
    .from("call_recordings")
    .insert({
      workspace_id: ctx.workspaceId,
      call_id: callId,
      storage_bucket: BUCKET,
      storage_path: path,
      mime_type: typeof body.mime_type === "string" ? body.mime_type : null,
      size_bytes: typeof object.metadata?.size === "number" ? object.metadata.size : null,
      duration_seconds: duration,
      original_file_name: typeof body.original_file_name === "string" ? body.original_file_name.slice(0, 255) : null,
      uploaded_by_member_id: ctx.memberId,
    })
    .select("id, call_id, storage_path, mime_type, size_bytes, duration_seconds, original_file_name, created_at")
    .single();

  if (error) {
    // Another upload won the race (unique call_id): keep theirs. The orphan
    // object stays — agents can't delete storage objects (manager-only policy).
    if (error.code === "23505") {
      const existing = await existingRecording(ctx, callId);
      if (existing) return { recording: existing };
    }
    throw new HttpError(500, "server_error", "Could not save the recording.");
  }
  return { recording: data };
}

async function recordingUrl(ctx: Ctx, body: Record<string, unknown>) {
  const recordingId = requireUuid(body.recording_id, "recording_id");
  const { data, error } = await ctx.db
    .from("call_recordings")
    .select("storage_path")
    .eq("workspace_id", ctx.workspaceId)
    .eq("id", recordingId)
    .maybeSingle();
  if (error) throw new HttpError(500, "server_error", "Could not read the recording.");
  if (!data) throw new HttpError(404, "not_found", "Recording not found.");
  const { data: signed, error: signError } = await ctx.db.storage.from(BUCKET).createSignedUrl(data.storage_path, SIGNED_URL_SECONDS);
  if (signError || !signed) throw new HttpError(500, "server_error", "Could not open the recording.");
  return { url: signed.signedUrl, expires_in: SIGNED_URL_SECONDS };
}

async function leadRecordings(ctx: Ctx, body: Record<string, unknown>) {
  const leadId = requireUuid(body.lead_id, "lead_id");
  const { data, error } = await ctx.db
    .from("call_recordings")
    .select(
      "id, call_id, mime_type, size_bytes, duration_seconds, original_file_name, created_at, " +
        "call:calls!call_recordings_call_fk!inner(lead_id, direction, state, started_at, duration_seconds, phone_number)",
    )
    .eq("workspace_id", ctx.workspaceId)
    .eq("call.lead_id", leadId);
  if (error) throw new HttpError(500, "server_error", "Could not load recordings.");
  // Oldest call first — "from the first call".
  const recordings = (data ?? []) as unknown as { call: { started_at: string } }[];
  recordings.sort((a, b) => a.call.started_at.localeCompare(b.call.started_at));
  return { recordings };
}

/** Which of these calls have a recording (for the call list's play buttons). RLS limits it to calls the caller may see. */
async function recordingsForCalls(ctx: Ctx, body: Record<string, unknown>) {
  const raw = body.call_ids;
  if (!Array.isArray(raw) || raw.length === 0) return { recordings: [] };
  if (raw.length > 100) throw new HttpError(400, "invalid_request", "At most 100 calls at a time");
  const ids = raw.map((id) => requireUuid(id, "call_ids"));
  const { data, error } = await ctx.db
    .from("call_recordings")
    .select("id, call_id, mime_type, size_bytes, duration_seconds, original_file_name, created_at, call:calls!call_recordings_call_fk!inner(direction, started_at, duration_seconds)")
    .eq("workspace_id", ctx.workspaceId)
    .in("call_id", ids);
  if (error) throw new HttpError(500, "server_error", "Could not load recordings.");
  return { recordings: data ?? [] };
}

// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: { code: "method_not_allowed", message: "Use POST." } }, 405);

  try {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new HttpError(400, "invalid_request", "Body must be JSON.");
    }
    const ctx = await context(req, body);
    switch (body.action) {
      case "sync_calls":
        return json(await syncCalls(ctx, body));
      case "recording_upload_url":
        return json(await recordingUploadUrl(ctx, body));
      case "recording_complete":
        return json(await recordingComplete(ctx, body));
      case "recording_url":
        return json(await recordingUrl(ctx, body));
      case "lead_recordings":
        return json(await leadRecordings(ctx, body));
      case "recordings_for_calls":
        return json(await recordingsForCalls(ctx, body));
      default:
        throw new HttpError(400, "invalid_request", "Unknown action.");
    }
  } catch (e) {
    if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
    // Never echo internals (tokens, SQL) back; the platform log keeps the stack.
    console.error("call-sync failed", e instanceof Error ? e.message : "unknown");
    return json({ error: { code: "server_error", message: "Something went wrong." } }, 500);
  }
});
