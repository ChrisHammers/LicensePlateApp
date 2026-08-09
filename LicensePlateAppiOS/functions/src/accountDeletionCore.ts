/**
 * Pure policy for the deleteAccount callable (App Review 5.1.1(v) in-app account deletion).
 * Keep Firestore-free so vitest can cover the rules directly.
 */

/** Matches the Firebase client SDK's own recent-login window for sensitive operations. */
export const RECENT_LOGIN_MAX_AGE_SECONDS = 5 * 60;

/**
 * A deletion request must carry a token whose auth_time is fresh enough.
 * Future auth_time (clock skew) counts as recent; missing/invalid auth_time does not.
 */
export function isRecentLogin(
  authTimeSeconds: number,
  nowSeconds: number,
  maxAgeSeconds: number = RECENT_LOGIN_MAX_AGE_SECONDS
): boolean {
  if (!Number.isFinite(authTimeSeconds) || authTimeSeconds <= 0) return false;
  const ageSeconds = nowSeconds - authTimeSeconds;
  return ageSeconds <= maxAgeSeconds;
}

export type FamilyCleanupAction = "inactivate_family" | "remove_member" | "none";

/**
 * Account deletion is a forced self-leave. Creators take their active family down
 * with them (mirrors onAuthUserDeleted); everyone else just loses their member doc.
 * Regular self-leave policy (canRemoveFamilyMember) blocks creator self-leave, which
 * is exactly why deletion resolves creators to family inactivation instead.
 */
export function familyCleanupAction(args: {
  isMember: boolean;
  isCreator: boolean;
  familyStatus: string | null;
}): FamilyCleanupAction {
  if (!args.isMember) return "none";
  if (args.isCreator && args.familyStatus === "active") return "inactivate_family";
  return "remove_member";
}

/** friendCount never goes negative and treats junk values as zero (mirrors removeFriend). */
export function decrementedFriendCount(current: unknown): number {
  const count =
    typeof current === "number" && Number.isFinite(current) ? current : 0;
  return Math.max(0, count - 1);
}

/** The surviving side of a friend edge, or null when the edge does not involve the user. */
export function otherFriendUserId(
  edge: { userA?: unknown; userB?: unknown },
  deletedUserId: string
): string | null {
  const userA = typeof edge.userA === "string" ? edge.userA : null;
  const userB = typeof edge.userB === "string" ? edge.userB : null;
  if (userA === deletedUserId) return userB;
  if (userB === deletedUserId) return userA;
  return null;
}
