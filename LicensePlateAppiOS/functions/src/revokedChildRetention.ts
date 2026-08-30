/**
 * FR-63(c) / FR-77, second retention class — OD-3 DECIDED 2026-08-30 (owner): 12 months.
 *
 * The abandonment backstop for STICKY POST-REVOCATION children: a parent chose
 * "remove, keep their data" (FR-63(a)) and then simply walked away. The account sits in
 * the FR-28 restricted state with the FR-62 rights live; §312.10 forbids keeping it
 * indefinitely, so once the revocation is older than the OD-3 window this sweep deletes
 * it through the SAME machinery the parent's own deletion uses
 * (`executeAccountDeletionForUser` — idempotent, Auth user last, retry-safe).
 *
 * The clock anchors on the FR-62 guardianship record's `endedAtMillis` — server-written
 * at every membership end, never deleted, and SUPERSEDED WHOLESALE by any re-grant (a
 * re-admitted child's record is live again, carries no `endedAtMillis`, and the range
 * query below structurally cannot match it).
 *
 * This deliberately does NOT touch the redemption-window population — never-consented
 * provisional children have their own 7-day sweep (`provisionalChildAccounts.ts`), and
 * the two predicates are disjoint by construction (this one requires an ENDED
 * guardianship, which only a consent grant ever creates).
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

/** OD-3 (owner, 2026-08-30): 12 months, implemented as days for millis math. */
export const REVOKED_CHILD_RETENTION_DAYS_DEFAULT = 365;

/**
 * Dev knob, same pattern as CONSENT_PLUS_NOTICE_DELAY_MINUTES: set
 * REVOKED_CHILD_RETENTION_DAYS in the functions env to shrink the window for a live
 * verification (0 = every revoked child qualifies immediately — deliberately NOT set
 * in the dev env file; setting it is a conscious destructive-test act).
 */
export function revokedChildRetentionDays(): number {
  // An unset/empty knob must fall to the OD-3 default — `Number("")` is 0, and a 0-day
  // default would delete every revoked child on the first nightly run. Pinned by test.
  const raw = process.env.REVOKED_CHILD_RETENTION_DAYS;
  if (raw === undefined || raw.trim() === "") {
    return REVOKED_CHILD_RETENTION_DAYS_DEFAULT;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0
    ? parsed
    : REVOKED_CHILD_RETENTION_DAYS_DEFAULT;
}

export function revokedChildDeletionCutoffMillis(
  nowMillis: number,
  windowDays: number = revokedChildRetentionDays()
): number {
  return nowMillis - windowDays * MS_PER_DAY;
}

export const REVOKED_CHILD_SWEEP_MAX_DELETES = 25;
export const REVOKED_CHILD_SWEEP_MAX_SCANNED = 500;
export const REVOKED_CHILD_SWEEP_PAGE_SIZE = 50;

export interface RevokedChildSweepResult {
  scanned: number;
  deleted: number;
  /** uid-only, matching the FR-64 reconcile's logging discipline. */
  deletedUids: string[];
  skipped: {
    userGone: number;
    notChild: number;
    liveMembership: number;
    liveJoinRequest: number;
  };
  truncated: boolean;
}

/**
 * Delete revoked-and-abandoned child accounts whose guardianship ended before
 * `cutoffMillis`. Every skip fails safe toward retention:
 *  - users/{uid} missing            → already deleted elsewhere; nothing to do.
 *  - isChildAccount !== true        → corrected to adult; not this sweep's population.
 *  - activeFamilyId set             → live membership again (this also transitively
 *    covers a member_flag consent request in flight: its child IS a member while the
 *    request is pending, and its expiry removes the member before this could match).
 *  - live join request              → a re-admission decision is in flight
 *    (`hasLiveJoinRequest` honors BOTH live statuses incl. awaiting_guardian — the
 *    child whose guardian's confirmation email sits unread is the last account any
 *    sweep may touch).
 */
export async function sweepAbandonedRevokedChildAccounts(
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
): Promise<RevokedChildSweepResult> {
  const maxDeletes = options.maxDeletes ?? REVOKED_CHILD_SWEEP_MAX_DELETES;
  const maxScanned = options.maxScanned ?? REVOKED_CHILD_SWEEP_MAX_SCANNED;
  const pageSize = options.pageSize ?? REVOKED_CHILD_SWEEP_PAGE_SIZE;

  const result: RevokedChildSweepResult = {
    scanned: 0,
    deleted: 0,
    deletedUids: [],
    skipped: { userGone: 0, notChild: 0, liveMembership: 0, liveJoinRequest: 0 },
    truncated: false,
  };
  const seen = new Set<string>();
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    if (result.deleted >= maxDeletes || result.scanned >= maxScanned) {
      result.truncated = true;
      break;
    }

    // Only guardianship docs carry `endedAtMillis`, and range operators never match a
    // missing field — so this structurally selects ENDED guardianships only; the doc-id
    // check below is belt and braces.
    let query: admin.firestore.Query = db
      .collectionGroup("private")
      .where("endedAtMillis", "<", options.cutoffMillis)
      .orderBy("endedAtMillis", "asc")
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
      if (doc.id !== "guardianship") continue;
      const childUserId = doc.ref.parent.parent?.id;
      if (!childUserId || seen.has(childUserId)) continue;
      seen.add(childUserId);

      const userDoc = await db.collection("users").doc(childUserId).get();
      if (!userDoc.exists) {
        result.skipped.userGone += 1;
        continue;
      }
      const userData = userDoc.data() ?? {};
      if (userData.isChildAccount !== true) {
        result.skipped.notChild += 1;
        continue;
      }
      if (
        typeof userData.activeFamilyId === "string" &&
        userData.activeFamilyId.length > 0
      ) {
        result.skipped.liveMembership += 1;
        continue;
      }
      if (await hasLiveJoinRequest(db, childUserId)) {
        result.skipped.liveJoinRequest += 1;
        continue;
      }

      await executeAccountDeletionForUser(
        db,
        {
          userId: childUserId,
          actorId: options.actorId,
          clientMetadata: null,
          revenueCatApiKey: options.revenueCatApiKey ?? null,
        },
        deps.accountDeletionDeps
      );
      await deps.deleteAuthUser(childUserId);
      result.deleted += 1;
      result.deletedUids.push(childUserId);
    }
  }

  return result;
}
