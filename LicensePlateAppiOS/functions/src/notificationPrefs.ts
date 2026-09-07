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
 * FR-73(c) — categories a CHILD account is never sent, whatever its prefs say.
 *
 * The amended §312.5(c)(7) internal-operations exception may not be used to "prompt or
 * encourage use of the service", and — unlike the bounded family-trip categories, which a
 * parent's consent does cover (v3 §5 R-15) — nothing a parent consented to reaches
 * promotional contact. The suppression is therefore unconditional for a child account,
 * consented or not, and lives at the token chokepoint (`getFCMTokenForPush`) so it binds
 * every sender that exists now or later rather than one send path.
 *
 * Deliberately NOT extended to `inactiveTripReminder` / `returnStreakReminder`: v2.1 §18
 * considered per-category engagement defaults for CONSENTED children and DECLINED them,
 * and v3 §5 R-15 restates that decision as standing with FR-73(c) killing only the
 * marketing category. Widening this set is an owner decision, not an implementation one.
 */
export const CHILD_SUPPRESSED_PUSH_CATEGORIES: readonly PushCategory[] = [
  "promotionsAndNews",
];

/** FR-73(c): may this category be delivered to a child account at all? */
export function isPushCategoryAllowedForChild(category: PushCategory): boolean {
  return !CHILD_SUPPRESSED_PUSH_CATEGORIES.includes(category);
}

/**
 * Whether a push category is allowed.
 * Explicit `false` disables; missing / non-boolean = enabled,
 * except `promotionsAndNews` where missing = disabled.
 *
 * Preference-scoped ONLY. The FR-73(c) child suppression is a separate, stronger gate that
 * no preference can re-enable — see `isPushCategoryAllowedForChild`.
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
