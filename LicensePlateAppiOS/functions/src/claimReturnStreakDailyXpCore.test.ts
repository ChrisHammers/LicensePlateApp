import { describe, it, expect } from "vitest";
import {
  planReturnStreakDailyClaim,
  returnStreakDailyScopeKey,
  RETURN_STREAK_DAILY_XP_AMOUNT,
  RETURN_STREAK_MIN_STREAK_FOR_XP,
} from "./claimReturnStreakDailyXpCore";

describe("claimReturnStreakDailyXpCore", () => {
  it("builds stable scope keys", () => {
    expect(returnStreakDailyScopeKey("u1", "2026-07-11")).toBe(
      "return_streak_daily|v1|u1|2026-07-11"
    );
  });

  it("rejects streak below minimum", () => {
    const plan = planReturnStreakDailyClaim({
      userId: "u1",
      dayKey: "2026-07-10",
      currentStreak: 1,
      progressionData: {},
    });
    expect(plan).toEqual({ outcome: "rejected", reason: "streak_below_minimum" });
    expect(RETURN_STREAK_MIN_STREAK_FOR_XP).toBe(2);
  });

  it("rejects invalid dayKey", () => {
    const plan = planReturnStreakDailyClaim({
      userId: "u1",
      dayKey: "07-10-2026",
      currentStreak: 3,
      progressionData: {},
    });
    expect(plan).toEqual({ outcome: "rejected", reason: "invalid_day_key" });
  });

  it("plans a claim for streak >= 2", () => {
    const plan = planReturnStreakDailyClaim({
      userId: "u1",
      dayKey: "2026-07-11",
      currentStreak: 2,
      progressionData: {},
    });
    expect(plan).toEqual({
      outcome: "claim",
      scopeKey: "return_streak_daily|v1|u1|2026-07-11",
      amount: RETURN_STREAK_DAILY_XP_AMOUNT,
      dayKey: "2026-07-11",
      currentStreak: 2,
    });
  });

  it("no-ops when scope already applied", () => {
    const scopeKey = returnStreakDailyScopeKey("u1", "2026-07-11");
    const plan = planReturnStreakDailyClaim({
      userId: "u1",
      dayKey: "2026-07-11",
      currentStreak: 4,
      progressionData: {
        appliedProgressionScopes: { [scopeKey]: true },
      },
    });
    expect(plan).toEqual({ outcome: "already_claimed", scopeKey });
  });
});
