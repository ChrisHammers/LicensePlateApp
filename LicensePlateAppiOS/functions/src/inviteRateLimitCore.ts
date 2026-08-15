/**
 * Invite rate-limit policy core — COPPA remediation FR-47 (F-10, audit F2 remainder).
 *
 * Pure policy: constants plus one fixed-window decision function. This module never calls
 * `admin.firestore()` at load time, so the whole limit matrix is unit-testable without a
 * Firestore stand-in (same shape as `retentionCore.ts`). The Firestore wiring — a
 * transactional read-modify-write of one counter doc — lives in `inviteRateLimit.ts`.
 *
 * WHY A FIRESTORE COUNTER RATHER THAN IN-MEMORY STATE
 * ---------------------------------------------------
 * Cloud Functions instances are ephemeral and horizontally scaled: a per-instance Map would
 * reset on every cold start and would not be shared between concurrent instances, so a
 * sender could trivially exceed any limit by spreading calls across instances. A counter doc
 * keyed by sender uid is the only variant that is both authoritative and deterministic, and
 * it is what makes the acceptance tests meaningful.
 *
 * WINDOW SEMANTICS
 * ----------------
 * Fixed window, lazily reset: the first call after a window lapses starts a fresh window at
 * that moment. There is no background job and no stored schedule — a counter is only ever
 * touched by the sender it belongs to. The trade-off versus a sliding window is the usual
 * boundary burst (up to 2x the limit across a window edge); at these limits that is well
 * inside the abuse threshold and buys a single-document, single-read implementation.
 */

/** Root collection holding one counter doc per (scope, sender). */
export const INVITE_RATE_LIMIT_COLLECTION = "invite_rate_limits";

/** Length of the fixed window every invite limit is expressed over. */
export const INVITE_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/**
 * Trip invites per sender per hour.
 *
 * Sizing: the client only ever offers friends + family as targets
 * (`InvitePlayersViewModel.loadCandidates`), and a family caps at a handful of members, so a
 * legitimate "invite everyone to this road trip" burst is well under ten. Twenty leaves ~2x
 * headroom for a genuine re-send after a failure while still bounding a spam run.
 */
export const TRIP_INVITE_MAX_PER_WINDOW = 20;

/**
 * Friend invites per sender per hour.
 *
 * Sizing: the standing friend cap is 100 total (`checkFriendCap`), so twenty per hour lets a
 * new user build out a normal friend list over a couple of sessions while making bulk
 * enumeration of accounts expensive.
 */
export const FRIEND_INVITE_MAX_PER_WINDOW = 20;

/**
 * Share-code redemptions per redeemer per hour (FR-67 / OD-4).
 *
 * Sizing: a code is six characters from a 36-symbol alphabet, so guessing one blind is a
 * 2.2-billion-attempt search. Ten per hour is far above any real "I mistyped the code my
 * cousin read out" burst and turns brute force into millennia. This is the limit that makes
 * FR-67's read-rule scoping meaningful: once `share_codes` stops being world-listable, the
 * callable is the only resolver left, so the callable is where the search has to be bounded.
 */
export const SHARE_REDEEM_MAX_PER_WINDOW = 10;

export type InviteRateLimitScope = "trip_invite" | "friend_invite" | "share_redeem";

export const INVITE_RATE_LIMIT_MAX_PER_WINDOW: Record<InviteRateLimitScope, number> = {
  trip_invite: TRIP_INVITE_MAX_PER_WINDOW,
  friend_invite: FRIEND_INVITE_MAX_PER_WINDOW,
  share_redeem: SHARE_REDEEM_MAX_PER_WINDOW,
};

/**
 * Rejection wording. `resource-exhausted` matches the existing friend-cap rejection in
 * `friends.ts`, which the client already maps to the `inviteFailedRateLimited` analytics
 * event (`FriendsFamilyInviteAnalytics.logInviteFailure`) — so no client change is needed to
 * classify or surface this.
 */
export const INVITE_RATE_LIMITED_MESSAGE =
  "Too many invites sent recently. Please try again later.";

export const INVITE_RATE_LIMITED_REASON = "invite_rate_limited";

/** One counter doc per (scope, sender). Firebase uids contain no "/", so this is a safe id. */
export function inviteRateLimitDocId(
  scope: InviteRateLimitScope,
  userId: string
): string {
  return `${scope}__${userId}`;
}

/** Every counter doc id a single user can own — used by account-deletion residue cleanup. */
export function inviteRateLimitDocIdsForUser(userId: string): string[] {
  return (Object.keys(INVITE_RATE_LIMIT_MAX_PER_WINDOW) as InviteRateLimitScope[]).map(
    (scope) => inviteRateLimitDocId(scope, userId)
  );
}

export interface InviteRateLimitWindow {
  windowStartAtMs: number;
  count: number;
}

export interface InviteRateLimitDecision {
  allowed: boolean;
  /** The window to persist when `allowed`; ignored when denied (nothing is written). */
  next: InviteRateLimitWindow;
  /** Milliseconds until the current window lapses. Zero when allowed. */
  retryAfterMs: number;
}

/**
 * Parse a stored counter doc, defensively. Anything malformed (missing, wrong type,
 * non-finite, negative) is treated as "no window", which starts a fresh one rather than
 * failing the call — a corrupt counter must never lock a user out of inviting.
 */
export function readInviteRateLimitWindow(
  data: Record<string, unknown> | undefined
): InviteRateLimitWindow | null {
  if (!data) return null;
  const windowStartAtMs = data.windowStartAtMs;
  const count = data.count;
  if (typeof windowStartAtMs !== "number" || !Number.isFinite(windowStartAtMs)) {
    return null;
  }
  if (typeof count !== "number" || !Number.isFinite(count) || count < 0) {
    return null;
  }
  return { windowStartAtMs, count: Math.floor(count) };
}

/**
 * Decide whether one more invite may be sent, and what the counter should become.
 *
 * `current === null` (no doc yet, or an unreadable one) and a lapsed window both start a
 * fresh window. A `windowStartAtMs` in the future — only reachable through clock skew or a
 * hand-edited doc — also restarts rather than blocking until the bogus timestamp passes.
 */
export function evaluateInviteRateLimit(
  current: InviteRateLimitWindow | null,
  nowMs: number,
  maxPerWindow: number,
  windowMs: number = INVITE_RATE_LIMIT_WINDOW_MS
): InviteRateLimitDecision {
  // A non-positive limit means "closed"; expressed here so the function stays total.
  if (maxPerWindow <= 0) {
    return {
      allowed: false,
      next: current ?? { windowStartAtMs: nowMs, count: 0 },
      retryAfterMs: windowMs,
    };
  }

  const elapsedMs = current === null ? Number.POSITIVE_INFINITY : nowMs - current.windowStartAtMs;

  if (current === null || elapsedMs >= windowMs || elapsedMs < 0) {
    return {
      allowed: true,
      next: { windowStartAtMs: nowMs, count: 1 },
      retryAfterMs: 0,
    };
  }

  if (current.count >= maxPerWindow) {
    return { allowed: false, next: current, retryAfterMs: windowMs - elapsedMs };
  }

  return {
    allowed: true,
    next: { windowStartAtMs: current.windowStartAtMs, count: current.count + 1 },
    retryAfterMs: 0,
  };
}
