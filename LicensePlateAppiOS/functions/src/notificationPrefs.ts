/**
 * Social push preference helpers.
 * Missing prefs default to ON for older app versions.
 */

export type SocialPushCategory = "friend" | "family";

export interface NotificationPrefs {
  friend?: boolean;
  family?: boolean;
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
  return {
    friend: typeof prefs.friend === "boolean" ? prefs.friend : undefined,
    family: typeof prefs.family === "boolean" ? prefs.family : undefined,
  };
}

/**
 * Whether a social push category is allowed.
 * Explicit `false` disables; missing / non-boolean = enabled.
 */
export function isSocialPushEnabled(
  prefs: NotificationPrefs | null | undefined,
  category: SocialPushCategory
): boolean {
  if (!prefs) {
    return true;
  }
  const value = prefs[category];
  if (typeof value !== "boolean") {
    return true;
  }
  return value;
}
