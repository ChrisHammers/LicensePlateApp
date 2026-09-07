import { describe, it, expect } from "vitest";
import {
  CHILD_SUPPRESSED_PUSH_CATEGORIES,
  isPushCategoryAllowedForChild,
  isPushEnabled,
  isSocialPushEnabled,
  notificationPrefsFromUserData,
} from "./notificationPrefs";

describe("notificationPrefsFromUserData", () => {
  it("returns empty prefs when missing", () => {
    expect(notificationPrefsFromUserData(undefined)).toEqual({});
    expect(notificationPrefsFromUserData(null)).toEqual({});
    expect(notificationPrefsFromUserData({})).toEqual({});
    expect(notificationPrefsFromUserData({ notificationPrefs: "nope" })).toEqual({});
  });

  it("reads known boolean keys only", () => {
    expect(
      notificationPrefsFromUserData({
        notificationPrefs: {
          friend: false,
          family: true,
          tripInvite: false,
          plateFoundByOpponent: true,
          promotionsAndNews: true,
          ignored: 1,
        },
      })
    ).toEqual({
      friend: false,
      family: true,
      tripInvite: false,
      plateFoundByOpponent: true,
      promotionsAndNews: true,
    });

    expect(
      notificationPrefsFromUserData({
        notificationPrefs: { friend: "false", family: 0, tripEnded: true },
      })
    ).toEqual({ tripEnded: true });
  });
});

describe("isPushEnabled", () => {
  it("defaults to enabled when prefs are missing (except promotions)", () => {
    expect(isPushEnabled(undefined, "friend")).toBe(true);
    expect(isPushEnabled(null, "family")).toBe(true);
    expect(isPushEnabled({}, "tripInvite")).toBe(true);
    expect(isPushEnabled({}, "tripEnded")).toBe(true);
    expect(isPushEnabled({}, "plateFoundByOpponent")).toBe(true);
    expect(isPushEnabled({}, "plateFoundByCoPilots")).toBe(true);
    expect(isPushEnabled({}, "inactiveTripReminder")).toBe(true);
    expect(isPushEnabled({}, "returnStreakReminder")).toBe(true);
    expect(isPushEnabled({}, "promotionsAndNews")).toBe(false);
    expect(isPushEnabled({ family: false }, "friend")).toBe(true);
  });

  it("respects explicit false / true", () => {
    expect(isPushEnabled({ friend: false }, "friend")).toBe(false);
    expect(isPushEnabled({ friend: true }, "friend")).toBe(true);
    expect(isPushEnabled({ tripInvite: false }, "tripInvite")).toBe(false);
    expect(isPushEnabled({ plateFoundByCoPilots: false }, "plateFoundByCoPilots")).toBe(false);
    expect(isPushEnabled({ promotionsAndNews: true }, "promotionsAndNews")).toBe(true);
    expect(isPushEnabled({ promotionsAndNews: false }, "promotionsAndNews")).toBe(false);
  });
});

describe("isSocialPushEnabled", () => {
  it("delegates to isPushEnabled for friend/family", () => {
    expect(isSocialPushEnabled(undefined, "friend")).toBe(true);
    expect(isSocialPushEnabled(null, "family")).toBe(true);
    expect(isSocialPushEnabled({ friend: false }, "friend")).toBe(false);
    expect(isSocialPushEnabled({ family: true }, "family")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// FR-73(c) — which categories a child may never be sent
// ---------------------------------------------------------------------------

describe("FR-73(c): isPushCategoryAllowedForChild", () => {
  it("blocks the marketing category", () => {
    expect(isPushCategoryAllowedForChild("promotionsAndNews")).toBe(false);
  });

  /**
   * The bounded family-trip set parental consent covers (FR-38 / v3 §5 R-15). Listed
   * explicitly rather than derived, so a category added to `PushCategory` without a
   * decision about children fails this test instead of silently defaulting to allowed.
   */
  it("allows every transactional and family-state category", () => {
    for (const category of [
      "friend",
      "family",
      "tripInvite",
      "tripEnded",
      "plateFoundByOpponent",
      "plateFoundByCoPilots",
      "inactiveTripReminder",
      "returnStreakReminder",
    ] as const) {
      expect(isPushCategoryAllowedForChild(category)).toBe(true);
    }
  });

  /**
   * v3 §5 R-15 pin: the suppressed set is EXACTLY the marketing category. The declined
   * engagement-defaults half stays declined; widening this list is an owner decision.
   */
  it("suppresses exactly one category", () => {
    expect([...CHILD_SUPPRESSED_PUSH_CATEGORIES]).toEqual(["promotionsAndNews"]);
  });

  /** The child gate is independent of preferences — neither one can re-enable the other. */
  it("is orthogonal to the preference gate", () => {
    expect(isPushEnabled({ promotionsAndNews: true }, "promotionsAndNews")).toBe(true);
    expect(isPushCategoryAllowedForChild("promotionsAndNews")).toBe(false);
  });
});
