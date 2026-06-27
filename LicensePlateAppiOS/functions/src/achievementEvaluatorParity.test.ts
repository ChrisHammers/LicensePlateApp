import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";
import { achievementCatalogEntry } from "./achievementCatalogCore";
import {
  AchievementEvaluationContext,
  evaluateAchievement,
} from "./achievementProgressCore";

type FixtureCase = {
  achievementId: string;
  inputs: {
    progression: {
      everCompetitiveFirstPlace?: boolean;
      acceptedRegionFindCount?: number;
      competitiveFirstPlaceFinishes?: number;
    } | null;
    lifetimeStats: {
      totalCompletedTrips?: number;
      totalDiscoveries?: number;
    } | null;
    isFamilyMember: boolean;
    isRoyale: boolean;
    isFounder: boolean;
  };
  expected: { progress: number; unlocked: boolean };
};

type FixtureFile = { cases: FixtureCase[] };

const fixturePath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../LicensePlateAppTests/Fixtures/AchievementEvaluatorParityFixtures.json"
);
const fixture = JSON.parse(readFileSync(fixturePath, "utf8")) as FixtureFile;

function toEvaluationContext(inputs: FixtureCase["inputs"]): AchievementEvaluationContext {
  return {
    progression: {
      totalXp: 0,
      acceptedRegionFindCount: inputs.progression?.acceptedRegionFindCount ?? 0,
      competitiveFirstPlaceFinishes: inputs.progression?.competitiveFirstPlaceFinishes ?? 0,
      everCompetitiveFirstPlace: inputs.progression?.everCompetitiveFirstPlace ?? false,
    },
    lifetimeStats: inputs.lifetimeStats
      ? {
          totalCompletedTrips: inputs.lifetimeStats.totalCompletedTrips ?? 0,
          totalDiscoveries: inputs.lifetimeStats.totalDiscoveries ?? 0,
        }
      : null,
    isFamilyMember: inputs.isFamilyMember,
    isRoyale: inputs.isRoyale,
    isFounder: inputs.isFounder,
  };
}

describe("achievementEvaluatorParity", () => {
  for (const testCase of fixture.cases) {
    it(`${testCase.achievementId} matches fixture`, () => {
      const entry = achievementCatalogEntry(testCase.achievementId);
      expect(entry).toBeTruthy();
      expect(entry!.hidden).toBe(false);
      const result = evaluateAchievement(entry!, toEvaluationContext(testCase.inputs));
      expect(result.progress).toBe(testCase.expected.progress);
      expect(result.unlocked).toBe(testCase.expected.unlocked);
    });
  }

  it("covers all visible achievement ids", () => {
    const covered = new Set(fixture.cases.map((c) => c.achievementId));
    const visibleIds = [
      "first_win",
      "explorer_10",
      "plates_100",
      "trips_10",
      "family",
      "plates_1000",
      "wins_100",
      "trips_50",
      "royale",
      "coast_to_coast",
      "founder",
    ];
    for (const id of visibleIds) {
      expect(covered.has(id)).toBe(true);
    }
  });
});
