import { describe, it, expect } from "vitest";
import {
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

  it("reads boolean friend/family only", () => {
    expect(
      notificationPrefsFromUserData({
        notificationPrefs: { friend: false, family: true, ignored: 1 },
      })
    ).toEqual({ friend: false, family: true });

    expect(
      notificationPrefsFromUserData({
        notificationPrefs: { friend: "false", family: 0 },
      })
    ).toEqual({ friend: undefined, family: undefined });
  });
});

describe("isSocialPushEnabled", () => {
  it("defaults to enabled when prefs are missing", () => {
    expect(isSocialPushEnabled(undefined, "friend")).toBe(true);
    expect(isSocialPushEnabled(null, "family")).toBe(true);
    expect(isSocialPushEnabled({}, "friend")).toBe(true);
    expect(isSocialPushEnabled({ family: false }, "friend")).toBe(true);
  });

  it("respects explicit false / true", () => {
    expect(isSocialPushEnabled({ friend: false }, "friend")).toBe(false);
    expect(isSocialPushEnabled({ friend: true }, "friend")).toBe(true);
    expect(isSocialPushEnabled({ family: false }, "family")).toBe(false);
    expect(isSocialPushEnabled({ family: true }, "family")).toBe(true);
  });
});
