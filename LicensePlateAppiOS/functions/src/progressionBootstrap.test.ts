import { describe, expect, it } from "vitest";
import { buildProgressionBootstrapDefaults } from "./progressionBootstrapCore";

describe("buildProgressionBootstrapDefaults", () => {
  it("creates default progression fields for a missing document", () => {
    const defaults = buildProgressionBootstrapDefaults(undefined);

    expect(defaults).toEqual({
      schemaVersion: 1,
      totalXp: 0,
      acceptedRegionFindCount: 0,
      competitiveFirstPlaceFinishes: 0,
      everCompetitiveFirstPlace: false,
      appliedProgressionEvents: {},
      appliedProgressionScopes: {},
    });
  });

  it("does not overwrite existing totals or applied maps", () => {
    const defaults = buildProgressionBootstrapDefaults({
      schemaVersion: 1,
      totalXp: 120,
      acceptedRegionFindCount: 7,
      competitiveFirstPlaceFinishes: 1,
      everCompetitiveFirstPlace: true,
      appliedProgressionEvents: { event1: true },
      appliedProgressionScopes: { scope1: true },
    });

    expect(defaults).toEqual({});
  });
});
