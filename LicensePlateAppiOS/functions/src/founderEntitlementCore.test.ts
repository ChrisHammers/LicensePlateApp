import { describe, expect, it } from "vitest";
import {
  decideFounderGrant,
  hasFounderTag,
  isFounderProgramActive,
  parseEntitlementTags,
  parseFounderProgramConfig,
} from "./founderEntitlementCore";

describe("parseEntitlementTags", () => {
  it("returns empty array when missing or invalid", () => {
    expect(parseEntitlementTags(undefined)).toEqual([]);
    expect(parseEntitlementTags({ entitlementTags: "founder" })).toEqual([]);
  });

  it("filters non-string entries", () => {
    expect(parseEntitlementTags({ entitlementTags: ["founder", 1, "", "lifetime"] })).toEqual([
      "founder",
      "lifetime",
    ]);
  });
});

describe("hasFounderTag", () => {
  it("detects founder tag", () => {
    expect(hasFounderTag({ entitlementTags: ["founder"] })).toBe(true);
    expect(hasFounderTag({ entitlementTags: ["lifetime"] })).toBe(false);
  });
});

describe("parseFounderProgramConfig", () => {
  it("defaults to enabled with no end date", () => {
    expect(parseFounderProgramConfig(null)).toEqual({ enabled: true, endsAt: null });
  });

  it("parses disabled program", () => {
    expect(parseFounderProgramConfig({ enabled: false })).toEqual({
      enabled: false,
      endsAt: null,
    });
  });

  it("parses endsAt from ISO string", () => {
    const config = parseFounderProgramConfig({ enabled: true, endsAt: "2030-01-01T00:00:00.000Z" });
    expect(config.endsAt?.toISOString()).toBe("2030-01-01T00:00:00.000Z");
  });
});

describe("isFounderProgramActive", () => {
  it("returns false when disabled", () => {
    expect(isFounderProgramActive({ enabled: false, endsAt: null })).toBe(false);
  });

  it("returns false when endsAt is in the past", () => {
    expect(
      isFounderProgramActive(
        { enabled: true, endsAt: new Date("2020-01-01T00:00:00.000Z") },
        new Date("2021-01-01T00:00:00.000Z")
      )
    ).toBe(false);
  });

  it("returns true when enabled and not ended", () => {
    expect(
      isFounderProgramActive(
        { enabled: true, endsAt: new Date("2030-01-01T00:00:00.000Z") },
        new Date("2026-01-01T00:00:00.000Z")
      )
    ).toBe(true);
  });
});

describe("decideFounderGrant", () => {
  const activeProgram = { enabled: true, endsAt: null };
  const now = new Date("2026-06-01T00:00:00.000Z");

  it("returns alreadyGranted when tag exists", () => {
    expect(
      decideFounderGrant({
        userData: { entitlementTags: ["founder"] },
        programConfig: activeProgram,
        now,
      })
    ).toEqual({ outcome: "alreadyGranted" });
  });

  it("returns programDisabled when config disabled", () => {
    expect(
      decideFounderGrant({
        userData: {},
        programConfig: { enabled: false, endsAt: null },
        now,
      })
    ).toEqual({ outcome: "programDisabled" });
  });

  it("returns programEnded when cutoff passed", () => {
    expect(
      decideFounderGrant({
        userData: {},
        programConfig: { enabled: true, endsAt: new Date("2020-01-01T00:00:00.000Z") },
        now,
      })
    ).toEqual({ outcome: "programEnded" });
  });

  it("returns grant when eligible", () => {
    expect(
      decideFounderGrant({
        userData: {},
        programConfig: activeProgram,
        now,
      })
    ).toEqual({ outcome: "grant" });
  });
});
