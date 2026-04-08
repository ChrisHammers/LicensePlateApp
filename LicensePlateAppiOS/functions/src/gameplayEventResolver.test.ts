import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
  evaluateDiscoverySubmission,
  replayDiscoveriesFromDocs,
  KIND_REGION_FOUND,
  KIND_REGION_REMOVED,
  KIND_DISCOVERY_REJECTED,
  KIND_PARTICIPANT_INVITED,
  KIND_PARTICIPANT_JOINED,
  REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP,
} from "./gameplayEventResolver";

/** Plain shape compatible with replay (avoids firebase-admin init in vitest). */
function mockTs(seconds: number): admin.firestore.Timestamp {
  return { seconds, nanoseconds: 0 } as admin.firestore.Timestamp;
}

function mockDoc(
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

describe("evaluateDiscoverySubmission", () => {
  const existingOther = [
    {
      id: "a",
      gameInstanceId: "g1",
      participantId: "u1",
      targetId: "r1",
      discoveredAt: mockTs(100),
      inputMethod: "list",
      serverCommittedAtSec: 0,
    },
  ];

  it("empty target is new_credit", () => {
    expect(evaluateDiscoverySubmission("competitive", "multiplayer", [], "u2")).toBe("new_credit");
  });

  it("same participant is personal_duplicate", () => {
    expect(evaluateDiscoverySubmission("competitive", "multiplayer", existingOther, "u1")).toBe("personal_duplicate");
  });

  it("competitive other participant is rejected_duplicate", () => {
    expect(evaluateDiscoverySubmission("competitive", "multiplayer", existingOther, "u2")).toBe("rejected_duplicate");
  });

  it("collaborative other participant is shared_duplicate", () => {
    expect(evaluateDiscoverySubmission("collaborative", "multiplayer", existingOther, "u2")).toBe("shared_duplicate");
  });

  it("solo other participant is rejected_invalid_participant", () => {
    expect(evaluateDiscoverySubmission("competitive", "solo", existingOther, "u2")).toBe("rejected_invalid_participant");
  });
});

describe("trip lifecycle event kind constants", () => {
  it("uses stable strings for server-only invite/join activity kinds", () => {
    expect(KIND_PARTICIPANT_INVITED).toBe("participant_invited");
    expect(KIND_PARTICIPANT_JOINED).toBe("participant_joined");
  });
});

describe("replayDiscoveriesFromDocs", () => {
  const gid = "550e8400-e29b-41d4-a716-446655440000";

  it("tracks two collaborative finders on same target", () => {
    const docs = [
      mockDoc("e1", KIND_REGION_FOUND, 1, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u1",
        inputMethod: "list",
      }),
      mockDoc("e2", KIND_REGION_FOUND, 2, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u2",
        inputMethod: "list",
      }),
    ];
    const buckets = replayDiscoveriesFromDocs(docs, gid);
    const key = `${gid}|CA`;
    expect(buckets.get(key)?.length).toBe(2);
  });

  it("partial region_removed removes one discovery", () => {
    const docs = [
      mockDoc("e1", KIND_REGION_FOUND, 1, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u1",
        inputMethod: "list",
      }),
      mockDoc("e2", KIND_REGION_FOUND, 2, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u2",
        inputMethod: "list",
      }),
      mockDoc("rm", KIND_REGION_REMOVED, 3, {
        gameInstanceId: gid,
        regionId: "CA",
        removedDiscoveryEventId: "e2",
      }),
    ];
    const buckets = replayDiscoveriesFromDocs(docs, gid);
    const key = `${gid}|CA`;
    expect(buckets.get(key)?.map((d) => d.id)).toEqual(["e1"]);
  });

  it("supersede rejection removes later region_found by id (timestamp-first)", () => {
    const docs = [
      mockDoc("early", KIND_REGION_FOUND, 100, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u1",
        inputMethod: "list",
        serverCommittedAt: "2000",
      }),
      mockDoc("late", KIND_REGION_FOUND, 200, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u2",
        inputMethod: "list",
        serverCommittedAt: "1000",
      }),
      mockDoc("suprej", KIND_DISCOVERY_REJECTED, 300, {
        gameInstanceId: gid,
        regionId: "CA",
        participantId: "u2",
        rejectionReason: REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP,
        supersededRegionFoundEventId: "late",
        firstFinderParticipantId: "u1",
        firstFinderEventId: "early",
        firstFinderDiscoveredAt: "100",
        clientAttemptEventId: "late",
      }),
    ];
    const buckets = replayDiscoveriesFromDocs(docs, gid);
    const key = `${gid}|CA`;
    expect(buckets.get(key)?.length).toBe(1);
    expect(buckets.get(key)?.[0]?.participantId).toBe("u1");
  });
});
