// Pure helpers for the call-sync Edge Function — no Deno or network APIs,
// so they can be unit-tested on their own (logic_test.ts).

export const MAX_SYNC_ENTRIES = 500;
export const MAX_RECORDING_BYTES = 50 * 1024 * 1024; // the bucket's own file_size_limit

/** Only the past week of calls is synced (the app's window is 7 days; 1 extra day for clock/timezone slack). */
export const MAX_CALL_AGE_MS = 8 * 24 * 3600 * 1000;

const DIRECTIONS = new Set(["inbound", "outbound"]);
const STATES = new Set(["ENDED", "MISSED", "CANCELLED", "FAILED"]);

export interface SyncEntry {
  key: string;
  phone: string;
  phoneKey: string;
  direction: "inbound" | "outbound";
  state: string;
  startedAt: string;
  connectedAt: string | null;
  endedAt: string;
}

/** Last 10 digits — the same rule as the match_call_leads() SQL function. */
export function phoneKey(phone: string): string | null {
  const digits = phone.replace(/\D/g, "");
  return digits.length >= 10 ? digits.slice(-10) : null;
}

/**
 * Validates one call-log entry from the app. Null = unusable (skipped and
 * counted as invalid, never guessed at).
 *
 * Talk time comes from Android's CallLog DURATION; the call is treated as
 * connected at its start, exactly as the backend's create_call does.
 */
export function parseSyncEntry(raw: unknown, now: number = Date.now()): SyncEntry | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;

  const key = r.key;
  if (typeof key !== "string" || !/^[0-9a-f]{8,64}:\d{1,19}$/.test(key)) return null;

  const phone = typeof r.phone === "string" ? r.phone.trim() : "";
  const pk = phoneKey(phone);
  if (!pk || phone.length > 32) return null;

  if (typeof r.direction !== "string" || !DIRECTIONS.has(r.direction)) return null;
  if (typeof r.state !== "string" || !STATES.has(r.state)) return null;

  const started = typeof r.started_at === "string" ? new Date(r.started_at) : null;
  if (!started || Number.isNaN(started.getTime())) return null;
  // Not in the future (a little clock skew allowed), and only from the past week.
  if (started.getTime() > now + 10 * 60 * 1000 || started.getTime() < now - MAX_CALL_AGE_MS) return null;

  const duration = r.duration_seconds;
  if (typeof duration !== "number" || !Number.isInteger(duration) || duration < 0 || duration > 24 * 3600) return null;

  const connected = r.state === "ENDED" && duration > 0;
  return {
    key,
    phone,
    phoneKey: pk,
    direction: r.direction as "inbound" | "outbound",
    state: r.state,
    startedAt: started.toISOString(),
    connectedAt: connected ? started.toISOString() : null,
    endedAt: new Date(started.getTime() + duration * 1000).toISOString(),
  };
}

export function isAudioMime(mime: string): boolean {
  return /^audio\/[a-z0-9.+-]+$/i.test(mime) || mime === "application/ogg";
}

/** `{workspace}/{call}/{random}_{safe name}` — the path convention 000028's storage policies check. */
export function buildRecordingPath(workspaceId: string, callId: string, fileName: string, random: string): string {
  const safe = fileName
    .replace(/[\/\\]/g, "_")
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^[._]+/, "")
    .slice(0, 100) || "recording";
  return `${workspaceId}/${callId}/${random.replace(/-/g, "")}_${safe}`;
}
