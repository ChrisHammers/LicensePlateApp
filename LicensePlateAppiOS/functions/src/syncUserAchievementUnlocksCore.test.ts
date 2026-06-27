import { describe, expect, it } from "vitest";
import { achievementCatalogEntry } from "./achievementCatalogCore";
import {
  AchievementEvaluationContext,
  evaluateAchievement,
} from "./achievementProgressCore";
import {
  buildEvaluationContextFromFirestore,
  evaluateCandidateForSync,
  parseAchievementCandidates,
  planAchievementSyncTransaction,
} from "./syncUserAchievementUnlocksCore";

const baseContext = (): AchievementEvaluationContext => ({
  progression: {
    totalXp: 0,
    acceptedRegionFindCount: 0,
    competitiveFirstPlaceFinishes: 0,
    everCompetitiveFirstPlace: false,
  },
  lifetimeStats: null,
  isFamilyMember: false,
  isRoyale: false,
  isFounder: false,
});

describe("parseAchievementCandidates", () => {
  it("dedupes candidates and keeps max progress", () => {
    const parsed = parseAchievementCandidates(
      [
        { achievementId: "first_win", lastProgress: 1 },
        { achievementId: "first_win", lastProgress: 3 },
      ],
      20
    );
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.deduped.get("first_win")).toBe(3);
    }
  });

  it("ignores hidden and unknown ids", () => {
    const parsed = parseAchievementCandidates(
      [
        { achievementId: "streak_5", lastProgress: 5 },
        { achievementId: "not_real", lastProgress: 1 },
        { achievementId: "first_win", lastProgress: 1 },
      ],
      20
    );
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.deduped.has("streak_5")).toBe(false);
      expect(parsed.deduped.has("not_real")).toBe(false);
      expect(parsed.deduped.has("first_win")).toBe(true);
    }
  });

  it("returns too_many when over max", () => {
    const raw = Array.from({ length: 21 }, (_, i) => ({
      achievementId: "first_win",
      lastProgress: i,
    }));
    const parsed = parseAchievementCandidates(raw, 20);
    expect(parsed).toEqual({ ok: false, error: "too_many" });
  });
});

describe("buildEvaluationContextFromFirestore", () => {
  it("maps progression, lifetime, family, and entitlement hints", () => {
    const ctx = buildEvaluationContextFromFirestore(
      {
        totalXp: 500,
        acceptedRegionFindCount: 12,
        competitiveFirstPlaceFinishes: 2,
        everCompetitiveFirstPlace: true,
      },
      true,
      { totalCompletedTrips: 4, totalDiscoveries: 90 },
      { activeFamilyId: "fam1", wasEverInFamily: false },
      { isRoyale: true, isFounder: false }
    );
    expect(ctx.progression.totalXp).toBe(500);
    expect(ctx.lifetimeStats?.totalCompletedTrips).toBe(4);
    expect(ctx.isFamilyMember).toBe(true);
    expect(ctx.isRoyale).toBe(true);
    expect(ctx.isFounder).toBe(false);
  });

  it("uses wasEverInFamily when activeFamilyId is missing", () => {
    const ctx = buildEvaluationContextFromFirestore({}, false, undefined, { wasEverInFamily: 1 }, {});
    expect(ctx.isFamilyMember).toBe(true);
    expect(ctx.lifetimeStats).toBeNull();
  });
});

describe("evaluateCandidateForSync", () => {
  it("accepts valid unlock candidates", () => {
    const ctx = baseContext();
    ctx.progression.everCompetitiveFirstPlace = true;
    const result = evaluateCandidateForSync("first_win", 1, ctx, achievementCatalogEntry);
    expect(result.kind).toBe("accepted");
    if (result.kind === "accepted") {
      expect(result.progressToStore).toBe(1);
      expect(result.evaluation.unlocked).toBe(true);
    }
  });

  it("rejects candidates that fail server evaluation", () => {
    const result = evaluateCandidateForSync("first_win", 1, baseContext(), achievementCatalogEntry);
    expect(result).toEqual({ kind: "rejected" });
  });
});

describe("planAchievementSyncTransaction", () => {
  const entry = achievementCatalogEntry("first_win")!;

  it("plans a new record with xp increment", () => {
    const plan = planAchievementSyncTransaction({
      userId: "uid1",
      achievementId: "first_win",
      entry,
      progressToStore: 1,
      existingAchievementExists: false,
      existingAchievementData: undefined,
      progressionData: {},
    });
    expect(plan.outcome).toBe("recorded");
    expect(plan.achievementWrite.isNew).toBe(true);
    expect(plan.progressionWrite.shouldIncrementXp).toBe(true);
    expect(plan.progressionWrite.scopeKey).toBe("achievement_xp|v1|uid1|first_win");
  });

  it("plans already_synced without xp increment when achievement exists", () => {
    const plan = planAchievementSyncTransaction({
      userId: "uid1",
      achievementId: "first_win",
      entry,
      progressToStore: 2,
      existingAchievementExists: true,
      existingAchievementData: { lastProgress: 1 },
      progressionData: {},
    });
    expect(plan.outcome).toBe("already_synced");
    expect(plan.achievementWrite.lastProgress).toBe(2);
    expect(plan.progressionWrite.shouldIncrementXp).toBe(false);
  });

  it("does not increment xp when scope already applied", () => {
    const scopeKey = "achievement_xp|v1|uid1|first_win";
    const plan = planAchievementSyncTransaction({
      userId: "uid1",
      achievementId: "first_win",
      entry,
      progressToStore: 1,
      existingAchievementExists: false,
      existingAchievementData: undefined,
      progressionData: { appliedProgressionScopes: { [scopeKey]: true } },
    });
    expect(plan.outcome).toBe("recorded");
    expect(plan.progressionWrite.shouldIncrementXp).toBe(false);
  });

  it("matches evaluateAchievement before planning", () => {
    const ctx = baseContext();
    ctx.progression.everCompetitiveFirstPlace = true;
    const evaluation = evaluateAchievement(entry, ctx);
    expect(evaluation.unlocked).toBe(true);
  });
});
