/**
 * Push preference helpers for `users/{uid}.notificationPrefs`.
 * Missing booleans default to ON (older clients), except promotionsAndNews → OFF.
 */

export type PushCategory =
  | "friend"
  | "family"
  | "tripInvite"
  | "tripEnded"
  | "plateFoundByOpponent"
  | "plateFoundByCoPilots"
  | "inactiveTripReminder"
  | "returnStreakReminder"
  | "promotionsAndNews";

/** @deprecated Use PushCategory */
export type SocialPushCategory = "friend" | "family";

export interface NotificationPrefs {
  friend?: boolean;
  family?: boolean;
  tripInvite?: boolean;
  tripEnded?: boolean;
  plateFoundByOpponent?: boolean;
  plateFoundByCoPilots?: boolean;
  inactiveTripReminder?: boolean;
  returnStreakReminder?: boolean;
  promotionsAndNews?: boolean;
}

const PREF_KEYS: PushCategory[] = [
  "friend",
  "family",
  "tripInvite",
  "tripEnded",
  "plateFoundByOpponent",
  "plateFoundByCoPilots",
  "inactiveTripReminder",
  "returnStreakReminder",
  "promotionsAndNews",
];

function readOptionalBool(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

/** Resolve prefs from a users/{uid} document payload. */
export function notificationPrefsFromUserData(
  data: Record<string, unknown> | undefined | null
): NotificationPrefs {
  const raw = data?.notificationPrefs;
  if (!raw || typeof raw !== "object") {
    return {};
  }
  const prefs = raw as Record<string, unknown>;
  const out: NotificationPrefs = {};
  for (const key of PREF_KEYS) {
    const value = readOptionalBool(prefs[key]);
    if (value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}

/**
 * Whether a push category is allowed.
 * Explicit `false` disables; missing / non-boolean = enabled,
 * except `promotionsAndNews` where missing = disabled.
 */
export function isPushEnabled(
  prefs: NotificationPrefs | null | undefined,
  category: PushCategory
): boolean {
  if (!prefs) {
    return category !== "promotionsAndNews";
  }
  const value = prefs[category];
  if (typeof value !== "boolean") {
    return category !== "promotionsAndNews";
  }
  return value;
}

/**
 * @deprecated Use isPushEnabled
 */
export function isSocialPushEnabled(
  prefs: NotificationPrefs | null | undefined,
  category: SocialPushCategory
): boolean {
  return isPushEnabled(prefs, category);
}
