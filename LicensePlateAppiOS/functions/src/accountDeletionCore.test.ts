import { describe, it, expect } from "vitest";
import {
  RECENT_LOGIN_MAX_AGE_SECONDS,
  isRecentLogin,
  familyCleanupAction,
  decrementedFriendCount,
  otherFriendUserId,
} from "./accountDeletionCore";

describe("isRecentLogin", () => {
  const now = 1_700_000_000;

  it("accepts an auth_time inside the window", () => {
    expect(isRecentLogin(now - 10, now)).toBe(true);
    expect(isRecentLogin(now - RECENT_LOGIN_MAX_AGE_SECONDS, now)).toBe(true);
  });

  it("rejects an auth_time older than the window", () => {
    expect(isRecentLogin(now - RECENT_LOGIN_MAX_AGE_SECONDS - 1, now)).toBe(false);
    expect(isRecentLogin(now - 86_400, now)).toBe(false);
  });

  it("treats future auth_time (clock skew) as recent", () => {
    expect(isRecentLogin(now + 30, now)).toBe(true);
  });

  it("rejects missing or invalid auth_time", () => {
    expect(isRecentLogin(0, now)).toBe(false);
    expect(isRecentLogin(-1, now)).toBe(false);
    expect(isRecentLogin(Number.NaN, now)).toBe(false);
  });

  it("honors a custom window", () => {
    expect(isRecentLogin(now - 50, now, 60)).toBe(true);
    expect(isRecentLogin(now - 70, now, 60)).toBe(false);
  });
});

describe("familyCleanupAction", () => {
  it("inactivates the family when the deleted user created it and it is active", () => {
    expect(
      familyCleanupAction({ isMember: true, isCreator: true, familyStatus: "active" })
    ).toBe("inactivate_family");
  });

  it("removes only the member doc for non-creators", () => {
    expect(
      familyCleanupAction({ isMember: true, isCreator: false, familyStatus: "active" })
    ).toBe("remove_member");
  });

  it("removes only the member doc when the creator's family is already inactive", () => {
    expect(
      familyCleanupAction({ isMember: true, isCreator: true, familyStatus: "inactive" })
    ).toBe("remove_member");
  });

  it("does nothing when the user is not a member", () => {
    expect(
      familyCleanupAction({ isMember: false, isCreator: false, familyStatus: null })
    ).toBe("none");
  });
});

describe("decrementedFriendCount", () => {
  it("decrements a positive count", () => {
    expect(decrementedFriendCount(3)).toBe(2);
    expect(decrementedFriendCount(1)).toBe(0);
  });

  it("never goes negative", () => {
    expect(decrementedFriendCount(0)).toBe(0);
  });

  it("treats missing or junk values as zero", () => {
    expect(decrementedFriendCount(undefined)).toBe(0);
    expect(decrementedFriendCount(null)).toBe(0);
    expect(decrementedFriendCount("7")).toBe(0);
    expect(decrementedFriendCount(Number.NaN)).toBe(0);
  });
});

describe("otherFriendUserId", () => {
  it("returns the surviving side of the edge", () => {
    expect(otherFriendUserId({ userA: "me", userB: "them" }, "me")).toBe("them");
    expect(otherFriendUserId({ userA: "them", userB: "me" }, "me")).toBe("them");
  });

  it("returns null when the edge does not involve the deleted user", () => {
    expect(otherFriendUserId({ userA: "x", userB: "y" }, "me")).toBeNull();
  });

  it("returns null for malformed edges", () => {
    expect(otherFriendUserId({ userA: "me" }, "me")).toBeNull();
    expect(otherFriendUserId({}, "me")).toBeNull();
  });
});
