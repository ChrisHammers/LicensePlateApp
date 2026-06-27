import catalogJson from "./progressionCatalog.v1.json";

export type AchievementEvaluator =
  | "ever_competitive_first_place"
  | "accepted_region_count"
  | "total_discoveries"
  | "win_streak"
  | "completed_trips"
  | "family_member"
  | "competitive_wins"
  | "royale_member"
  | "flawless"
  | "founder";

export interface AchievementCatalogEntry {
  id: string;
  goal: number;
  xpReward: number;
  hidden: boolean;
  evaluator: AchievementEvaluator;
}

export interface ProgressionCatalogJson {
  schemaVersion: number;
  achievements: AchievementCatalogEntry[];
}

const catalog = catalogJson as ProgressionCatalogJson;

export function visibleAchievementCatalog(): AchievementCatalogEntry[] {
  return catalog.achievements.filter((entry) => !entry.hidden);
}

export function achievementCatalogEntry(id: string): AchievementCatalogEntry | undefined {
  return catalog.achievements.find((entry) => entry.id === id);
}

export function isKnownVisibleAchievementId(id: string): boolean {
  const entry = achievementCatalogEntry(id);
  return !!entry && !entry.hidden;
}
