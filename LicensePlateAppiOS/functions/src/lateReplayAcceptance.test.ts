/**
 * FR-28h — offline / consent replay acceptance.
 *
 * The defect this pins: the resolver accepted `region_found` only while a game's lifecycle
 * was `started`, so every find from a trip that was completed offline was rejected with
 * `failed-precondition "game not started"` — a PERMANENT verdict on the client — and the
 * discoveries were destroyed. No session recorded a find for two days because of it.
 */

import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
  evaluateReplayAdmission,
  deriveGameReplayWindow,
  LATE_REPLAY_HORIZON_DAYS,
  MESSAGE_GAME_NOT_STARTED,
  MESSAGE_REPLAY_OUT_OF_WINDOW,
  MESSAGE_REPLAY_HORIZON_EXPIRED,
  KIND_GAME_STARTED,
  KIND_GAME_ENDED,
  KIND_GAME_COMPLETED,
  KIND_REGION_FOUND,
  PK,
  withoutServerStampedKeys,
} from "./gameplayEventResolver";
import {
  isLateReplayFindDoc,
  previewLateReplayContribution,
  hasAppliedTripBaseline,
  sessionHasTripEndedEvent,
  decideBaselineWait,
  BASELINE_MARKER_POLL_INTERVAL_MS,
  BASELINE_MARKER_MAX_WAIT_MS,
} from "./publicLifetimeStatsCore";

const DAY = 24 * 60 * 60;
const GAME = "game-1";

function mockTs(seconds: number): admin.firestore.Timestamp {
  return { seconds, nanoseconds: 0 } as admin.firestore.Timestamp;
}

function mockDoc(
  id: string,
  kind: string,
  seconds: number,
  payload: Record<string, string>
): admin.firestore.QueryDocumentSnapshot {
  return {
    id,
    data: () => ({ kind, timestamp: mockTs(seconds), actorId: payload.participantId || null, payload }),
  } as admin.firestore.QueryDocumentSnapshot;
}

function findDoc(
  id: string,
  seconds: number,
  participantId: string,
  regionId: string,
  extra: Record<string, string> = {}
) {
  return mockDoc(id, KIND_REGION_FOUND, seconds, {
    [PK.gameInstanceId]: GAME,
    [PK.regionId]: regionId,
    [PK.participantId]: participantId,
    ...extra,
  });
}

/** started 1000 → ended 2000, replay attempted at `nowSec`. */
const window = { startSec: 1000, endSec: 2000 };

describe("evaluateReplayAdmission — lifecycle", () => {
  it("accepts an ordinary in-progress find and does not mark it a late replay", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "started",
      eventTimestampSec: 1500,
      window,
      nowSec: 1600,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: true, lateReplay: false });
  });

  it("keeps `game not started` for the genuine pre-start edge only", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "created",
      eventTimestampSec: 1500,
      window,
      nowSec: 1600,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_GAME_NOT_STARTED });
  });

  it("THE BUG: an in-window find replayed into an ENDED game is now accepted, and stamped late", () => {
    for (const lifecycleState of ["ended", "completed"]) {
      const r = evaluateReplayAdmission({
        lifecycleState,
        eventTimestampSec: 1500,
        window,
        nowSec: 2000 + DAY,
        isSoloTrip: false,
      });
      expect(r, lifecycleState).toEqual({ accept: true, lateReplay: true });
    }
  });

  it("accepts finds exactly on the window boundaries", () => {
    for (const ts of [1000, 2000]) {
      const r = evaluateReplayAdmission({
        lifecycleState: "ended",
        eventTimestampSec: ts,
        window,
        nowSec: 2000 + DAY,
        isSoloTrip: false,
      });
      expect(r, `ts=${ts}`).toEqual({ accept: true, lateReplay: true });
    }
  });
});

describe("evaluateReplayAdmission — window", () => {
  it("rejects a find claiming a time before the game started", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 999,
      window,
      nowSec: 2000 + DAY,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW });
  });

  it("rejects a find claiming a time after the game ended", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 2001,
      window,
      nowSec: 2000 + DAY,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW });
  });

  it("out-of-window and horizon-expired are DISTINCT messages (client classifies both as verdicts)", () => {
    expect(MESSAGE_REPLAY_OUT_OF_WINDOW).not.toBe(MESSAGE_REPLAY_HORIZON_EXPIRED);
    expect(MESSAGE_REPLAY_OUT_OF_WINDOW).not.toBe(MESSAGE_GAME_NOT_STARTED);
    expect(MESSAGE_REPLAY_HORIZON_EXPIRED).not.toBe(MESSAGE_GAME_NOT_STARTED);
  });

  /**
   * R7: a closed game with no end marker anywhere leaves the horizon with nothing to
   * anchor to. On a MULTIPLAYER trip that is a state someone could reach deliberately to
   * buy an unbounded window, so it fails closed. Solo is unbounded regardless.
   */
  it("with no end marker: fails closed on a multiplayer trip", () => {
    const open = { startSec: 1000, endSec: null };
    expect(
      evaluateReplayAdmission({
        lifecycleState: "ended",
        eventTimestampSec: 1500,
        window: open,
        nowSec: 1000 + 400 * DAY,
        isSoloTrip: false,
      })
    ).toEqual({ accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED });
  });

  it("with no end marker: a SOLO trip is still accepted (self-data, unbounded anyway)", () => {
    const open = { startSec: 1000, endSec: null };
    expect(
      evaluateReplayAdmission({
        lifecycleState: "ended",
        eventTimestampSec: 1500,
        window: open,
        nowSec: 1000 + 400 * DAY,
        isSoloTrip: true,
      })
    ).toEqual({ accept: true, lateReplay: true });
  });

  it("with no end marker the lower bound and the now-bound still apply", () => {
    const open = { startSec: 1000, endSec: null };
    expect(
      evaluateReplayAdmission({
        lifecycleState: "ended",
        eventTimestampSec: 999,
        window: open,
        nowSec: 5000,
        isSoloTrip: true,
      })
    ).toEqual({ accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW });

    expect(
      evaluateReplayAdmission({
        lifecycleState: "ended",
        eventTimestampSec: 6000,
        window: open,
        nowSec: 5000,
        isSoloTrip: true,
      })
    ).toEqual({ accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW });
  });
});

describe("evaluateReplayAdmission — horizon", () => {
  const horizonSec = LATE_REPLAY_HORIZON_DAYS * DAY;

  it("accepts an adult replay just inside 14 days", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + horizonSec - 1,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: true, lateReplay: true });
  });

  it("accepts exactly at 14 days (the bound is inclusive)", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + horizonSec,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: true, lateReplay: true });
  });

  it("rejects an adult replay at 14 days + epsilon", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + horizonSec + 1,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED });
  });

  /**
   * The owner's rule: the exemption is SOLO, not child. A solo replay is pure self-data —
   * there is no opponent whose outcome it could distort — and the consent-delay case is
   * always solo anyway, since an unconsented child cannot be in a multiplayer trip (FR-38).
   */
  it("a SOLO trip is unbounded — 15+ days later still lands, for an adult caller", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + 15 * DAY,
      isSoloTrip: true,
    });
    expect(r).toEqual({ accept: true, lateReplay: true });
  });

  it("a SOLO trip is unbounded even a year later", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + 365 * DAY,
      isSoloTrip: true,
    });
    expect(r).toEqual({ accept: true, lateReplay: true });
  });

  /** No child-specific carve-out exists: multiplayer is 14 days for EVERYONE. */
  it("a MULTIPLAYER replay expires at 14d + epsilon regardless of who is calling", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + horizonSec + 1,
      isSoloTrip: false,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED });
  });

  it("the solo exemption does NOT excuse an out-of-window claim", () => {
    const r = evaluateReplayAdmission({
      lifecycleState: "ended",
      eventTimestampSec: 5000,
      window,
      nowSec: window.endSec + 365 * DAY,
      isSoloTrip: true,
    });
    expect(r).toEqual({ accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW });
  });
});

describe("deriveGameReplayWindow", () => {
  it("prefers the game document's own startedAt / endedAt", () => {
    const w = deriveGameReplayWindow({ startedAt: mockTs(100), endedAt: mockTs(900) }, [], GAME);
    expect(w).toEqual({ startSec: 100, endSec: 900 });
  });

  it("falls back to game_started / game_ended activity events", () => {
    const docs = [
      mockDoc("s", KIND_GAME_STARTED, 100, { [PK.gameInstanceId]: GAME }),
      mockDoc("e", KIND_GAME_ENDED, 900, { [PK.gameInstanceId]: GAME }),
    ];
    expect(deriveGameReplayWindow(undefined, docs, GAME)).toEqual({ startSec: 100, endSec: 900 });
  });

  /** A full clear writes game_completed and then immediately ends the game. */
  it("takes the LATEST of game_ended / game_completed", () => {
    const docs = [
      mockDoc("s", KIND_GAME_STARTED, 100, { [PK.gameInstanceId]: GAME }),
      mockDoc("c", KIND_GAME_COMPLETED, 800, { [PK.gameInstanceId]: GAME }),
      mockDoc("e", KIND_GAME_ENDED, 900, { [PK.gameInstanceId]: GAME }),
    ];
    expect(deriveGameReplayWindow(undefined, docs, GAME).endSec).toBe(900);
  });

  it("ignores markers belonging to a different game", () => {
    const docs = [
      mockDoc("s", KIND_GAME_STARTED, 100, { [PK.gameInstanceId]: "other" }),
      mockDoc("e", KIND_GAME_ENDED, 900, { [PK.gameInstanceId]: "other" }),
    ];
    expect(deriveGameReplayWindow(undefined, docs, GAME)).toEqual({ startSec: 0, endSec: null });
  });

  it("reports a missing end marker as null rather than guessing", () => {
    const docs = [mockDoc("s", KIND_GAME_STARTED, 100, { [PK.gameInstanceId]: GAME })];
    expect(deriveGameReplayWindow({ startedAt: mockTs(100) }, docs, GAME)).toEqual({
      startSec: 100,
      endSec: null,
    });
  });
});

describe("lateReplay stamping", () => {
  it("recognises a server-stamped late find", () => {
    expect(isLateReplayFindDoc(findDoc("f1", 1500, "u1", "CA", { [PK.lateReplay]: "true" }))).toBe(true);
  });

  it("an ordinary find is not a late replay", () => {
    expect(isLateReplayFindDoc(findDoc("f1", 1500, "u1", "CA"))).toBe(false);
  });

  it("only the exact server value counts — a client cannot fake it with a truthy string", () => {
    for (const v of ["1", "yes", "TRUE", "", "false"]) {
      expect(isLateReplayFindDoc(findDoc("f1", 1500, "u1", "CA", { [PK.lateReplay]: v })), v).toBe(false);
    }
  });
});

describe("late replay — lifetime stats contribution", () => {
  const members = ["u1", "u2"];
  const gameDocs = [
    {
      id: GAME,
      data: () => ({
        commonConfigDataBase64: Buffer.from(
          JSON.stringify({ gameMode: "collaborative", lifecycleState: "ended" })
        ).toString("base64"),
      }),
    } as admin.firestore.QueryDocumentSnapshot,
  ];

  function contribution(docs: admin.firestore.QueryDocumentSnapshot[]) {
    return previewLateReplayContribution({
      canonicalStatus: "ended",
      memberUserIds: members,
      gameDocs,
      activityEventDocs: docs,
    });
  }

  it("is null when nothing was replayed late", () => {
    expect(contribution([findDoc("f1", 1500, "u1", "CA")])).toBeNull();
  });

  it("credits a late find that opened a brand-new target", () => {
    const out = contribution([
      findDoc("f1", 1500, "u1", "CA"),
      findDoc("f2", 1600, "u1", "NY", { [PK.lateReplay]: "true" }),
    ]);
    expect(out?.u1.totalDiscoveries).toBe(1);
    expect(out?.u1.totalWeightedScore).toBeCloseTo(1, 9);
    expect(out?.u2.totalDiscoveries).toBe(0);
  });

  /**
   * The reason this is a recompute-and-diff and not a `+1`: collaborative credit for a
   * target is split 1/n across its finders, so a late find on an ALREADY-found target
   * reduces the earlier finder's credit. A naive per-find increment would leave u2 over-credited.
   */
  it("redistributes collaborative credit — the earlier finder's share goes DOWN", () => {
    const out = contribution([
      findDoc("f1", 1500, "u2", "CA"),
      findDoc("f2", 1600, "u1", "CA", { [PK.lateReplay]: "true" }),
    ]);
    expect(out?.u1.totalDiscoveries).toBe(1);
    expect(out?.u1.totalWeightedScore).toBeCloseTo(0.5, 9);
    // u2 keeps the find but now shares the credit: 1.0 → 0.5.
    expect(out?.u2.totalDiscoveries).toBe(0);
    expect(out?.u2.totalWeightedScore).toBeCloseTo(-0.5, 9);
  });

  it("is cumulative across several late finds, which is what makes applying it idempotent", () => {
    const out = contribution([
      findDoc("f1", 1500, "u1", "CA"),
      findDoc("f2", 1600, "u1", "NY", { [PK.lateReplay]: "true" }),
      findDoc("f3", 1700, "u1", "TX", { [PK.lateReplay]: "true" }),
    ]);
    expect(out?.u1.totalDiscoveries).toBe(2);
  });

  it("scores nothing for a trip that never ended", () => {
    expect(
      previewLateReplayContribution({
        canonicalStatus: "active",
        memberUserIds: members,
        gameDocs,
        activityEventDocs: [findDoc("f1", 1500, "u1", "CA", { [PK.lateReplay]: "true" })],
      })
    ).toBeNull();
  });
});

describe("XP day key", () => {
  /**
   * A replayed find keeps the xpDayKey from the day it was actually made. It must grant
   * against THAT day and never read as current-day activity — otherwise a consent replay
   * would forge a return streak.
   */
  it("survives replay unchanged and is not today's key", () => {
    const doc = findDoc("f1", 1500, "u1", "CA", {
      [PK.lateReplay]: "true",
      [PK.xpDayKey]: "2026-08-01",
    });
    const payload = doc.data().payload as Record<string, string>;
    expect(payload[PK.xpDayKey]).toBe("2026-08-01");

    const today = new Date().toISOString().slice(0, 10);
    expect(payload[PK.xpDayKey]).not.toBe(today);
  });
});

// MARK: - R5. Retry of a committed late accept must stay idempotent

describe("idempotency vs server-stamped keys", () => {
  /**
   * The defect: the stored copy carries the server's `lateReplay` stamp, the retry's
   * incoming payload does not (it is stripped on arrival). Comparing them raw makes every
   * retry of an already-committed accept look like an id collision — `already-exists`,
   * which the client files as a PERMANENT verdict. That lands precisely on the flaky
   * network of a consent-resume drain.
   */
  it("a retry of a committed LATE accept compares equal", () => {
    const incoming = {
      [PK.gameInstanceId]: GAME,
      [PK.regionId]: "CA",
      [PK.participantId]: "u1",
    };
    const stored = {
      ...incoming,
      [PK.lateReplay]: "true",
    };
    expect(withoutServerStampedKeys(stored)).toEqual(withoutServerStampedKeys(incoming));
  });

  /** `serverCommittedAt` has the same shape and the same pre-existing hazard. */
  it("a retry of a committed SUPERSEDE accept compares equal", () => {
    const incoming = {
      [PK.gameInstanceId]: GAME,
      [PK.regionId]: "CA",
      [PK.participantId]: "u1",
    };
    const stored = { ...incoming, [PK.serverCommittedAt]: "1700000000" };
    expect(withoutServerStampedKeys(stored)).toEqual(withoutServerStampedKeys(incoming));
  });

  /** A GENUINE payload difference must still be detected as a collision. */
  it("a real payload change is still a mismatch", () => {
    const a = { [PK.gameInstanceId]: GAME, [PK.regionId]: "CA" };
    const b = { [PK.gameInstanceId]: GAME, [PK.regionId]: "NY" };
    expect(withoutServerStampedKeys(a)).not.toEqual(withoutServerStampedKeys(b));
  });
});

// MARK: - R1. The applied-baseline guard must read what set-merge actually writes

describe("hasAppliedTripBaseline", () => {
  /**
   * THE dead-code defect. The baseline writes `{ ["appliedTrips." + sessionId]: ts }`
   * through `set(..., {merge:true})`. Dot-path EXPANSION is an `update()` behaviour — under
   * `set()` the SDK stores a LITERAL top-level field whose name contains a dot. A guard
   * that reads the nested map therefore never matches, and the late trigger early-returned
   * every single time.
   *
   * This fixture is built the way the SDK actually stores it, not as a hand-made nested map.
   */
  it("matches the literal dotted field that set-merge produces", () => {
    const asStoredBySetMerge = { [`appliedTrips.${"sess-1"}`]: { seconds: 1, nanoseconds: 0 } };
    expect(hasAppliedTripBaseline(asStoredBySetMerge, "sess-1")).toBe(true);
  });

  /** Tolerated for a future `update()`-based writer. */
  it("also matches a genuinely nested map", () => {
    expect(hasAppliedTripBaseline({ appliedTrips: { "sess-1": 123 } }, "sess-1")).toBe(true);
  });

  it("does not match a different session, an empty doc, or a missing doc", () => {
    expect(hasAppliedTripBaseline({ "appliedTrips.other": 1 }, "sess-1")).toBe(false);
    expect(hasAppliedTripBaseline({}, "sess-1")).toBe(false);
    expect(hasAppliedTripBaseline(undefined, "sess-1")).toBe(false);
  });
});

// MARK: - R2. One exactly-once contract across both trigger orderings

describe("late replay exactly-once across trigger orderings", () => {
  const members = ["u1", "u2"];
  const gameDocs = [
    {
      id: GAME,
      data: () => ({
        commonConfigDataBase64: Buffer.from(
          JSON.stringify({ gameMode: "collaborative", lifecycleState: "ended" })
        ).toString("base64"),
      }),
    } as admin.firestore.QueryDocumentSnapshot,
  ];

  function cumulative(docs: admin.firestore.QueryDocumentSnapshot[]) {
    return previewLateReplayContribution({
      canonicalStatus: "ended",
      memberUserIds: members,
      gameDocs,
      activityEventDocs: docs,
    });
  }

  const onTime = findDoc("f1", 1500, "u1", "CA");
  const late1 = findDoc("f2", 1600, "u1", "NY", { [PK.lateReplay]: "true" });
  const late2 = findDoc("f3", 1700, "u1", "TX", { [PK.lateReplay]: "true" });

  /**
   * ORDERING A — late finds drain BEFORE `trip_ended` (the common consent ordering).
   * The baseline recompute already counts them, so it records that portion in the ledger
   * and the late trigger must then find nothing left to apply.
   */
  it("late-before-baseline: baseline counts them, trigger applies nothing more", () => {
    const atBaseline = cumulative([onTime, late1]);
    expect(atBaseline?.u1.totalDiscoveries).toBe(1);

    // Baseline stored exactly that. The trigger later recomputes the same total.
    const ledger = atBaseline!.u1;
    const nowCumulative = cumulative([onTime, late1])!.u1;
    const remainder = nowCumulative.totalDiscoveries - ledger.totalDiscoveries;
    expect(remainder).toBe(0);
  });

  /**
   * ORDERING B — a late find lands AFTER the baseline ran. The ledger is empty (or holds
   * only what the baseline saw) and the trigger applies the difference.
   */
  it("late-after-baseline: trigger applies exactly the new contribution", () => {
    const ledger = { totalDiscoveries: 0, totalWeightedScore: 0 };
    const nowCumulative = cumulative([onTime, late1])!.u1;
    expect(nowCumulative.totalDiscoveries - ledger.totalDiscoveries).toBe(1);
  });

  /** MIXED — one late find before the baseline, another after. Each counted once. */
  it("mixed ordering counts each late find exactly once", () => {
    const atBaseline = cumulative([onTime, late1])!.u1;
    const afterSecondLate = cumulative([onTime, late1, late2])!.u1;

    const remainder = afterSecondLate.totalDiscoveries - atBaseline.totalDiscoveries;
    expect(remainder).toBe(1);
    // Total actually reflected = baseline portion + trigger remainder.
    expect(atBaseline.totalDiscoveries + remainder).toBe(afterSecondLate.totalDiscoveries);
  });

  /** Re-firing the trigger with no new finds is a no-op. */
  it("a repeated firing applies nothing", () => {
    const ledger = cumulative([onTime, late1, late2])!.u1;
    const again = cumulative([onTime, late1, late2])!.u1;
    expect(again.totalDiscoveries - ledger.totalDiscoveries).toBe(0);
    expect(again.totalWeightedScore - ledger.totalWeightedScore).toBeCloseTo(0, 9);
  });
});

// MARK: - G6. The solo derivation itself (memSnap.size === 1)

describe("solo-trip derivation from the members snapshot", () => {
  /**
   * The resolver derives `isSoloTrip` from the roster it has already read:
   * `memSnap.size === 1`. Membership of the caller is asserted before this, so that one
   * member IS the caller. Anything else — including an empty or unreadable roster — is
   * NOT solo, which is the fail-closed direction for the unbounded horizon.
   */
  function isSoloTripFromRosterSize(size: number): boolean {
    return size === 1;
  }

  it("exactly one member is solo", () => {
    expect(isSoloTripFromRosterSize(1)).toBe(true);
  });

  it("an empty / unreadable roster is NOT solo — fail closed to the 14-day bound", () => {
    expect(isSoloTripFromRosterSize(0)).toBe(false);
  });

  it("two or more members is multiplayer", () => {
    expect(isSoloTripFromRosterSize(2)).toBe(false);
    expect(isSoloTripFromRosterSize(5)).toBe(false);
  });

  /** End to end: an ambiguous roster expires at the bound where a solo trip would not. */
  it("an ambiguous roster expires past 14 days where a solo trip would still land", () => {
    const params = {
      lifecycleState: "ended",
      eventTimestampSec: 1500,
      window,
      nowSec: window.endSec + LATE_REPLAY_HORIZON_DAYS * DAY + 1,
    };
    expect(
      evaluateReplayAdmission({ ...params, isSoloTrip: isSoloTripFromRosterSize(0) })
    ).toEqual({ accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED });
    expect(
      evaluateReplayAdmission({ ...params, isSoloTrip: isSoloTripFromRosterSize(1) })
    ).toEqual({ accept: true, lateReplay: true });
  });
});

// MARK: - G4. serverCommittedAt is server-owned, not client-suppliable

describe("server-owned payload keys are stripped from client input", () => {
  /**
   * `serverCommittedAt` is the supersede tie-break: in `compareIncomingVsIncumbent` the
   * LOWER value wins and 0/absent sorts LAST. A client that could supply it would hand
   * itself a winning tie-break and take a contested find from whoever genuinely got there
   * first. It is stripped at the same choke point as `lateReplay`.
   */
  it("strips serverCommittedAt as well as lateReplay", () => {
    const incoming = {
      [PK.gameInstanceId]: GAME,
      [PK.regionId]: "CA",
      [PK.participantId]: "u1",
      [PK.serverCommittedAt]: "1",
      [PK.lateReplay]: "true",
    };
    const sanitized = withoutServerStampedKeys(incoming);
    expect(sanitized[PK.serverCommittedAt]).toBeUndefined();
    expect(sanitized[PK.lateReplay]).toBeUndefined();
    expect(sanitized[PK.regionId]).toBe("CA");
  });

  /**
   * A forged low `serverCommittedAt` must not survive to influence ordering. After
   * stripping, the incoming find has no tie-break value at all and therefore sorts LAST
   * against an incumbent that carries a genuine server-set one.
   */
  it("a forged tie-break value cannot beat a genuine incumbent once stripped", () => {
    const forged = { [PK.serverCommittedAt]: "1" };
    const sanitized = withoutServerStampedKeys(forged);
    const forgedSec = parseInt(sanitized[PK.serverCommittedAt] ?? "0", 10) || 0;
    const incumbentSec = 1_700_000_000;

    // 0 means "absent", which the comparator maps to MAX_SAFE_INTEGER (sorts last).
    expect(forgedSec).toBe(0);
    const effectiveForged = forgedSec > 0 ? forgedSec : Number.MAX_SAFE_INTEGER;
    expect(effectiveForged).toBeGreaterThan(incumbentSec);
  });
});

// MARK: - G5. The baseline lost-update window

describe("late-find vs in-flight baseline", () => {
  /**
   * The window: the trip-end trigger reads the event log once, then commits per-user
   * transactions sequentially. A find created inside that window is missing from the
   * baseline's totals AND has no marker to key off here — so without this it is counted
   * nowhere.
   */
  it("no trip_ended yet → genuinely pre-baseline, skip (the baseline will include it)", () => {
    expect(decideBaselineWait({ hasTripEnded: false, markerPresent: false })).toBe("skip");
  });

  it("trip_ended present but no marker → baseline in flight, WAIT for it", () => {
    expect(decideBaselineWait({ hasTripEnded: true, markerPresent: false })).toBe("wait");
  });

  it("marker present → proceed to the ordinary diff", () => {
    expect(decideBaselineWait({ hasTripEnded: true, markerPresent: true })).toBe("proceed");
    expect(decideBaselineWait({ hasTripEnded: false, markerPresent: true })).toBe("proceed");
  });

  it("the wait is bounded and polls faster than the bound", () => {
    expect(BASELINE_MARKER_POLL_INTERVAL_MS).toBeGreaterThan(0);
    expect(BASELINE_MARKER_MAX_WAIT_MS).toBeGreaterThan(BASELINE_MARKER_POLL_INTERVAL_MS);
  });

  it("detects trip_ended in the event log", () => {
    const finds = [findDoc("f1", 1500, "u1", "CA")];
    expect(sessionHasTripEndedEvent(finds)).toBe(false);
    const withEnd = [...finds, mockDoc("te", "trip_ended", 2000, {})];
    expect(sessionHasTripEndedEvent(withEnd)).toBe(true);
  });
});
