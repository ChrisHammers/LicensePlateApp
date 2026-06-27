import { describe, expect, it } from "vitest";
import { achievementCatalogEntry } from "./achievementCatalogCore";
import {
  AchievementEvaluationContext,
  evaluateAchievement,
} from "./achievementProgressCore";
import { achievementUnlockScopeKey } from "./progressionCore";

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

describe("achievementProgressCore", () => {
  it("first_win unlocks from everCompetitiveFirstPlace", () => {
    const entry = achievementCatalogEntry("first_win");
    expect(entry).toBeTruthy();
    const ctx = baseContext();
    ctx.progression.everCompetitiveFirstPlace = true;
    const result = evaluateAchievement(entry!, ctx);
    expect(result.unlocked).toBe(true);
    expect(result.progress).toBe(1);
  });

  it("trips_10 unlocks from completed trips", () => {
    const entry = achievementCatalogEntry("trips_10");
    expect(entry).toBeTruthy();
    const ctx = baseContext();
    ctx.lifetimeStats = { totalCompletedTrips: 10, totalDiscoveries: 0 };
    const result = evaluateAchievement(entry!, ctx);
    expect(result.unlocked).toBe(true);
    expect(result.progress).toBe(10);
  });

  it("coast_to_coast requires 63 regions", () => {
    const entry = achievementCatalogEntry("coast_to_coast");
    expect(entry).toBeTruthy();
    const short = baseContext();
    short.progression.acceptedRegionFindCount = 62;
    expect(evaluateAchievement(entry!, short).unlocked).toBe(false);
    const complete = baseContext();
    complete.progression.acceptedRegionFindCount = 63;
    expect(evaluateAchievement(entry!, complete).unlocked).toBe(true);
  });

  it("hidden deferred evaluators stay locked", () => {
    const streak = achievementCatalogEntry("streak_5");
    const flawless = achievementCatalogEntry("flawless");
    expect(streak).toBeTruthy();
    expect(flawless).toBeTruthy();
    const ctx = baseContext();
    ctx.progression.everCompetitiveFirstPlace = true;
    ctx.progression.competitiveFirstPlaceFinishes = 200;
    ctx.lifetimeStats = { totalCompletedTrips: 100, totalDiscoveries: 5000 };
    ctx.isFamilyMember = true;
    ctx.isRoyale = true;
    ctx.isFounder = true;
    expect(evaluateAchievement(streak!, ctx).unlocked).toBe(false);
    expect(evaluateAchievement(flawless!, ctx).unlocked).toBe(false);
  });
});

describe("achievementUnlockScopeKey", () => {
  it("is stable per user and achievement", () => {
    expect(achievementUnlockScopeKey("uid1", "first_win")).toBe(
      "achievement_xp|v1|uid1|first_win"
    );
  });
});
