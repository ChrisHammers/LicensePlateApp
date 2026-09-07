/**
 * FR-77 / NP-3 row 11 — OD-3 DECIDED 2026-08-30 (owner): 36 months, ALL AGES.
 *
 * §312.10 forbids keeping personal information "indefinitely". Every other retention class
 * in this program is anchored on an EVENT (a declaration, a revocation, an expiry); this one
 * is anchored on the absence of one. An account nobody has authenticated into for three years
 * has outlived the purpose it was collected for, so it is deleted through the same machinery
 * a parent's or a user's own deletion uses (`executeAccountDeletionForUser` — idempotent,
 * Auth user last, retry-safe).
 *
 * WHY ALL AGES, AND WHY THIS LONG (owner ruling, recorded in RETENTION_POLICY.md row 11)
 * -------------------------------------------------------------------------------------
 * Road-trip play is episodic: a year between family trips is normal use, not abandonment.
 * Children are the likeliest returners, so a shorter child window would delete exactly the
 * accounts most likely to come back, and it would delete a child's side of a family's shared
 * trip history while the parent's review and deletion rights (FR-62) are live the whole time.
 * Equal windows, deliberately long, revisitable downward later.
 *
 * PER-ACCOUNT, NOT PER-FAMILY — a decision, not an oversight (FR-77, 2026-08-30)
 * -----------------------------------------------------------------------------
 * The window is measured on THIS account's own `lastDateLoggedIn` and nothing else. An
 * inactive member of a family that is otherwise busy is still deleted, because the policy
 * text says "no authenticated activity" for the ACCOUNT — a relative's play is not this
 * person's use of the service, and reading a family's recency as consent-to-retain would
 * make the window unbounded for anyone who shares a household with an active player. That is
 * exactly the indefinite retention §312.10 prohibits.
 *
 * The converse interplay is intended, not a side effect: deleting a family CREATOR takes the
 * family down with it (`executeAccountDeletionForUser`'s inactivate-family branch). A family
 * whose creator has not signed in for three years has no one left holding the parental
 * controls, and the remaining members' own accounts are untouched and keep their history.
 *
 * WHAT THIS SWEEP DELIBERATELY DOES NOT DO
 * ----------------------------------------
 * It does not touch an account with NO `lastDateLoggedIn` at all. A missing timestamp is
 * absent evidence, not evidence of absence, and this sweep never deletes on absent evidence.
 * The two populations that legitimately lack one — the redemption-window child and the
 * sticky post-revocation child — have their own event-anchored sweeps
 * (`provisionalChildAccounts.ts`, `revokedChildRetention.ts`).
 */

import * as admin from "firebase-admin";
import { executeAccountDeletionForUser } from "./accountDeletion";
import {
  ProvisionalChildCleanupDeps,
  hasLiveJoinRequest,
  liveProvisionalChildCleanupDeps,
} from "./provisionalChildAccounts";

type Firestore = admin.firestore.Firestore;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * The only "authenticated activity" signal the server holds. Written by the iOS login patch
 * (`FirebaseAuthService.updateLoginTimestampsInFirestore`) as a Firestore `Timestamp`, and
 * listed in `AuthProfileSyncPolicy.loginTimestampFieldKeys` so nothing else may ride along
 * with it. It is the sweep's cursor field.
 */
export const LAST_AUTHENTICATED_ACTIVITY_FIELD = "lastDateLoggedIn";

/**
 * FR-63(b)'s deletion-intent marker, written by `requestChildDataDeletionFlow` before it
 * ends membership and mirrored in `firestore.rules`' server-controlled key guard. Its
 * presence means a PARENT-DIRECTED deletion is already mid-cascade for this account.
 */
export const PENDING_DELETION_MARKER_FIELDS: readonly string[] = [
  "pendingDeletionRequestedBy",
  "pendingDeletionRequestedAtMillis",
];

/** OD-3 (owner, 2026-08-30): 36 months, implemented as days for millis math. */
export const INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT = 1095;

/**
 * Dev knob, same pattern as REVOKED_CHILD_RETENTION_DAYS: set
 * INACTIVE_ACCOUNT_RETENTION_DAYS in the functions env to shrink the window for a live
 * verification (0 = every account with a login stamp qualifies immediately — deliberately
 * NOT set in the dev env file; setting it is a conscious destructive-test act).
 */
export function inactiveAccountRetentionDays(): number {
  // An unset/empty knob must fall to the OD-3 default — `Number("")` is 0, and a 0-day
  // default would delete every account on the first nightly run. Pinned by test.
  const raw = process.env.INACTIVE_ACCOUNT_RETENTION_DAYS;
  if (raw === undefined || raw.trim() === "") {
    return INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0
    ? parsed
    : INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT;
}

export function inactiveAccountDeletionCutoffMillis(
  nowMillis: number,
  windowDays: number = inactiveAccountRetentionDays()
): number {
  return nowMillis - windowDays * MS_PER_DAY;
}

export const INACTIVE_ACCOUNT_SWEEP_MAX_DELETES = 25;
export const INACTIVE_ACCOUNT_SWEEP_MAX_SCANNED = 500;
export const INACTIVE_ACCOUNT_SWEEP_PAGE_SIZE = 50;

/**
 * Millis for a stored activity stamp, or `null` when the field is not one.
 *
 * Two representations are recognised, and only two: a Firestore `Timestamp` (what the login
 * patch writes in production) and a raw millis number (what the FakeFirestore harness stores
 * — it JSON-clones every value, so a `Timestamp` there comes back as a method-less map; the
 * convention is recorded in `provisionalChildAccounts.test.ts`). Anything else — a map, a
 * string, `null`, a missing field — reads as NO evidence of activity and is never deleted on.
 *
 * The numeric branch is not a safety hole: `lastDateLoggedIn` lives on the account's own user
 * doc, so a client forging a number there can only shorten its OWN window, never anyone
 * else's, and the caller still re-verifies the value against the cutoff.
 */
export function lastAuthenticatedActivityMillis(
  data: Record<string, unknown> | undefined | null
): number | null {
  const value = data?.[LAST_AUTHENTICATED_ACTIVITY_FIELD];
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (
    value &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    const millis = (value as { toMillis: () => number }).toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

/** True when a parent-directed deletion is already in flight for this account. */
export function hasPendingDeletionMarker(
  data: Record<string, unknown> | undefined | null
): boolean {
  if (!data) return false;
  return PENDING_DELETION_MARKER_FIELDS.some(
    (field) => data[field] !== undefined && data[field] !== null
  );
}

export interface InactiveAccountSweepResult {
  scanned: number;
  deleted: number;
  /** uid-only, matching the FR-64 reconcile's logging discipline. */
  deletedUids: string[];
  skipped: {
    missingTimestamp: number;
    notInactive: number;
    pendingDeletion: number;
    liveJoinRequest: number;
  };
  truncated: boolean;
}

/**
 * Delete accounts with no authenticated activity since `cutoffMillis`. Every skip fails safe
 * toward retention:
 *  - no usable `lastDateLoggedIn`  → absent evidence; this sweep never deletes on it. (In
 *    production the range filter already hides a missing field; the re-check also catches the
 *    real-Firestore case where an explicit `null` sorts BELOW a Timestamp and so is returned
 *    by a `<` query it has no business matching.)
 *  - stamp not actually older      → the account signed in between the page read and here.
 *  - pending-deletion marker       → FR-63(b): a parent already lawfully asked, and that
 *    cascade owns this account. Racing it would re-attribute a parent-directed deletion to
 *    the schedule and split one deletion's audit lineage across two actors.
 *  - live join request             → a consent decision is in flight (`hasLiveJoinRequest`
 *    honors BOTH live statuses incl. awaiting_guardian — the child whose guardian's
 *    confirmation email sits unread is the last account any sweep may touch).
 */
export async function sweepInactiveAccounts(
  db: Firestore,
  options: {
    cutoffMillis: number;
    actorId: string;
    revenueCatApiKey?: string | null;
    maxDeletes?: number;
    maxScanned?: number;
    pageSize?: number;
  },
  deps: ProvisionalChildCleanupDeps = liveProvisionalChildCleanupDeps
): Promise<InactiveAccountSweepResult> {
  const maxDeletes = options.maxDeletes ?? INACTIVE_ACCOUNT_SWEEP_MAX_DELETES;
  const maxScanned = options.maxScanned ?? INACTIVE_ACCOUNT_SWEEP_MAX_SCANNED;
  const pageSize = options.pageSize ?? INACTIVE_ACCOUNT_SWEEP_PAGE_SIZE;
  const cutoff = admin.firestore.Timestamp.fromMillis(options.cutoffMillis);

  const result: InactiveAccountSweepResult = {
    scanned: 0,
    deleted: 0,
    deletedUids: [],
    skipped: {
      missingTimestamp: 0,
      notInactive: 0,
      pendingDeletion: 0,
      liveJoinRequest: 0,
    },
    truncated: false,
  };
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    if (result.deleted >= maxDeletes || result.scanned >= maxScanned) {
      result.truncated = true;
      break;
    }

    // Single-field inequality + `orderBy` on the same field, so Firestore serves it from the
    // automatic single-field index — no composite index to deploy. Oldest first, so a
    // truncated run always makes progress from the far end of the backlog.
    let query: admin.firestore.Query = db
      .collection("users")
      .where(LAST_AUTHENTICATED_ACTIVITY_FIELD, "<", cutoff)
      .orderBy(LAST_AUTHENTICATED_ACTIVITY_FIELD, "asc")
      .limit(pageSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];
    result.scanned += snapshot.size;

    for (const doc of snapshot.docs) {
      if (result.deleted >= maxDeletes) {
        result.truncated = true;
        break;
      }

      const data = doc.data() ?? {};
      const activeAt = lastAuthenticatedActivityMillis(data);
      if (activeAt === null) {
        result.skipped.missingTimestamp += 1;
        continue;
      }
      if (activeAt >= options.cutoffMillis) {
        result.skipped.notInactive += 1;
        continue;
      }
      if (hasPendingDeletionMarker(data)) {
        result.skipped.pendingDeletion += 1;
        continue;
      }
      if (await hasLiveJoinRequest(db, doc.id)) {
        result.skipped.liveJoinRequest += 1;
        continue;
      }

      await executeAccountDeletionForUser(
        db,
        {
          userId: doc.id,
          actorId: options.actorId,
          clientMetadata: null,
          revenueCatApiKey: options.revenueCatApiKey ?? null,
        },
        deps.accountDeletionDeps
      );
      await deps.deleteAuthUser(doc.id);
      result.deleted += 1;
      result.deletedUids.push(doc.id);
    }
  }

  return result;
}
