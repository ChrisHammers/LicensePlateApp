import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
  evaluateDiscoverySubmission,
  replayDiscoveriesFromDocs,
  KIND_REGION_FOUND,
  KIND_REGION_REMOVED,
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
});
