/**
 * FR-77 / NP-3 row 12 — OD-3 (36 months, owner 2026-08-30): the ended-trip location aging job.
 *
 * Two properties carry this feature, and both are negative:
 *
 *  1. It strips LOCATION keys and NOTHING else. `SERVER_STAMPED_PAYLOAD_KEYS` —
 *     `lateReplay` and `serverCommittedAt` — are the FR-28h/D-25 ledger that freezes
 *     competitive outcomes and drives `publicLifetimeStatsOnLateReplay`. An aging job that
 *     dropped either would rewrite settled gameplay history three years after the fact. The
 *     survival test below is the regression pin FR-77 names.
 *  2. It never touches a trip that has not ended. A live trip carries an explicit
 *     `canonicalEndedAt: null`, and in real Firestore null sorts BELOW every Timestamp — so
 *     the range filter alone is not the guard, and the per-doc check is.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import type * as adminTypes from "firebase-admin";

const holder = vi.hoisted(() => ({ db: undefined as any }));

// Raw millis, not Timestamp objects — see provisionalChildAccounts.test.ts for why the
// FakeFirestore harness requires this.
vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    increment: (n: number) => ({ __increment__: n }),
  };
  firestore.FieldPath = { documentId: () => "__name__" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { LOCATION_PAYLOAD_KEYS, SERVER_STAMPED_PAYLOAD_KEYS } from "./payloadKeys";
import {
  LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT,
  SESSION_ENDED_AT_FIELD,
  ageLocationPayloadsOnEndedTrips,
  locationPayloadAgingCutoffMillis,
  locationPayloadRetentionDays,
  sessionEndedAtMillis,
  stripLocationPayloadKeys,
} from "./locationPayloadAging";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

function asFirestore(fake: FakeFirestore): adminTypes.firestore.Firestore {
  return fake as unknown as adminTypes.firestore.Firestore;
}

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_800_000_000_000;
const CUTOFF = NOW - 1095 * DAY;
const OLD = CUTOFF - 30 * DAY; // ended ~37 months ago
const RECENT = CUTOFF + 30 * DAY; // ended ~35 months ago

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
});

function seedSession(sessionId: string, endedAt: unknown): void {
  db().seed(`trip_sessions/${sessionId}`, {
    name: `trip-${sessionId}`,
    canonicalStatus: endedAt === null ? "active" : "ended",
    [SESSION_ENDED_AT_FIELD]: endedAt,
  });
}

/** A `region_found` carrying both a place-trail and the FR-28h server-stamped ledger. */
function seedFindEvent(sessionId: string, eventId: string): void {
  db().seed(`trip_sessions/${sessionId}/activity_events/${eventId}`, {
    sessionId,
    kind: "region_found",
    actorId: "player-1",
    payload: {
      regionId: "CA",
      gameInstanceId: "game-1",
      participantId: "player-1",
      inputMethod: "manual",
      xpDayKey: "2023-04-02",
      lateReplay: "true",
      serverCommittedAt: "1680400000",
      locationLatitude: "37.775",
      locationLongitude: "-122.418",
      locationTimestamp: "1680400000",
    },
  });
}

function payloadAt(path: string): Record<string, unknown> {
  return (db().store.get(path) as { payload: Record<string, unknown> }).payload;
}

async function age(
  options: Partial<Parameters<typeof ageLocationPayloadsOnEndedTrips>[1]> = {}
) {
  return ageLocationPayloadsOnEndedTrips(asFirestore(db()), {
    cutoffMillis: CUTOFF,
    ...options,
  });
}

describe("OD-3 location aging: the strip case", () => {
  it("strips the place-trail from an aged ended trip's events", async () => {
    seedSession("old-trip", OLD);
    seedFindEvent("old-trip", "evt-1");

    const result = await age();

    expect(result.agedSessions).toBe(1);
    expect(result.strippedEvents).toBe(1);
    const payload = payloadAt("trip_sessions/old-trip/activity_events/evt-1");
    for (const key of LOCATION_PAYLOAD_KEYS) {
      expect(payload[key]).toBeUndefined();
    }
  });

  it("PRESERVES the server-stamped replay ledger and every other payload key", async () => {
    // The FR-77 constraint, pinned. Losing `lateReplay` or `serverCommittedAt` would rewrite
    // an FR-28h competitive outcome; losing `xpDayKey` would break XP day idempotence.
    seedSession("old-trip", OLD);
    seedFindEvent("old-trip", "evt-1");

    await age();

    const payload = payloadAt("trip_sessions/old-trip/activity_events/evt-1");
    for (const key of SERVER_STAMPED_PAYLOAD_KEYS) {
      expect(payload[key]).toBeDefined();
    }
    expect(payload.lateReplay).toBe("true");
    expect(payload.serverCommittedAt).toBe("1680400000");
    expect(payload.regionId).toBe("CA");
    expect(payload.gameInstanceId).toBe("game-1");
    expect(payload.participantId).toBe("player-1");
    expect(payload.inputMethod).toBe("manual");
    expect(payload.xpDayKey).toBe("2023-04-02");

    // The event's own non-payload fields are untouched too.
    const doc = db().store.get("trip_sessions/old-trip/activity_events/evt-1")!;
    expect(doc.kind).toBe("region_found");
    expect(doc.actorId).toBe("player-1");
    // The trip itself survives — names, discoveries and scores are the product's purpose.
    expect(db().store.has("trip_sessions/old-trip")).toBe(true);
  });

  it("is idempotent: a second run over an already-aged trip writes nothing", async () => {
    seedSession("old-trip", OLD);
    seedFindEvent("old-trip", "evt-1");
    seedFindEvent("old-trip", "evt-2");

    const first = await age();
    expect(first.strippedEvents).toBe(2);

    db().writeCount = 0;
    const second = await age();

    expect(second.strippedEvents).toBe(0);
    expect(second.agedSessions).toBe(0);
    expect(second.cleanSessions).toBe(1);
    expect(db().writeCount).toBe(0);
  });
});

describe("OD-3 location aging: what it must not touch", () => {
  it("leaves a trip that ended inside the window alone", async () => {
    seedSession("recent-trip", RECENT);
    seedFindEvent("recent-trip", "evt-1");

    const result = await age();

    expect(result.scannedSessions).toBe(0);
    expect(result.strippedEvents).toBe(0);
    expect(payloadAt("trip_sessions/recent-trip/activity_events/evt-1").locationLatitude).toBe(
      "37.775"
    );
  });

  it("cannot even see a live trip whose canonicalEndedAt is null", async () => {
    seedSession("live-trip", null);
    seedFindEvent("live-trip", "evt-1");

    const result = await age();

    expect(result.scannedSessions).toBe(0);
    expect(payloadAt("trip_sessions/live-trip/activity_events/evt-1").locationLatitude).toBe(
      "37.775"
    );
  });

  it("rejects a non-timestamp end stamp the range filter handed over", async () => {
    // A boolean sorts below the cutoff number, so the fake's filter returns it — standing in
    // for real Firestore, where an explicit `null` sorts below every Timestamp and is
    // returned by a `<` query it has no business matching. The guard is what refuses it.
    seedSession("garbled-trip", true);
    seedFindEvent("garbled-trip", "evt-1");

    const result = await age();

    expect(result.scannedSessions).toBe(1);
    expect(result.skipped.notAgedEndedTrip).toBe(1);
    expect(result.strippedEvents).toBe(0);
    expect(payloadAt("trip_sessions/garbled-trip/activity_events/evt-1").locationLatitude).toBe(
      "37.775"
    );
  });

  it("reads an aged trip with no location keys without writing to it", async () => {
    seedSession("clean-trip", OLD);
    db().seed("trip_sessions/clean-trip/activity_events/evt-1", {
      kind: "trip_ended",
      actorId: "player-1",
      payload: { reason: "owner_ended" },
    });

    const result = await age();

    expect(result.scannedSessions).toBe(1);
    expect(result.cleanSessions).toBe(1);
    expect(result.agedSessions).toBe(0);
    expect(db().writeCount).toBe(0);
  });
});

describe("OD-3 location aging: caps are loud, never silent", () => {
  it("stops at maxSessions and reports truncation", async () => {
    seedSession("trip-a", OLD);
    seedFindEvent("trip-a", "evt-1");
    seedSession("trip-b", OLD + 1);
    seedFindEvent("trip-b", "evt-1");

    const result = await age({ maxSessions: 1 });
    expect(result.agedSessions).toBe(1);
    expect(result.truncated).toBe(true);

    // The nightly re-run finishes the remainder.
    const second = await age();
    expect(second.agedSessions).toBe(1);
    expect(second.truncated).toBe(false);
  });
});

describe("OD-3 location aging: the pure rules", () => {
  it("strips every legacy location key and returns null when there is nothing to strip", () => {
    const full: Record<string, unknown> = { regionId: "CA", lateReplay: "true" };
    for (const key of LOCATION_PAYLOAD_KEYS) full[key] = "1";

    const stripped = stripLocationPayloadKeys(full)!;
    expect(stripped).toEqual({ regionId: "CA", lateReplay: "true" });

    expect(stripLocationPayloadKeys({ regionId: "CA" })).toBeNull();
    expect(stripLocationPayloadKeys({})).toBeNull();
    expect(stripLocationPayloadKeys(undefined)).toBeNull();
    expect(stripLocationPayloadKeys("not-a-map")).toBeNull();
    expect(stripLocationPayloadKeys([1, 2])).toBeNull();
  });

  it("reads an end stamp only from the two representations that exist", () => {
    expect(sessionEndedAtMillis({ canonicalEndedAt: 1234 })).toBe(1234);
    expect(sessionEndedAtMillis({ canonicalEndedAt: { toMillis: () => 99 } })).toBe(99);
    expect(sessionEndedAtMillis({ canonicalEndedAt: null })).toBeNull();
    expect(sessionEndedAtMillis({ canonicalEndedAt: true })).toBeNull();
    expect(sessionEndedAtMillis({ canonicalEndedAt: "2023-01-01" })).toBeNull();
    expect(sessionEndedAtMillis({})).toBeNull();
    expect(sessionEndedAtMillis(undefined)).toBeNull();
  });
});

describe("OD-3 location-aging window plumbing", () => {
  const originalEnv = process.env.LOCATION_PAYLOAD_RETENTION_DAYS;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.LOCATION_PAYLOAD_RETENTION_DAYS;
    } else {
      process.env.LOCATION_PAYLOAD_RETENTION_DAYS = originalEnv;
    }
  });

  it("defaults to the OD-3 ruling and honors the dev knob", () => {
    delete process.env.LOCATION_PAYLOAD_RETENTION_DAYS;
    expect(locationPayloadRetentionDays()).toBe(LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT);
    expect(LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT).toBe(1095);

    process.env.LOCATION_PAYLOAD_RETENTION_DAYS = "0";
    expect(locationPayloadRetentionDays()).toBe(0);

    process.env.LOCATION_PAYLOAD_RETENTION_DAYS = "not-a-number";
    expect(locationPayloadRetentionDays()).toBe(LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT);

    expect(locationPayloadAgingCutoffMillis(NOW, 1095)).toBe(CUTOFF);
  });

  it("an unset-but-present knob falls to the default, not to zero", () => {
    // `Number("")` is 0, and a 0-day window would strip every ended trip on the first run.
    process.env.LOCATION_PAYLOAD_RETENTION_DAYS = "";
    expect(locationPayloadRetentionDays()).toBe(LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT);

    process.env.LOCATION_PAYLOAD_RETENTION_DAYS = "   ";
    expect(locationPayloadRetentionDays()).toBe(LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT);
  });
});
