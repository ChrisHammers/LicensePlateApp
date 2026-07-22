import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND, PK } from "./gameplayEventResolver";
import {
  isFamilyOnlyTrip,
  isEntireFamilyTrip,
  classifySocialTrip,
  previewTripEndedAggregates,
  KIND_TRIP_ENDED,
  parseCommonConfigGameMode,
} from "./publicLifetimeStatsCore";

function mockTs(seconds: number): admin.firestore.Timestamp {
  return { seconds, nanoseconds: 0 } as admin.firestore.Timestamp;
}

function mockEventDoc(
  id: string,
  kind: string,
  seconds: number,
  payload: Record<string, string>
): admin.firestore.QueryDocumentSnapshot {
  const ts = mockTs(seconds);
  return {
    id,
    data: () => ({
      kind,
      timestamp: ts,
      actorId: payload.participantId || null,
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

describe("publicLifetimeStatsCore", () => {
  const gid = "550e8400-e29b-41d4-a716-446655440000";

  it("KIND_TRIP_ENDED matches iOS TripActivityEventKind.tripEnded", () => {
    expect(KIND_TRIP_ENDED).toBe("trip_ended");
  });

  it("isFamilyOnlyTrip matches empty family as false", () => {
    expect(isFamilyOnlyTrip(["a", "b"], new Set())).toBe(false);
    expect(isFamilyOnlyTrip([], new Set(["a"]))).toBe(false);
  });

  it("isFamilyOnlyTrip false for solo even when in family", () => {
    expect(isFamilyOnlyTrip(["a"], new Set(["a", "b"]))).toBe(false);
  });

  it("isFamilyOnlyTrip true when roster subset of family with 2+", () => {
    expect(isFamilyOnlyTrip(["a", "b"], new Set(["a", "b", "c"]))).toBe(true);
  });

  it("isEntireFamilyTrip requires full family on roster", () => {
    expect(isEntireFamilyTrip(["a", "b"], new Set(["a", "b"]))).toBe(true);
    expect(isEntireFamilyTrip(["a", "b"], new Set(["a", "b", "c"]))).toBe(false);
    expect(isEntireFamilyTrip(["a", "b", "x"], new Set(["a", "b"]))).toBe(true);
    expect(isEntireFamilyTrip(["a"], new Set(["a"]))).toBe(false);
  });

  it("classifySocialTrip family wins for dual peers", () => {
    expect(classifySocialTrip(["me", "sis"], "me", new Set(["me", "sis"]), new Set(["sis"]))).toBe(
      "familyOnly"
    );
  });

  it("classifySocialTrip friendsOnly and mixed", () => {
    expect(classifySocialTrip(["me", "pal"], "me", new Set(["me"]), new Set(["pal"]))).toBe("friendsOnly");
    expect(
      classifySocialTrip(["me", "sis", "pal"], "me", new Set(["me", "sis"]), new Set(["pal", "sis"]))
    ).toBe("mixed");
  });

  it("preview returns null for cancelled session", () => {
    const p = previewTripEndedAggregates({
      canonicalStatus: "cancelled",
      memberUserIds: ["u1"],
      gameDocs: [],
      activityEventDocs: [],
      familyMemberIdsByUser: { u1: new Set() },
      friendUserIdsByUser: { u1: new Set() },
    });
    expect(p).toBeNull();
  });

  it("preview applies one trip for two members with competitive credit", () => {
    const region = "US-CA";
    const events = [
      mockEventDoc("e1", KIND_REGION_FOUND, 10, {
        [PK.gameInstanceId]: gid,
        [PK.regionId]: region,
        [PK.participantId]: "u1",
        [PK.inputMethod]: "list",
      }),
    ];
    const preview = previewTripEndedAggregates({
      canonicalStatus: "ended",
      memberUserIds: ["u1", "u2"],
      gameDocs: [mockGameDoc(gid, "competitive")],
      activityEventDocs: events,
      familyMemberIdsByUser: { u1: new Set(["u1", "u2"]), u2: new Set(["u1", "u2"]) },
      friendUserIdsByUser: { u1: new Set(), u2: new Set() },
    });
    expect(preview).not.toBeNull();
    expect(preview!.perUser.u1.totalCompletedTrips).toBe(1);
    expect(preview!.perUser.u1.totalDiscoveries).toBe(1);
    expect(preview!.perUser.u1.totalWeightedScore).toBe(1);
    expect(preview!.perUser.u2.totalDiscoveries).toBe(0);
    expect(preview!.perUser.u1.familyOnlyTripsCount).toBe(1);
    expect(preview!.perUser.u2.familyOnlyTripsCount).toBe(1);
    expect(preview!.perUser.u1.entireFamilyTripsCount).toBe(1);
    expect(preview!.perUser.u1.friendsOnlyTripsCount).toBe(0);
    expect(preview!.perUser.u1.mixedFriendsFamilyTripsCount).toBe(0);
  });

  it("parseCommonConfigGameMode defaults collaborative on bad base64", () => {
    expect(parseCommonConfigGameMode(undefined)).toBe("collaborative");
    expect(parseCommonConfigGameMode("@@@")).toBe("collaborative");
  });
});
