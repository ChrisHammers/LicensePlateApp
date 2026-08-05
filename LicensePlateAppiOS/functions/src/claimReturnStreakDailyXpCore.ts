/**
 * Pure helpers for claimReturnStreakDailyXp (unit-testable).
 */

export const RETURN_STREAK_DAILY_XP_AMOUNT = 5;
export const RETURN_STREAK_MIN_STREAK_FOR_XP = 2;

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

export function returnStreakDailyScopeKey(userId: string, dayKey: string): string {
  return `return_streak_daily|v1|${userId}|${dayKey}`;
}

export function isValidReturnStreakDayKey(dayKey: unknown): dayKey is string {
  return typeof dayKey === "string" && DAY_KEY_RE.test(dayKey);
}

export function normalizeCurrentStreak(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  const streak = Math.floor(value);
  if (streak < 1) {
    return null;
  }
  return streak;
}

export type ClaimReturnStreakPlan =
  | { outcome: "rejected"; reason: "invalid_day_key" | "invalid_current_streak" | "streak_below_minimum" }
  | { outcome: "already_claimed"; scopeKey: string }
  | {
      outcome: "claim";
      scopeKey: string;
      amount: number;
      dayKey: string;
      currentStreak: number;
    };

export function getMergedAppliedProgressionScopes(
  docData: Record<string, unknown>
): Record<string, unknown> | undefined {
  const nested = docData.appliedProgressionScopes;
  if (
    nested !== null &&
    nested !== undefined &&
    !Array.isArray(nested) &&
    typeof nested === "object"
  ) {
    return nested as Record<string, unknown>;
  }
  const prefix = "appliedProgressionScopes.";
  const synthetic: Record<string, unknown> = {};
  for (const k of Object.keys(docData)) {
    if (k.startsWith(prefix) && k.length > prefix.length) {
      synthetic[k.slice(prefix.length)] = docData[k] as unknown;
    }
  }
  return Object.keys(synthetic).length > 0 ? synthetic : undefined;
}

export function planReturnStreakDailyClaim(input: {
  userId: string;
  dayKey: unknown;
  currentStreak: unknown;
  progressionData: Record<string, unknown>;
}): ClaimReturnStreakPlan {
  if (!isValidReturnStreakDayKey(input.dayKey)) {
    return { outcome: "rejected", reason: "invalid_day_key" };
  }
  const currentStreak = normalizeCurrentStreak(input.currentStreak);
  if (currentStreak == null) {
    return { outcome: "rejected", reason: "invalid_current_streak" };
  }
  if (currentStreak < RETURN_STREAK_MIN_STREAK_FOR_XP) {
    return { outcome: "rejected", reason: "streak_below_minimum" };
  }

  const scopeKey = returnStreakDailyScopeKey(input.userId, input.dayKey);
  const scopes = getMergedAppliedProgressionScopes(input.progressionData);
  if (scopes && scopes[scopeKey] != null) {
    return { outcome: "already_claimed", scopeKey };
  }

  return {
    outcome: "claim",
    scopeKey,
    amount: RETURN_STREAK_DAILY_XP_AMOUNT,
    dayKey: input.dayKey,
    currentStreak,
  };
}
