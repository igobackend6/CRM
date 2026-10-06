// Run with: deno test supabase/functions/call-sync/logic_test.ts
// (also runs under Node 22+: node --experimental-strip-types --test supabase/functions/call-sync/logic_test.ts)

import { test } from "node:test";
import assert from "node:assert/strict";
import { buildRecordingPath, isAudioMime, parseSyncEntry, phoneKey } from "./logic.ts";

const NOW = Date.parse("2026-10-02T10:00:00.000Z");
const parse = (raw: unknown) => parseSyncEntry(raw, NOW);

const base = {
  key: "0123456789abcdef0123456789abcdef:42",
  phone: "+918925829917",
  direction: "outbound",
  state: "ENDED",
  started_at: "2026-10-01T10:00:00.000Z",
  duration_seconds: 65,
};

test("phoneKey keeps the last 10 digits and refuses short numbers", () => {
  assert.equal(phoneKey("+91 89258-29917"), "8925829917");
  assert.equal(phoneKey("08925829917"), "8925829917");
  assert.equal(phoneKey("12345"), null);
});

test("a connected call gets connected/ended times from its talk time", () => {
  const e = parse(base)!;
  assert.equal(e.phoneKey, "8925829917");
  assert.equal(e.connectedAt, "2026-10-01T10:00:00.000Z");
  assert.equal(e.endedAt, "2026-10-01T10:01:05.000Z");
});

test("a missed or zero-length call is never marked connected", () => {
  assert.equal(parse({ ...base, state: "MISSED", duration_seconds: 0 })!.connectedAt, null);
  assert.equal(parse({ ...base, duration_seconds: 0 })!.connectedAt, null);
});

test("bad entries are refused, not guessed", () => {
  for (const bad of [
    null,
    "x",
    { ...base, key: "no-colon" },
    { ...base, key: "zz:1" },
    { ...base, phone: "123" },
    { ...base, direction: "sideways" },
    { ...base, state: "CONNECTED" },
    { ...base, started_at: "not a date" },
    { ...base, started_at: "2999-01-01T00:00:00Z" },
    { ...base, duration_seconds: -1 },
    { ...base, duration_seconds: 1.5 },
    { ...base, duration_seconds: "60" },
  ]) {
    assert.equal(parse(bad), null, JSON.stringify(bad));
  }
});

test("only the past week is accepted", () => {
  assert.ok(parse({ ...base, started_at: "2026-09-26T10:00:00.000Z" })); // 6 days ago
  assert.equal(parse({ ...base, started_at: "2026-09-20T10:00:00.000Z" }), null); // 12 days ago
});

test("only audio files count as recordings", () => {
  assert.ok(isAudioMime("audio/mp4"));
  assert.ok(isAudioMime("audio/amr"));
  assert.ok(isAudioMime("audio/x-m4a"));
  assert.ok(!isAudioMime("application/pdf"));
  assert.ok(!isAudioMime("audio/"));
});

test("recording paths stay inside {workspace}/{call}/ whatever the file name", () => {
  const p = buildRecordingPath("ws", "call", "../../etc/Call recording +91 89 (1).m4a", "aaaa-bbbb");
  assert.ok(p.startsWith("ws/call/aaaabbbb_"));
  assert.ok(!p.slice("ws/call/".length).includes("/"));
  assert.ok(!p.includes(".."));
  assert.equal(buildRecordingPath("ws", "call", "", "r"), "ws/call/r_recording");
});
