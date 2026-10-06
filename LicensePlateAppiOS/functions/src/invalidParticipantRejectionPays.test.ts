/**
 * SRS §3.1.1 item 24 — the server-authored invalid-participant rejection pays the find.
 *
 * THE CASE: a partner who leaves (or is kicked) has their `members` doc deleted while their
 * finds stay. The trip then reads as SOLO on the server, so the remaining player's next find of a
 * plate the partner holds resolves to `rejected_invalid_participant`, and the resolver writes
 * `srvrej_<clientEventId>` in place of the find. The device has already shown +10 base,
 * +20 lifetime-unique and +10 first-of-day for it. OD-17: a shown number never goes down.
 *
 * PINNED here: that rejection pays exactly what a late competitive rejection pays —
 * base + lifetime-unique + first-of-day under the device's `xpDayKey`, never the +5 — and only
 * when the SERVER wrote it. A client writes the same reason for its own tap-time rejection (a
 * find it refused and never credited); that one must still pay nothing.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

/** 2026-08-15T01:01:00Z — the server's clock when it stamps the rejection. */
const h = vi.hoisted(() => ({ nowSec: 1_786_755_660 }));

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
import {
  resolveGameplayAppendTransaction,
  PK,
  KIND_REGION_FOUND,
  KIND_DISCOVERY_REJECTED,
  KIND_PARTICIPANT_LEFT,
  REJECTION_INVALID_PARTICIPANT,
} from "./gameplayEventResolver";
import {
  previewProgressionComponentsForActivityEvent,
  baseRegionDiscoveryScopeKey,
  lifetimeUniqueRegionScopeKey,
  firstFindOfDayScopeKey,
  XP_AMOUNTS,
} from "./progressionCore";
import { XP_GRANT_REASON } from "./xpGrantLedgerCore";

const SESSION = "sess-invalid-participant";
const GAME = "game-invalid-participant";
const U_SOLO = "u-solo"; // owner — still on the trip
const U_LEFT = "u-left"; // member who finds the plate first, then leaves

/** The DEVICE's day for every find below. */
const LOCAL_DAY = "2026-08-14";

const GAME_STARTED_SEC = 1_786_700_000; // 2026-08-14T09:33:20Z
const LEFT_FIND_SEC = 1_786_744_800; // 2026-08-14T22:00:00Z
const LEFT_LEAVES_SEC = 1_786_745_400; // 2026-08-14T22:10:00Z
const SOLO_FIND_SEC = 1_786_746_000; // 2026-08-14T22:20:00Z

describe("SRS item 24 — the server's invalid-participant rejection pays the find", () => {
  let db: FakeFirestore;

  function seedTrip(gameMode: "competitive" | "collaborative") {
    db.seed(`trip_sessions/${SESSION}`, { createdBy: U_SOLO });
    db.seed(`trip_sessions/${SESSION}/members/${U_SOLO}`, {
      role: "owner",
      joinedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`trip_sessions/${SESSION}/members/${U_LEFT}`, {
      role: "member",
      joinedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`trip_sessions/${SESSION}/games/${GAME}`, {
      commonConfigDataBase64: Buffer.from(
        JSON.stringify({ gameMode, lifecycleState: "started" })
      ).toString("base64"),
      startedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`users/${U_SOLO}`, { isChildAccount: false });
    db.seed(`users/${U_LEFT}`, { isChildAccount: false });
  }

  function submit(
    userId: string,
    eventId: string,
    kind: string,
    timestampSec: number,
    payload: Record<string, string>
  ) {
    return resolveGameplayAppendTransaction(
      db as unknown as admin.firestore.Firestore,
      SESSION,
      userId,
      { id: eventId, sessionId: SESSION, kind, timestamp: timestampSec, actorId: userId, payload }
    );
  }

  function submitFind(userId: string, eventId: string, timestampSec: number) {
    return submit(userId, eventId, KIND_REGION_FOUND, timestampSec, {
      [PK.regionId]: "US-CA",
      [PK.gameInstanceId]: GAME,
      [PK.participantId]: userId,
      [PK.inputMethod]: "list",
      [PK.xpDayKey]: LOCAL_DAY,
    });
  }

  /** U_LEFT finds CA, then leaves: the server now reads the trip as solo (one members doc). */
  async function partnerFindsThenLeaves() {
    expect((await submitFind(U_LEFT, "evt-left-ca", LEFT_FIND_SEC)).resolution).toBe("accepted");
    const left = await submit(U_LEFT, "evt-left-leaves", KIND_PARTICIPANT_LEFT, LEFT_LEAVES_SEC, {
      [PK.participantId]: U_LEFT,
    });
    expect(left.resolution).toBe("accepted");
    expect(db.store.has(`trip_sessions/${SESSION}/members/${U_LEFT}`)).toBe(false);
  }

  function storedEvent(eventId: string): {
    payload: Record<string, string>;
    actorId: unknown;
    timestampSec: number;
  } {
    const doc = db.store.get(`trip_sessions/${SESSION}/activity_events/${eventId}`);
    expect(doc, `event ${eventId} was not written`).toBeTruthy();
    const ts = doc!.timestamp as { seconds: number };
    return {
      payload: (doc!.payload ?? {}) as Record<string, string>,
      actorId: doc!.actorId,
      timestampSec: ts.seconds,
    };
  }

  function gameDocs(): admin.firestore.QueryDocumentSnapshot[] {
    const data = db.store.get(`trip_sessions/${SESSION}/games/${GAME}`)!;
    return [{ id: GAME, data: () => data } as admin.firestore.QueryDocumentSnapshot];
  }

  /** Exactly what the `onCreate` trigger computes for one stored event; only U_SOLO is a member now. */
  function componentsFor(eventId: string) {
    const { payload, actorId, timestampSec } = storedEvent(eventId);
    return previewProgressionComponentsForActivityEvent({
      kind: KIND_DISCOVERY_REJECTED,
      actorId: (actorId as string) ?? null,
      payload,
      memberUserIds: [U_SOLO],
      sessionId: SESSION,
      eventTimestampSeconds: timestampSec,
      gameDocs: gameDocs(),
      activityEventDocs: [],
    });
  }

  beforeEach(() => {
    db = new FakeFirestore();
  });

  for (const gameMode of ["competitive", "collaborative"] as const) {
    it(`${gameMode}: pays base + lifetime-unique + first-of-day to the finder, never the +5`, async () => {
      seedTrip(gameMode);
      await partnerFindsThenLeaves();

      const rejected = await submitFind(U_SOLO, "evt-solo-ca", SOLO_FIND_SEC);
      expect(rejected.resolution).toBe("superseded");
      // The client's own find is never written; the server's rejection stands in for it.
      expect(db.store.has(`trip_sessions/${SESSION}/activity_events/evt-solo-ca`)).toBe(false);

      const rejection = storedEvent("srvrej_evt-solo-ca");
      expect(rejection.payload[PK.rejectionReason]).toBe(REJECTION_INVALID_PARTICIPANT);
      expect(rejection.payload[PK.participantId]).toBe(U_SOLO);
      expect(rejection.actorId).toBe(U_SOLO);
      expect(rejection.payload[PK.serverResolvedAt]).toBe(String(h.nowSec));
      // Item 18's carry-over covers this rejection too: same block, same day key.
      expect(rejection.payload[PK.xpDayKey]).toBe(LOCAL_DAY);

      const byUser = componentsFor("srvrej_evt-solo-ca");
      expect(Object.keys(byUser)).toEqual([U_SOLO]);
      const components = byUser[U_SOLO];
      expect(components.map((c) => c.scopeKey).sort()).toEqual(
        [
          baseRegionDiscoveryScopeKey({ userId: U_SOLO, sessionId: SESSION, payload: rejection.payload })!,
          lifetimeUniqueRegionScopeKey(U_SOLO, "US-CA"),
          firstFindOfDayScopeKey(U_SOLO, LOCAL_DAY),
        ].sort()
      );
      expect(components.some((c) => c.reason === XP_GRANT_REASON.COMPETITIVE_FIRST_FINDER)).toBe(false);
      expect(components.reduce((sum, c) => sum + c.amount, 0)).toBe(
        XP_AMOUNTS.baseDiscoveryXp +
          XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp +
          XP_AMOUNTS.firstFindOfDayBonusXp
      );
      expect(components.reduce((sum, c) => sum + (c.acceptedRegionFindCount ?? 0), 0)).toBe(1);
    });
  }

  /**
   * The authorship gate. The client writes `rejected_invalid_participant` itself when it refuses a
   * find at tap time, and the resolver passes that through under the client's own event id — which
   * the client may name `srvrej_…`. Its forged `serverResolvedAt` is dropped by the FR-76
   * allowlist, so the stored rejection pays nothing: a refused find earns nothing.
   */
  it("a CLIENT-authored invalid-participant rejection pays nothing, even under a srvrej_ id", async () => {
    seedTrip("competitive");
    await partnerFindsThenLeaves();

    const passthrough = await submit(
      U_SOLO,
      "srvrej_forged",
      KIND_DISCOVERY_REJECTED,
      SOLO_FIND_SEC,
      {
        [PK.regionId]: "US-CA",
        [PK.gameInstanceId]: GAME,
        [PK.participantId]: U_SOLO,
        [PK.rejectionReason]: REJECTION_INVALID_PARTICIPANT,
        [PK.serverResolvedAt]: String(h.nowSec),
      }
    );
    expect(passthrough.resolution).toBe("passthrough");

    const stored = storedEvent("srvrej_forged");
    expect(stored.payload[PK.rejectionReason]).toBe(REJECTION_INVALID_PARTICIPANT);
    expect(stored.payload[PK.serverResolvedAt]).toBeUndefined();
    expect(componentsFor("srvrej_forged")).toEqual({});
  });
});
