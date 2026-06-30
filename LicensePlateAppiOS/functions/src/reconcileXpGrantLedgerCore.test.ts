import { describe, it, expect } from "vitest";
import {
  achievementGrantBackfillCandidates,
  computeLegacyUnledgeredDelta,
  legacyUnledgeredGrantWrite,
} from "./reconcileXpGrantLedgerCore";

describe("reconcileXpGrantLedgerCore", () => {
  it("backfills achievement grants from stored xpReward and applied scopes", () => {
    const candidates = achievementGrantBackfillCandidates({
      userId: "u1",
      appliedScopeKeys: new Set(["achievement_xp|v1|u1|first_win"]),
      achievementDocs: [{ id: "first_win", xpReward: 35 }],
      existingGrantIds: new Set(),
    });
    expect(candidates).toHaveLength(1);
    expect(candidates[0].amount).toBe(35);
    expect(candidates[0].grantId).toBe("achievement_xp|v1|u1|first_win");
  });

  it("skips achievements without applied scope or existing grant", () => {
    const candidates = achievementGrantBackfillCandidates({
      userId: "u1",
      appliedScopeKeys: new Set(["achievement_xp|v1|u1|first_win"]),
      achievementDocs: [{ id: "first_win", xpReward: 35 }],
      existingGrantIds: new Set(["achievement_xp|v1|u1|first_win"]),
    });
    expect(candidates).toHaveLength(0);
  });

  it("computes legacy orphan delta", () => {
    expect(computeLegacyUnledgeredDelta(1005, [270, 700])).toBe(35);
    expect(computeLegacyUnledgeredDelta(1005, [1005])).toBe(0);
  });

  it("builds legacy grant writes", () => {
    expect(legacyUnledgeredGrantWrite(35)?.amount).toBe(35);
    expect(legacyUnledgeredGrantWrite(0)).toBeNull();
  });
});
