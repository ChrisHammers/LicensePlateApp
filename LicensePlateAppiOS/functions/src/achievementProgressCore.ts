import { AchievementCatalogEntry } from "./achievementCatalogCore";

export type AchievementProgressionSnapshot = {
  totalXp: number;
  acceptedRegionFindCount: number;
  competitiveFirstPlaceFinishes: number;
  everCompetitiveFirstPlace: boolean;
};

export type AchievementLifetimeStatsSnapshot = {
  totalCompletedTrips: number;
  totalDiscoveries: number;
};

export type AchievementEvaluationContext = {
  progression: AchievementProgressionSnapshot;
  lifetimeStats: AchievementLifetimeStatsSnapshot | null;
  isFamilyMember: boolean;
  isRoyale: boolean;
  isFounder: boolean;
};

export type AchievementEvaluationResult = {
  progress: number;
  unlocked: boolean;
};

export function evaluateAchievement(
  entry: AchievementCatalogEntry,
  ctx: AchievementEvaluationContext
): AchievementEvaluationResult {
  switch (entry.evaluator) {
    case "ever_competitive_first_place": {
      const progress = ctx.progression.everCompetitiveFirstPlace ? 1 : 0;
      return { progress, unlocked: progress >= entry.goal };
    }
    case "accepted_region_count": {
      const count = Math.max(0, ctx.progression.acceptedRegionFindCount);
      return { progress: count, unlocked: count >= entry.goal };
    }
    case "total_discoveries": {
      const count = Math.max(0, ctx.lifetimeStats?.totalDiscoveries ?? 0);
      return { progress: count, unlocked: count >= entry.goal };
    }
    case "win_streak":
    case "flawless":
      return { progress: 0, unlocked: false };
    case "completed_trips": {
      const count = Math.max(0, ctx.lifetimeStats?.totalCompletedTrips ?? 0);
      return { progress: count, unlocked: count >= entry.goal };
    }
    case "family_member": {
      const progress = ctx.isFamilyMember ? 1 : 0;
      return { progress, unlocked: progress >= entry.goal };
    }
    case "competitive_wins": {
      const count = Math.max(0, ctx.progression.competitiveFirstPlaceFinishes);
      return { progress: count, unlocked: count >= entry.goal };
    }
    case "royale_member": {
      const progress = ctx.isRoyale ? 1 : 0;
      return { progress, unlocked: progress >= entry.goal };
    }
    case "founder": {
      const progress = ctx.isFounder ? 1 : 0;
      return { progress, unlocked: progress >= entry.goal };
    }
    default:
      return { progress: 0, unlocked: false };
  }
}
