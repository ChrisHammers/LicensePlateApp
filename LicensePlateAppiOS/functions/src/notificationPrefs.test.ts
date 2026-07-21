import { describe, it, expect } from "vitest";
import {
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
