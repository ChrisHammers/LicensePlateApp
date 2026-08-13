import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND, KIND_DISCOVERY_REJECTED, PK, REJECTION_SERVER_LATE_COMPETITIVE } from "./gameplayEventResolver";
import {
  baseRegionDiscoveryScopeKey,
  competitiveFirstPlaceParticipantIds,
  previewProgressionDeltasForActivityEvent,
  rankContributionsSwiftParity,
  XP_AMOUNTS,
  XP_PER_ACCEPTED_REGION_FOUND,
  XP_PER_COMPETITIVE_FIRST_FINDER_BONUS,
  XP_PER_COMPETITIVE_FIRST_PLACE_FINISH,
  KIND_GAME_ENDED,
  KIND_GAME_COMPLETED,
  KIND_TRIP_ENDED,
} from "./progressionCore";

function mockTs(seconds: number): admin.firestore.Timestamp {
  return { seconds, nanoseconds: 0 } as admin.firestore.Timestamp;
}

function mockEventDoc(
  id: string,
  kind: string,
  seconds: number,
  payload: Record<string, string>,
  actorId?: string | null
): admin.firestore.QueryDocumentSnapshot {
  const ts = mockTs(seconds);
  return {
    id,
    data: () => ({
      kind,
      timestamp: ts,
      actorId: actorId ?? payload[PK.participantId] ?? null,
      payload,
    }),
  } as admin.firestore.QueryDocumentSnapshot;
}

function mockGameDoc(id: string, gameMode: string): admin.firestore.QueryDocumentSnapshot {
  const commonConfig = Buffer.from(JSON.stringify({ gameMode }), "utf8").toString("base64");
  return {
    id,
    data: () => ({
      commonConfigDataBase64: commonConfig,
      teamsDataBase64: null,
    }),
  } as admin.firestore.QueryDocumentSnapshot;
}

describe("progressionCore", () => {
  const gid = "550e8400-e29b-41d4-a716-446655440001";

  it("rankContributionsSwiftParity ties share rank 1", () => {
    const ranked = rankContributionsSwiftParity([
      { participantId: "a", discoveryCount: 2, weightedScore: 10, firstFindCount: 1 },
      { participantId: "b", discoveryCount: 1, weightedScore: 10, firstFindCount: 2 },
      { participantId: "c", discoveryCount: 3, weightedScore: 8, firstFindCount: 0 },
    ]);
    expect(ranked.filter((r) => r.rank === 1).map((r) => r.participantId).sort()).toEqual(["a", "b"]);
  });

  it("competitiveFirstPlaceParticipantIds returns all rank-1", () => {
    const ids = competitiveFirstPlaceParticipantIds([
      { participantId: "x", discoveryCount: 0, weightedScore: 5, firstFindCount: 0 },
      { participantId: "y", discoveryCount: 0, weightedScore: 5, firstFindCount: 0 },
    ]);
    expect(ids.sort()).toEqual(["x", "y"]);
  });

  it("region_found collaborative awards base + lifetime unique", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid, [PK.regionId]: "US-TX", [PK.participantId]: "u1", [PK.inputMethod]: "list" },
      memberUserIds: ["u1"],
      gameDocs: [mockGameDoc(gid, "collaborative")],
      activityEventDocs: [],
    });
    expect(d.u1).toEqual({
      totalXp: XP_AMOUNTS.baseDiscoveryXp + XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp,
      acceptedRegionFindCount: 1,
      competitiveFirstPlaceFinishes: 0,
      awardEverCompetitiveFirstPlace: false,
    });
  });

  it("region_found competitive awards base + first-finder + unique", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid, [PK.regionId]: "US-TX", [PK.participantId]: "u1", [PK.inputMethod]: "list" },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [],
    });
    expect(d.u1).toEqual({
      totalXp:
        XP_PER_ACCEPTED_REGION_FOUND +
        XP_PER_COMPETITIVE_FIRST_FINDER_BONUS +
        XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp,
      acceptedRegionFindCount: 1,
      competitiveFirstPlaceFinishes: 0,
      awardEverCompetitiveFirstPlace: false,
    });
  });

  it("region_found with xpDayKey adds first-of-day", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-TX",
        [PK.participantId]: "u1",
        xpDayKey: "2026-08-06",
      },
      memberUserIds: ["u1"],
      gameDocs: [mockGameDoc(gid, "collaborative")],
      activityEventDocs: [],
    });
    expect(d.u1?.totalXp).toBe(
      XP_AMOUNTS.baseDiscoveryXp +
        XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp +
        XP_AMOUNTS.firstFindOfDayBonusXp
    );
  });

  it("late discovery_rejected awards base + unique without first-finder", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_DISCOVERY_REJECTED,
      actorId: "u2",
      payload: {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-TX",
        [PK.participantId]: "u2",
        [PK.rejectionReason]: REJECTION_SERVER_LATE_COMPETITIVE,
      },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [],
    });
    expect(d.u2?.totalXp).toBe(
      XP_AMOUNTS.baseDiscoveryXp + XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp
    );
    expect(d.u2?.acceptedRegionFindCount).toBe(1);
  });

  it("builds scoped key with user/session/game/region", () => {
    const key = baseRegionDiscoveryScopeKey({
      userId: "u1",
      sessionId: "trip-1",
      payload: {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-TX",
      },
    });
    expect(key).toBe(`xp_scope|v1|u1|trip-1|${gid}|US-TX|base_region_discovery`);
  });

  it("game_ended collaborative awards game-ended XP to all members", () => {
    const region = "US-CA";
    const events = [
      mockEventDoc("e1", KIND_REGION_FOUND, 1, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: region,
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
    ];
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "collaborative")],
      activityEventDocs: events,
    });
    expect(d.u1?.totalXp).toBe(XP_AMOUNTS.gameEndedBonusXp);
    expect(d.u2?.totalXp).toBe(XP_AMOUNTS.gameEndedBonusXp);
    expect(d.u1?.competitiveFirstPlaceFinishes).toBe(0);
  });

  it("game_ended competitive awards game-ended + place XP", () => {
    const events = [
      mockEventDoc("e1", KIND_REGION_FOUND, 1, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-CA",
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
      mockEventDoc("e2", KIND_REGION_FOUND, 2, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-NV",
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
      mockEventDoc("e3", KIND_REGION_FOUND, 3, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-OR",
        [PK.participantId]: "u2",
        [PK.inputMethod]: "list",
      }),
    ];
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: events,
    });
    expect(d.u1?.competitiveFirstPlaceFinishes).toBe(1);
    expect(d.u1?.totalXp).toBe(
      XP_AMOUNTS.gameEndedBonusXp + XP_PER_COMPETITIVE_FIRST_PLACE_FINISH
    );
    expect(d.u1?.awardEverCompetitiveFirstPlace).toBe(true);
    expect(d.u2?.totalXp).toBe(
      XP_AMOUNTS.gameEndedBonusXp + XP_AMOUNTS.competitiveSecondPlaceFinishBonusXp
    );
    expect(d.u2?.competitiveFirstPlaceFinishes).toBe(0);
  });

  it("game_ended competitive tie awards both rank-1 place XP", () => {
    const events = [
      mockEventDoc("e1", KIND_REGION_FOUND, 1, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-CA",
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
      mockEventDoc("e2", KIND_REGION_FOUND, 2, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-NV",
        [PK.participantId]: "u2",
        [PK.inputMethod]: "list",
      }),
    ];
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: events,
    });
    expect(d.u1?.competitiveFirstPlaceFinishes).toBe(1);
    expect(d.u2?.competitiveFirstPlaceFinishes).toBe(1);
    const expected =
      XP_AMOUNTS.gameEndedBonusXp + XP_PER_COMPETITIVE_FIRST_PLACE_FINISH;
    expect(d.u1?.totalXp).toBe(expected);
    expect(d.u2?.totalXp).toBe(expected);
  });

  it("game_completed awards full-clear XP to all members", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_COMPLETED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "collaborative")],
      activityEventDocs: [],
    });
    expect(d.u1?.totalXp).toBe(XP_AMOUNTS.gameFullClearBonusXp);
    expect(d.u2?.totalXp).toBe(XP_AMOUNTS.gameFullClearBonusXp);
  });

  it("trip_ended stacks completion, participation, and competitive trip first", () => {
    const events = [
      mockEventDoc("e1", KIND_REGION_FOUND, 1, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: "US-CA",
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
    ];
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_TRIP_ENDED,
      actorId: "u1",
      payload: {},
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: events,
      sessionId: "trip-1",
    });
    expect(d.u1?.totalXp).toBe(
      XP_AMOUNTS.tripEndedBonusXp +
        XP_AMOUNTS.tripParticipationBonusXp +
        XP_AMOUNTS.tripCompetitiveFirstPlaceBonusXp
    );
    expect(d.u2?.totalXp).toBe(XP_AMOUNTS.tripEndedBonusXp);
  });
});

/**
 * FR-28h — server-side competitive OUTCOME freeze.
 *
 * A `region_found` the server accepted into an already-ended game is stamped
 * `lateReplay`. It still earns its own per-find XP, but it may not move a PLACEMENT:
 * competitive standings are frozen at trip end. Both server placement paths are covered
 * here — `game_ended` (per-game podium) and `trip_ended` (trip competitive first).
 */
describe("progressionCore — FR-28h late replay outcome freeze", () => {
  const gid = "550e8400-e29b-41d4-a716-446655440077";

  function findDoc(
    id: string,
    seconds: number,
    participantId: string,
    regionId: string,
    late = false
  ): admin.firestore.QueryDocumentSnapshot {
    const payload: Record<string, string> = {
      [PK.gameInstanceId]: gid,
      [PK.regionId]: regionId,
      [PK.participantId]: participantId,
      [PK.inputMethod]: "list",
    };
    if (late) payload[PK.lateReplay] = "true";
    return mockEventDoc(id, KIND_REGION_FOUND, seconds, payload, participantId);
  }

  /**
   * u2's late finds are timestamped EARLIER and outnumber u1's on-time find, so without
   * the freeze they would take the podium outright.
   */
  it("game_ended: placement ignores late replays and keeps the on-time winner", () => {
    const gameEndedPayload = { [PK.gameInstanceId]: gid };
    const onTimeOnly = [findDoc("f1", 1500, "u1", "US-CA")];
    const withLate = [
      findDoc("b1", 1100, "u2", "US-TX", true),
      findDoc("b2", 1200, "u2", "US-OR", true),
      findDoc("f1", 1500, "u1", "US-CA"),
    ];

    const before = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: gameEndedPayload,
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: onTimeOnly,
    });
    const after = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: gameEndedPayload,
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: withLate,
    });

    expect(before.u1.competitiveFirstPlaceFinishes).toBe(1);
    expect(after.u1.competitiveFirstPlaceFinishes).toBe(1);
    expect(after.u2.competitiveFirstPlaceFinishes).toBe(0);
    expect(after.u1.totalXp).toBe(before.u1.totalXp);
    expect(after.u2.totalXp).toBe(before.u2.totalXp);
  });

  /** R8: an all-late game has no frozen result — everyone would tie at zero. */
  it("game_ended: placement is suppressed when EVERY find was a late replay", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [
        findDoc("b1", 1100, "u2", "US-TX", true),
        findDoc("b2", 1200, "u1", "US-OR", true),
      ],
    });

    expect(d.u1.competitiveFirstPlaceFinishes).toBe(0);
    expect(d.u2.competitiveFirstPlaceFinishes).toBe(0);
    expect(d.u1.totalXp).toBe(XP_AMOUNTS.gameEndedBonusXp);
    expect(d.u2.totalXp).toBe(XP_AMOUNTS.gameEndedBonusXp);
  });

  it("trip_ended: trip competitive first ignores late replays", () => {
    const tripEndedPayload = {};
    const withLate = [
      findDoc("b1", 1100, "u2", "US-TX", true),
      findDoc("b2", 1200, "u2", "US-OR", true),
      findDoc("f1", 1500, "u1", "US-CA"),
    ];

    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_TRIP_ENDED,
      actorId: "u1",
      payload: tripEndedPayload,
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: withLate,
    });

    // u1 is the only outcome-eligible finder, so u1 takes trip first.
    expect(d.u1.totalXp).toBeGreaterThan(d.u2.totalXp);
    expect(d.u1.totalXp - d.u2.totalXp).toBe(XP_AMOUNTS.tripCompetitiveFirstPlaceBonusXp);
  });

  /** R8 at trip level: nothing eligible, so nobody takes trip competitive first. */
  it("trip_ended: trip competitive first is suppressed when every find was late", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_TRIP_ENDED,
      actorId: "u1",
      payload: {},
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [
        findDoc("b1", 1100, "u2", "US-TX", true),
        findDoc("b2", 1200, "u1", "US-OR", true),
      ],
    });

    expect(d.u1.totalXp).toBe(d.u2.totalXp);
  });

  /** ui-refactor-parity: with no late replays nothing about placement changes. */
  it("ordinary competitive play is entirely unaffected", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_GAME_ENDED,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [
        findDoc("b1", 1100, "u2", "US-TX"),
        findDoc("b2", 1200, "u2", "US-OR"),
        findDoc("f1", 1500, "u1", "US-CA"),
      ],
    });

    // u2 genuinely outscores u1 two to one and takes the podium.
    expect(d.u2.competitiveFirstPlaceFinishes).toBe(1);
    expect(d.u1.competitiveFirstPlaceFinishes).toBe(0);
  });
});
