/**
 * FR-76 (F-32) — the server does not store whatever it is handed.
 *
 * THE DEFECT: `appendTripActivityEvent` persisted client payloads key-for-key —
 * `stringifyPayload` copied everything it was given into `trip_sessions/{id}/activity_events`,
 * a document every trip member reads. The ~110 m coordinate coarsening was therefore purely
 * client-side: a modified client could persist a full-precision GPS fix, altitude and
 * accuracy for a CHILD's find, and nothing on the server said no.
 *
 * The fix extends the FR-28h sanitize loop (`SERVER_STAMPED_PAYLOAD_KEYS`) into a
 * per-event-type allowlist plus the child/adult location rules. FR-28h semantics are a
 * regression pin here: see also `lateReplayAcceptance.test.ts`.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const h = vi.hoisted(() => ({ nowSec: 1_800_000_000 }));

vi.mock("firebase-admin", () => {
  const ts = (seconds: number, nanoseconds = 0) => ({ seconds, nanoseconds });
  const firestore: any = () => {
    throw new Error("these tests pass the Firestore instance explicitly");
  };
  firestore.FieldValue = { serverTimestamp: () => "__serverTimestamp__" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ts(Math.floor(ms / 1000), Math.round(ms % 1000) * 1e6),
    now: () => ts(h.nowSec),
  };
  return { default: { firestore }, firestore };
});

import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { resolveGameplayAppendTransaction, PK } from "./gameplayEventResolver";
import {
  COARSE_LOCATION_PAYLOAD_KEYS,
  KIND_DISCOVERY_REJECTED,
  KIND_GAME_STARTED,
  KIND_PARTICIPANT_INVITED,
  KIND_PARTICIPANT_LEFT,
  KIND_REGION_FOUND,
  KIND_REGION_REMOVED,
  KIND_TRIP_STARTED,
  LOCATION_PAYLOAD_KEYS,
  PAYLOAD_ALLOWLIST_BY_EVENT_KIND,
  SERVER_STAMPED_PAYLOAD_KEYS,
  sanitizeIncomingEventPayload,
} from "./payloadKeys";
import {
  LOCATION_PAYLOAD_KEYS as SWEEP_LOCATION_PAYLOAD_KEYS,
  deidentifyEventFields,
} from "./accountDeletionDeidentifyCore";

const SESSION = "sess-1";
const GAME = "game-1";
const ADULT = "u-adult";
const CHILD = "u-child";

/** A full-precision fix — what a modified client would send if the server trusted it. */
const PRECISE_FIX = {
  [PK.locationLatitude]: "37.77492950000001",
  [PK.locationLongitude]: "-122.41941550000002",
  [PK.locationAltitude]: "94.7213134765625",
  [PK.locationHorizontalAccuracy]: "4.9482",
  [PK.locationVerticalAccuracy]: "3.1",
  [PK.locationTimestamp]: "1700000100.4567891",
};

function sanitize(
  kind: string,
  payload: Record<string, string>,
  actorIsChild = false
): Record<string, string> {
  return sanitizeIncomingEventPayload({ kind, payload, actorIsChild });
}

// MARK: - (a) Per-event-type allowlist

describe("FR-76(a) — per-event-type allowlist", () => {
  const legitimateFind = {
    [PK.regionId]: "CA",
    [PK.gameInstanceId]: GAME,
    [PK.participantId]: ADULT,
    [PK.inputMethod]: "list",
    [PK.discoveryEventId]: "evt-1",
    [PK.xpDayKey]: "2026-08-14",
  };

  it("keeps every key a current client sends on a region_found", () => {
    expect(sanitize(KIND_REGION_FOUND, legitimateFind)).toEqual(legitimateFind);
  });

  /** Fuzz: 20 junk keys alongside a legitimate find. Dropped silently, never an error. */
  it("drops unknown keys and keeps only the allowlisted ones", () => {
    const junk: Record<string, string> = {};
    for (let i = 0; i < 20; i += 1) {
      junk[`junkKey${i}`] = `junkValue${i}`;
    }
    junk.homeAddress = "1 Private Street";
    junk.deviceId = "ABCD-1234";
    junk["payload.with.dots"] = "x";
    junk[""] = "empty key";

    const out = sanitize(KIND_REGION_FOUND, { ...legitimateFind, ...junk });
    expect(out).toEqual(legitimateFind);
    expect(Object.keys(out).sort()).toEqual(Object.keys(legitimateFind).sort());
  });

  it("allows nothing for a kind that has no allowlist entry", () => {
    expect(sanitize("totally_invented_kind", { anything: "1", regionId: "CA" })).toEqual({});
  });

  it("trip_started / trip_ended carry no payload at all", () => {
    expect(sanitize(KIND_TRIP_STARTED, { [PK.regionId]: "CA", foo: "bar" })).toEqual({});
  });

  it("region_removed keeps only its three keys", () => {
    const out = sanitize(KIND_REGION_REMOVED, {
      [PK.regionId]: "CA",
      [PK.gameInstanceId]: GAME,
      [PK.removedDiscoveryEventId]: "evt-1",
      [PK.participantId]: ADULT,
      ...PRECISE_FIX,
    });
    expect(out).toEqual({
      [PK.regionId]: "CA",
      [PK.gameInstanceId]: GAME,
      [PK.removedDiscoveryEventId]: "evt-1",
    });
  });

  /**
   * `supersededRegionFoundEventId` + the superseded reason is what `replayDiscoveriesFromDocs`
   * honours to VOID a stored find. It is server-authored metadata, so a client-authored
   * rejection can no longer carry it.
   */
  it("discovery_rejected drops the server-authored first-finder / supersede metadata", () => {
    const out = sanitize(KIND_DISCOVERY_REJECTED, {
      [PK.regionId]: "CA",
      [PK.gameInstanceId]: GAME,
      [PK.participantId]: ADULT,
      [PK.inputMethod]: "list",
      [PK.rejectionReason]: "rejected_duplicate",
      [PK.participantCount]: "2",
      [PK.gameMode]: "competitive",
      [PK.supersededRegionFoundEventId]: "victim-event",
      [PK.firstFinderParticipantId]: ADULT,
      [PK.firstFinderEventId]: "forged",
      [PK.firstFinderDiscoveredAt]: "1",
      [PK.clientAttemptEventId]: "x",
      [PK.serverResolvedAt]: "1",
      [PK.clientClaimedAt]: "1",
    });
    expect(out[PK.supersededRegionFoundEventId]).toBeUndefined();
    expect(out[PK.firstFinderParticipantId]).toBeUndefined();
    expect(out[PK.firstFinderEventId]).toBeUndefined();
    expect(out[PK.rejectionReason]).toBe("rejected_duplicate");
    expect(out[PK.gameMode]).toBe("competitive");
  });

  it("participant_left drops the server-only kick attribution", () => {
    const out = sanitize(KIND_PARTICIPANT_LEFT, {
      [PK.participantId]: ADULT,
      [PK.leaveReason]: "voluntary",
      [PK.initiatedByUserId]: "someone-else",
    });
    expect(out).toEqual({ [PK.participantId]: ADULT, [PK.leaveReason]: "voluntary" });
  });

  it("game_started keeps only gameInstanceId", () => {
    expect(sanitize(KIND_GAME_STARTED, { [PK.gameInstanceId]: GAME, [PK.gameMode]: "x" })).toEqual({
      [PK.gameInstanceId]: GAME,
    });
  });

  it("the client-forbidden kinds allow nothing", () => {
    expect(PAYLOAD_ALLOWLIST_BY_EVENT_KIND[KIND_PARTICIPANT_INVITED]).toEqual([]);
    expect(sanitize(KIND_PARTICIPANT_INVITED, { [PK.fromUserId]: "a", [PK.toUserId]: "b" })).toEqual({});
  });

  /** FR-28h regression pin: the server-owned keys never arrive from a client, on any kind. */
  it("server-stamped keys are stripped whatever the kind", () => {
    for (const kind of Object.keys(PAYLOAD_ALLOWLIST_BY_EVENT_KIND)) {
      const out = sanitize(kind, {
        [PK.lateReplay]: "true",
        [PK.serverCommittedAt]: "1",
      });
      expect(out[PK.lateReplay], kind).toBeUndefined();
      expect(out[PK.serverCommittedAt], kind).toBeUndefined();
    }
    for (const key of SERVER_STAMPED_PAYLOAD_KEYS) {
      for (const allowed of Object.values(PAYLOAD_ALLOWLIST_BY_EVENT_KIND)) {
        expect(allowed).not.toContain(key);
      }
    }
  });
});

// MARK: - (b) region_found location rules

describe("FR-76(b) — region_found location keys", () => {
  const find = {
    [PK.regionId]: "CA",
    [PK.gameInstanceId]: GAME,
    [PK.participantId]: ADULT,
    ...PRECISE_FIX,
  };

  it("a CHILD actor's coordinates are stripped, and the find itself survives", () => {
    const out = sanitize(KIND_REGION_FOUND, find, true);
    for (const key of LOCATION_PAYLOAD_KEYS) {
      expect(out[key], key).toBeUndefined();
    }
    expect(out[PK.regionId]).toBe("CA");
    expect(out[PK.participantId]).toBe(ADULT);
  });

  it("an ADULT's full-precision fix is re-rounded server-side to 3 decimals", () => {
    const out = sanitize(KIND_REGION_FOUND, find);
    expect(out[PK.locationLatitude]).toBe("37.775");
    expect(out[PK.locationLongitude]).toBe("-122.419");
    expect(out[PK.locationTimestamp]).toBe("1700000100.457");
  });

  it("altitude and horizontal/vertical accuracy are rejected for everyone", () => {
    for (const actorIsChild of [false, true]) {
      const out = sanitize(KIND_REGION_FOUND, find, actorIsChild);
      expect(out[PK.locationAltitude]).toBeUndefined();
      expect(out[PK.locationHorizontalAccuracy]).toBeUndefined();
      expect(out[PK.locationVerticalAccuracy]).toBeUndefined();
    }
  });

  it("an existing well-behaved client is unaffected — 3dp in, identical 3dp out", () => {
    const alreadyCoarse = {
      ...find,
      [PK.locationLatitude]: "37.775",
      [PK.locationLongitude]: "-122.419",
      [PK.locationTimestamp]: "1700000100.457",
    };
    const out = sanitize(KIND_REGION_FOUND, alreadyCoarse);
    expect(out[PK.locationLatitude]).toBe("37.775");
    expect(out[PK.locationLongitude]).toBe("-122.419");
    expect(out[PK.locationTimestamp]).toBe("1700000100.457");
  });

  it("rounding is idempotent, so a retry compares equal to what was stored", () => {
    const once = sanitize(KIND_REGION_FOUND, find);
    expect(sanitize(KIND_REGION_FOUND, once)).toEqual(once);
  });

  it("non-numeric, blank and out-of-range coordinates are dropped, not stored", () => {
    for (const bad of ["", "   ", "not-a-number", "NaN", "Infinity", "91", "-90.5"]) {
      const out = sanitize(KIND_REGION_FOUND, { ...find, [PK.locationLatitude]: bad });
      expect(out[PK.locationLatitude], bad).toBeUndefined();
    }
    for (const bad of ["181", "-180.5", "1e400"]) {
      const out = sanitize(KIND_REGION_FOUND, { ...find, [PK.locationLongitude]: bad });
      expect(out[PK.locationLongitude], bad).toBeUndefined();
    }
  });
});

// MARK: - (c) One constants module — no drift

describe("FR-76(c) — the deletion sweep and the allowlist share one module", () => {
  it("the sweep's location list IS the shared constant, not a copy", () => {
    expect(SWEEP_LOCATION_PAYLOAD_KEYS).toBe(LOCATION_PAYLOAD_KEYS);
  });

  it("every location key the allowlist can store is one the sweep strips", () => {
    for (const key of COARSE_LOCATION_PAYLOAD_KEYS) {
      expect(LOCATION_PAYLOAD_KEYS, key).toContain(key);
      expect(PAYLOAD_ALLOWLIST_BY_EVENT_KIND[KIND_REGION_FOUND], key).toContain(key);
    }
  });

  it("the precise keys are swept but no longer writable", () => {
    for (const key of [PK.locationAltitude, PK.locationHorizontalAccuracy, PK.locationVerticalAccuracy]) {
      expect(LOCATION_PAYLOAD_KEYS, key).toContain(key);
      expect(PAYLOAD_ALLOWLIST_BY_EVENT_KIND[KIND_REGION_FOUND], key).not.toContain(key);
    }
  });

  it("end to end: what the allowlist stores is exactly what deletion removes", () => {
    const stored = sanitize(KIND_REGION_FOUND, {
      [PK.regionId]: "CA",
      [PK.gameInstanceId]: GAME,
      [PK.participantId]: ADULT,
      ...PRECISE_FIX,
    });
    const cleaned = deidentifyEventFields({ actorId: ADULT, payload: stored }, ADULT);
    for (const key of LOCATION_PAYLOAD_KEYS) {
      expect(cleaned?.payload[key], key).toBeUndefined();
    }
    expect(cleaned?.payload[PK.regionId]).toBe("CA");
  });
});

// MARK: - End to end through the resolver transaction

describe("FR-76 — appendTripActivityEvent persists only the allowlist", () => {
  let db: FakeFirestore;

  function seedTrip(options: { lifecycleState?: string; members?: string[] } = {}) {
    const members = options.members ?? [ADULT];
    db.seed(`trip_sessions/${SESSION}`, { createdBy: members[0] });
    for (const uid of members) {
      db.seed(`trip_sessions/${SESSION}/members/${uid}`, {
        role: uid === members[0] ? "owner" : "member",
        joinedAt: { seconds: 1_700_000_000, nanoseconds: 0 },
      });
    }
    db.seed(`trip_sessions/${SESSION}/games/${GAME}`, {
      commonConfigDataBase64: Buffer.from(
        JSON.stringify({
          gameMode: "collaborative",
          lifecycleState: options.lifecycleState ?? "started",
        })
      ).toString("base64"),
      startedAt: { seconds: 1_700_000_000, nanoseconds: 0 },
      endedAt: { seconds: 1_700_000_500, nanoseconds: 0 },
    });
    db.seed(`users/${ADULT}`, { isChildAccount: false });
    db.seed(`users/${CHILD}`, { isChildAccount: true, activeFamilyId: "fam-1" });
  }

  function append(userId: string, payload: Record<string, string>, eventId = "evt-1") {
    return resolveGameplayAppendTransaction(
      db as unknown as admin.firestore.Firestore,
      SESSION,
      userId,
      {
        id: eventId,
        sessionId: SESSION,
        kind: KIND_REGION_FOUND,
        timestamp: 1_700_000_100,
        actorId: userId,
        payload,
      }
    );
  }

  function storedPayload(eventId = "evt-1"): Record<string, string> {
    const doc = db.store.get(`trip_sessions/${SESSION}/activity_events/${eventId}`);
    return (doc?.payload ?? {}) as Record<string, string>;
  }

  function findPayload(userId: string) {
    return {
      [PK.regionId]: "CA",
      [PK.gameInstanceId]: GAME,
      [PK.participantId]: userId,
      [PK.inputMethod]: "voice",
      [PK.xpDayKey]: "2026-08-14",
      ...PRECISE_FIX,
    };
  }

  beforeEach(() => {
    db = new FakeFirestore();
  });

  it("a CHILD's find is stored WITHOUT any location key", async () => {
    seedTrip({ members: [CHILD] });
    const result = await append(CHILD, findPayload(CHILD));

    expect(result.resolution).toBe("accepted");
    const payload = storedPayload();
    for (const key of LOCATION_PAYLOAD_KEYS) {
      expect(payload[key], key).toBeUndefined();
    }
    // The find itself is untouched — this is a strip, never a rejection.
    expect(payload[PK.regionId]).toBe("CA");
    expect(payload[PK.inputMethod]).toBe("voice");
    expect(payload[PK.participantId]).toBe(CHILD);
  });

  it("the child flag comes from users/{uid}, not from the payload or the client", async () => {
    seedTrip({ members: [CHILD] });
    // The user doc is the only place the flag exists; nothing in the event says "child".
    expect(db.store.get(`users/${CHILD}`)?.isChildAccount).toBe(true);
    await append(CHILD, findPayload(CHILD));
    expect(storedPayload()[PK.locationLatitude]).toBeUndefined();
  });

  it("an ADULT's full-precision fix is persisted rounded to 3 decimals", async () => {
    seedTrip();
    await append(ADULT, findPayload(ADULT));

    const payload = storedPayload();
    expect(payload[PK.locationLatitude]).toBe("37.775");
    expect(payload[PK.locationLongitude]).toBe("-122.419");
    expect(payload[PK.locationTimestamp]).toBe("1700000100.457");
    expect(payload[PK.locationAltitude]).toBeUndefined();
    expect(payload[PK.locationHorizontalAccuracy]).toBeUndefined();
    expect(payload[PK.locationVerticalAccuracy]).toBeUndefined();
  });

  it("20 junk keys plus forged server keys persist nothing beyond the allowlist", async () => {
    seedTrip();
    const junk: Record<string, string> = {
      [PK.lateReplay]: "true",
      [PK.serverCommittedAt]: "1",
      [PK.firstFinderParticipantId]: "someone-else",
      [PK.initiatedByUserId]: "someone-else",
    };
    for (let i = 0; i < 20; i += 1) junk[`junk${i}`] = String(i);

    await append(ADULT, { ...findPayload(ADULT), ...junk });

    expect(Object.keys(storedPayload()).sort()).toEqual(
      [
        PK.regionId,
        PK.gameInstanceId,
        PK.participantId,
        PK.inputMethod,
        PK.xpDayKey,
        PK.locationLatitude,
        PK.locationLongitude,
        PK.locationTimestamp,
      ].sort()
    );
  });

  /**
   * The sanitize runs BEFORE the idempotency comparison, so a retry of the very same raw
   * payload normalizes to the stored copy instead of looking like an id collision.
   */
  it("a retry of the same raw payload stays idempotent", async () => {
    seedTrip();
    const raw = { ...findPayload(ADULT), junkKey: "junkValue" };
    await append(ADULT, raw);
    const first = { ...storedPayload() };

    const retry = await append(ADULT, raw);
    expect(retry.resolution).toBe("accepted");
    expect(storedPayload()).toEqual(first);
  });

  /** FR-28h pin: the server still stamps, and still stamps only from the server path. */
  it("the server still stamps lateReplay on a late solo replay", async () => {
    seedTrip({ lifecycleState: "ended", members: [ADULT] });
    const result = await append(ADULT, {
      ...findPayload(ADULT),
      [PK.lateReplay]: "false",
      [PK.serverCommittedAt]: "1",
    });

    expect(result.lateReplay).toBe(true);
    expect(storedPayload()[PK.lateReplay]).toBe("true");
  });

  it("an ordinary find carries no lateReplay stamp even when the client sends one", async () => {
    seedTrip();
    const result = await append(ADULT, { ...findPayload(ADULT), [PK.lateReplay]: "true" });

    expect(result.lateReplay).toBe(false);
    expect(storedPayload()[PK.lateReplay]).toBeUndefined();
  });
});
