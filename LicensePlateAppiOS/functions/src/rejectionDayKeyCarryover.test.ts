/**
 * SRS item 18 — the server-authored late-competitive rejection lost the device's day.
 *
 * THE DEFECT: `gameplayEventResolver` builds the `discovery_rejected` / `srvrej_<id>`
 * payload FIELD BY FIELD (the accepted path spreads the incoming payload and so keeps
 * `xpDayKey` for free). `xpDayKey` was never copied, so `progressionCore` fell through to
 * the UTC day of the SERVER's rejection timestamp. Two consequences, both real in the
 * Americas, where an evening find is already "tomorrow" in UTC:
 *
 *   (a) the find is billed under the next UTC day, minting a SECOND
 *       `first_find_of_day|v1|<uid>|<day>` scope — the bonus is paid twice in one real day;
 *   (b) the client's toast dedup (item 14, `XpGainToastEligibility.mirroredServerScopeKey`,
 *       keyed on the device's LOCAL day) cannot match that scope, so the first-find toast
 *       doubles on this path too.
 *
 * OD-16 is the rule these tests encode: the device's day is the truth, and the server
 * reconciles to it. The fallback is therefore the UTC day of the CLIENT's claimed find
 * time, never the server clock — for an FR-28h offline drain those are days apart.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

/** 2026-08-15T01:01:00Z — i.e. 20:01 on 2026-08-14 in the Americas. */
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
  REJECTION_SERVER_LATE_COMPETITIVE,
  REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP,
} from "./gameplayEventResolver";
import {
  previewProgressionComponentsForActivityEvent,
  lifetimeUniqueRegionScopeKey,
  firstFindOfDayScopeKey,
  XP_AMOUNTS,
} from "./progressionCore";
import { sanitizeIncomingEventPayload } from "./payloadKeys";

const SESSION = "sess-daykey";
const GAME = "game-daykey";
const U_FIRST = "u-first"; // owner, wins the contested region
const U_LATE = "u-late"; // the late finder whose find becomes a server rejection

/** 2026-08-14 in the Americas — the DEVICE's day for every find below. */
const LOCAL_DAY = "2026-08-14";
/** The UTC day the server's clock is on when it stamps the rejection. */
const SERVER_UTC_DAY = "2026-08-15";

const GAME_STARTED_SEC = 1_786_700_000; // 2026-08-14T09:33:20Z
const TX_FIND_SEC = 1_786_744_800; // 2026-08-14T22:00:00Z — 17:00 local, UTC day == local day
const CA_FIRST_SEC = 1_786_753_800; // 2026-08-15T00:30:00Z — 19:30 local, UTC has rolled over
const CA_LATE_SEC = 1_786_755_600; // 2026-08-15T01:00:00Z — 20:00 local, the losing attempt

describe("SRS item 18 — the late-competitive rejection carries the device's xpDayKey", () => {
  let db: FakeFirestore;

  function seedCompetitiveTrip() {
    db.seed(`trip_sessions/${SESSION}`, { createdBy: U_FIRST });
    db.seed(`trip_sessions/${SESSION}/members/${U_FIRST}`, {
      role: "owner",
      joinedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`trip_sessions/${SESSION}/members/${U_LATE}`, {
      role: "member",
      joinedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`trip_sessions/${SESSION}/games/${GAME}`, {
      commonConfigDataBase64: Buffer.from(
        JSON.stringify({ gameMode: "competitive", lifecycleState: "started" })
      ).toString("base64"),
      startedAt: { seconds: GAME_STARTED_SEC, nanoseconds: 0 },
    });
    db.seed(`users/${U_FIRST}`, { isChildAccount: false });
    db.seed(`users/${U_LATE}`, { isChildAccount: false });
  }

  function submitFind(options: {
    userId: string;
    eventId: string;
    regionId: string;
    timestampSec: number;
    xpDayKey?: string;
  }) {
    const payload: Record<string, string> = {
      [PK.regionId]: options.regionId,
      [PK.gameInstanceId]: GAME,
      [PK.participantId]: options.userId,
      [PK.inputMethod]: "list",
    };
    if (options.xpDayKey !== undefined) payload[PK.xpDayKey] = options.xpDayKey;
    return resolveGameplayAppendTransaction(
      db as unknown as admin.firestore.Firestore,
      SESSION,
      options.userId,
      {
        id: options.eventId,
        sessionId: SESSION,
        kind: KIND_REGION_FOUND,
        timestamp: options.timestampSec,
        actorId: options.userId,
        payload,
      }
    );
  }

  function storedEvent(eventId: string): { payload: Record<string, string>; timestampSec: number } {
    const doc = db.store.get(`trip_sessions/${SESSION}/activity_events/${eventId}`);
    expect(doc, `event ${eventId} was not written`).toBeTruthy();
    const ts = doc!.timestamp as { seconds: number };
    return { payload: (doc!.payload ?? {}) as Record<string, string>, timestampSec: ts.seconds };
  }

  /** The game docs `previewProgressionComponentsForActivityEvent` reads, from the fake store. */
  function gameDocs(): admin.firestore.QueryDocumentSnapshot[] {
    const data = db.store.get(`trip_sessions/${SESSION}/games/${GAME}`)!;
    return [{ id: GAME, data: () => data } as admin.firestore.QueryDocumentSnapshot];
  }

  /** Exactly what the `onCreate` trigger computes for one stored event, for one user. */
  function componentsFor(eventId: string, kind: string, uid: string) {
    const { payload, timestampSec } = storedEvent(eventId);
    const byUser = previewProgressionComponentsForActivityEvent({
      kind,
      actorId: payload[PK.participantId] ?? null,
      payload,
      memberUserIds: [U_FIRST, U_LATE],
      sessionId: SESSION,
      eventTimestampSeconds: timestampSec,
      gameDocs: gameDocs(),
      activityEventDocs: [],
    });
    return byUser[uid] ?? [];
  }

  beforeEach(() => {
    db = new FakeFirestore();
    seedCompetitiveTrip();
  });

  /**
   * The headline regression: one real evening, one user, two paid first-finds-of-day.
   *
   * `U_LATE` finds TX uncontested at 17:00 local, then loses CA to `U_FIRST` at 20:00 local.
   * Both events are the same DEVICE day; the second one's server stamp is the next UTC day.
   * The trigger skips a component whose scope is already in `appliedProgressionScopes`, so
   * a stable day key is the only thing that stops the second grant.
   */
  it("bills an evening find and its late-competitive rejection under ONE day scope", async () => {
    const accepted = await submitFind({
      userId: U_LATE,
      eventId: "evt-tx",
      regionId: "US-TX",
      timestampSec: TX_FIND_SEC,
      xpDayKey: LOCAL_DAY,
    });
    expect(accepted.resolution).toBe("accepted");

    const firstFinder = await submitFind({
      userId: U_FIRST,
      eventId: "evt-ca-first",
      regionId: "US-CA",
      timestampSec: CA_FIRST_SEC,
      xpDayKey: LOCAL_DAY,
    });
    expect(firstFinder.resolution).toBe("accepted");

    const rejected = await submitFind({
      userId: U_LATE,
      eventId: "evt-ca-late",
      regionId: "US-CA",
      timestampSec: CA_LATE_SEC,
      xpDayKey: LOCAL_DAY,
    });
    expect(rejected.resolution).toBe("superseded");

    // The server authored the rejection doc; the client's own find was never written.
    expect(db.store.has(`trip_sessions/${SESSION}/activity_events/evt-ca-late`)).toBe(false);
    const rejection = storedEvent("srvrej_evt-ca-late");
    expect(rejection.payload[PK.rejectionReason]).toBe(REJECTION_SERVER_LATE_COMPETITIVE);
    // The premise of the whole defect: the server stamp is already the NEXT UTC day.
    expect(rejection.timestampSec).toBe(h.nowSec);

    const applied = new Set<string>();
    for (const c of componentsFor("evt-tx", KIND_REGION_FOUND, U_LATE)) applied.add(c.scopeKey);
    expect(applied).toContain(firstFindOfDayScopeKey(U_LATE, LOCAL_DAY));

    const rejectionComponents = componentsFor(
      "srvrej_evt-ca-late",
      KIND_DISCOVERY_REJECTED,
      U_LATE
    );
    // The late finder is still paid for the find itself — only the DAY bonus must not repeat.
    expect(rejectionComponents.map((c) => c.scopeKey)).toContain(
      lifetimeUniqueRegionScopeKey(U_LATE, "US-CA")
    );

    const dayScopes = [...applied, ...rejectionComponents.map((c) => c.scopeKey)].filter((k) =>
      k.startsWith("first_find_of_day|")
    );
    expect(new Set(dayScopes).size, `day scopes seen: ${[...new Set(dayScopes)].join(", ")}`).toBe(1);
    expect(dayScopes.every((k) => k === firstFindOfDayScopeKey(U_LATE, LOCAL_DAY))).toBe(true);
    expect(dayScopes).not.toContain(firstFindOfDayScopeKey(U_LATE, SERVER_UTC_DAY));

    // And the trigger's own filter: nothing fresh to pay for the day on the rejection.
    const fresh = rejectionComponents.filter((c) => !applied.has(c.scopeKey));
    expect(fresh.some((c) => c.scopeKey.startsWith("first_find_of_day|"))).toBe(false);
    expect(fresh.reduce((sum, c) => sum + c.amount, 0)).toBe(
      XP_AMOUNTS.baseDiscoveryXp + XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp
    );
  });

  it("stamps the client's well-formed xpDayKey onto the rejection payload", async () => {
    await submitFind({
      userId: U_FIRST,
      eventId: "evt-ca-first",
      regionId: "US-CA",
      timestampSec: CA_FIRST_SEC,
      xpDayKey: LOCAL_DAY,
    });
    await submitFind({
      userId: U_LATE,
      eventId: "evt-ca-late",
      regionId: "US-CA",
      timestampSec: CA_LATE_SEC,
      xpDayKey: LOCAL_DAY,
    });

    expect(storedEvent("srvrej_evt-ca-late").payload[PK.xpDayKey]).toBe(LOCAL_DAY);
  });

  it("falls back to the UTC day of the CLIENT's claimed find when the key is malformed", async () => {
    await submitFind({
      userId: U_FIRST,
      eventId: "evt-ca-first",
      regionId: "US-CA",
      timestampSec: CA_FIRST_SEC,
    });
    await submitFind({
      userId: U_LATE,
      eventId: "evt-ca-late",
      regionId: "US-CA",
      timestampSec: CA_LATE_SEC,
      xpDayKey: "2026-8-14", // not zero-padded: `normalizeXpDayKey` rejects it
    });

    const payload = storedEvent("srvrej_evt-ca-late").payload;
    // CA_LATE_SEC is itself on 2026-08-15 UTC, so this fallback is the same day the old
    // code produced — the point is that it comes from `clientClaimedAt`, not the clock.
    expect(payload[PK.xpDayKey]).toBe("2026-08-15");
    expect(payload[PK.clientClaimedAt]).toBe(String(CA_LATE_SEC));
  });

  /**
   * The fallback is the DEVICE's instant, not the server's. Here the losing attempt was
   * claimed at 22:00 UTC on the 14th while the server stamps the rejection at 01:01 UTC on
   * the 15th: a server-clock fallback would bill the wrong day even with no key at all.
   */
  it("with no xpDayKey at all, uses the claimed find's day, not the server stamp's", async () => {
    await submitFind({
      userId: U_FIRST,
      eventId: "evt-ca-first",
      regionId: "US-CA",
      timestampSec: GAME_STARTED_SEC + 60,
    });
    await submitFind({
      userId: U_LATE,
      eventId: "evt-ca-late",
      regionId: "US-CA",
      timestampSec: TX_FIND_SEC, // 2026-08-14T22:00Z, later than the winner's find
    });

    const payload = storedEvent("srvrej_evt-ca-late").payload;
    expect(payload[PK.xpDayKey]).toBe(LOCAL_DAY);
    expect(payload[PK.xpDayKey]).not.toBe(SERVER_UTC_DAY);

    const dayScopes = componentsFor("srvrej_evt-ca-late", KIND_DISCOVERY_REJECTED, U_LATE)
      .map((c) => c.scopeKey)
      .filter((k) => k.startsWith("first_find_of_day|"));
    expect(dayScopes).toEqual([firstFindOfDayScopeKey(U_LATE, LOCAL_DAY)]);
  });

  /**
   * FR-76 is untouched: `xpDayKey` is NOT on the `discovery_rejected` allowlist and does not
   * need to be. The server writes `srvrej_*` directly, bypassing the sanitize pass, so the
   * carry-over needs no allowlist entry — and a client still cannot author one.
   */
  it("a CLIENT-authored discovery_rejected still has its xpDayKey dropped", () => {
    const out = sanitizeIncomingEventPayload({
      kind: KIND_DISCOVERY_REJECTED,
      payload: {
        [PK.regionId]: "US-CA",
        [PK.gameInstanceId]: GAME,
        [PK.participantId]: U_LATE,
        [PK.rejectionReason]: "rejected_duplicate",
        [PK.xpDayKey]: LOCAL_DAY,
      },
      actorIsChild: false,
    });
    expect(out[PK.xpDayKey]).toBeUndefined();
    expect(out[PK.rejectionReason]).toBe("rejected_duplicate");
  });

  /**
   * The sibling server-authored payload. It is also built field by field and also has no
   * `xpDayKey` — correctly, because it grants nothing. This pins that "grants nothing":
   * if it ever changes, the day key has to be stamped from the DISPLACED finder's own
   * claimed time, not from the caller's payload and not from the server clock.
   */
  it("the supersede rejection grants no XP, which is why it needs no day key", () => {
    const components = previewProgressionComponentsForActivityEvent({
      kind: KIND_DISCOVERY_REJECTED,
      actorId: U_FIRST,
      payload: {
        [PK.regionId]: "US-CA",
        [PK.gameInstanceId]: GAME,
        [PK.participantId]: U_FIRST,
        [PK.rejectionReason]: REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP,
      },
      memberUserIds: [U_FIRST, U_LATE],
      sessionId: SESSION,
      eventTimestampSeconds: h.nowSec,
      gameDocs: gameDocs(),
      activityEventDocs: [],
    });
    expect(components).toEqual({});
  });

  /**
   * `lifetime_unique_region` is scoped on the region alone, so no day key can move it.
   * Stated as a test because item 18's brief asks for it to be confirmed unaffected.
   */
  it("lifetime_unique_region is region-scoped and unaffected by the day key", async () => {
    await submitFind({
      userId: U_FIRST,
      eventId: "evt-ca-first",
      regionId: "US-CA",
      timestampSec: CA_FIRST_SEC,
    });
    await submitFind({
      userId: U_LATE,
      eventId: "evt-ca-late",
      regionId: "US-CA",
      timestampSec: CA_LATE_SEC,
      xpDayKey: LOCAL_DAY,
    });

    const scopes = componentsFor("srvrej_evt-ca-late", KIND_DISCOVERY_REJECTED, U_LATE).map(
      (c) => c.scopeKey
    );
    expect(scopes).toContain(lifetimeUniqueRegionScopeKey(U_LATE, "US-CA"));
    expect(lifetimeUniqueRegionScopeKey(U_LATE, "US-CA")).toBe(
      `lifetime_unique_region|v1|${U_LATE}|US-CA`
    );
  });
});
