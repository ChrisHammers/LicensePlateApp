import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND, PK } from "./gameplayEventResolver";
import {
  baseRegionDiscoveryScopeKey,
  competitiveFirstPlaceParticipantIds,
  previewProgressionDeltasForActivityEvent,
  rankContributionsSwiftParity,
  XP_PER_ACCEPTED_REGION_FOUND,
  XP_PER_COMPETITIVE_FIRST_FINDER_BONUS,
  XP_PER_COMPETITIVE_FIRST_PLACE_FINISH,
  KIND_GAME_ENDED,
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

  it("region_found collaborative awards base XP and find count", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid, [PK.regionId]: "US-TX", [PK.participantId]: "u1", [PK.inputMethod]: "list" },
      memberUserIds: ["u1"],
      gameDocs: [mockGameDoc(gid, "collaborative")],
      activityEventDocs: [],
    });
    expect(d.u1).toEqual({
      totalXp: XP_PER_ACCEPTED_REGION_FOUND,
      acceptedRegionFindCount: 1,
      competitiveFirstPlaceFinishes: 0,
      awardEverCompetitiveFirstPlace: false,
    });
  });

  it("region_found competitive awards base plus first-finder bonus", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid, [PK.regionId]: "US-TX", [PK.participantId]: "u1", [PK.inputMethod]: "list" },
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: [],
    });
    expect(d.u1).toEqual({
      totalXp: XP_PER_ACCEPTED_REGION_FOUND + XP_PER_COMPETITIVE_FIRST_FINDER_BONUS,
      acceptedRegionFindCount: 1,
      competitiveFirstPlaceFinishes: 0,
      awardEverCompetitiveFirstPlace: false,
    });
  });

  it("region_found without game doc defaults to base collaborative XP", () => {
    const d = previewProgressionDeltasForActivityEvent({
      kind: KIND_REGION_FOUND,
      actorId: "u1",
      payload: { [PK.gameInstanceId]: gid, [PK.regionId]: "US-TX", [PK.participantId]: "u1", [PK.inputMethod]: "list" },
      memberUserIds: ["u1"],
      gameDocs: [],
      activityEventDocs: [],
    });
    expect(d.u1).toEqual({
      totalXp: XP_PER_ACCEPTED_REGION_FOUND,
      acceptedRegionFindCount: 1,
      competitiveFirstPlaceFinishes: 0,
      awardEverCompetitiveFirstPlace: false,
    });
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

  it("game_ended collaborative yields no deltas", () => {
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
    expect(Object.keys(d).length).toBe(0);
  });

  it("game_ended competitive awards first-place XP to sole leader only", () => {
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
    expect(d.u1?.totalXp).toBe(XP_PER_COMPETITIVE_FIRST_PLACE_FINISH);
    expect(d.u1?.awardEverCompetitiveFirstPlace).toBe(true);
    expect(d.u2).toBeUndefined();
  });

  it("game_ended competitive tie awards both rank-1", () => {
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
    expect(d.u1?.totalXp).toBe(XP_PER_COMPETITIVE_FIRST_PLACE_FINISH);
    expect(d.u2?.totalXp).toBe(XP_PER_COMPETITIVE_FIRST_PLACE_FINISH);
  });
});
