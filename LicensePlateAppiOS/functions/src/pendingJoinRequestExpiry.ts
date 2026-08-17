/**
 * An unanswered family join request has its own clock — device pass 2026-08-17.
 *
 * THE BUG
 * -------
 * A child redeemed a family share code; the code (and the `invites` doc it minted) lapsed on
 * its 15-minute TTL; the captain's pending row stayed exactly as it was, indefinitely and
 * indistinguishably. `expireInvitesAndCodes` swept the invite to `expired` and never looked at
 * `families/{id}/pending` — nothing in the codebase ever did. So the row was owned by no clock
 * at all: not the invite's, not its own.
 *
 * THE DECISION, AND WHY IT IS NOT "EXPIRE THE ROW WITH THE INVITE"
 * ----------------------------------------------------------------
 * The 15-minute TTL is a REDEMPTION window. It bounds how long a code or an invite may be used
 * to *make* a request, which is a secret-handling property: a share code is a short human-typed
 * string, and its lifetime is how long a guessed or shoulder-surfed one stays useful.
 *
 * A pending row is not a redemption token. By the time it exists the redemption already
 * happened and was authorised — the row carries the FR-66(a) lineage stamp proving it. What the
 * row is waiting for is a HUMAN DECISION by a parent who is, very often, not holding the phone
 * in the same fifteen minutes. Applying the redemption clock to the decision is a category
 * error, and it is the one the owner hit from the other side: the row outliving its invite
 * looked like a leak, when in fact expiring it on the invite's clock would have been the real
 * defect. COPPA §312.5 wants this artifact to survive long enough for a guardian to actually
 * answer it.
 *
 * So the row gets its own, much longer lifetime, and the invite's expiry stops being a claim
 * about the row at all.
 *
 * WHY SEVEN DAYS EXACTLY
 * ----------------------
 * `PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS` is 7, and the two numbers MUST be the same one.
 *
 * FR-60(c)'s account sweep is vetoed by `hasLiveJoinRequest` — a `collectionGroup("pending")`
 * query on `status == "pending"` — precisely so an account is never deleted out from under a
 * decision a guardian could still make. That veto cuts both ways:
 *
 *   - a row allowed to outlive the account window would pin the account open forever, because
 *     the veto never lifts;
 *   - a row expiring much earlier would die while the account it names still has days to run,
 *     re-opening the divergence between rows and accounts that F-44 closed.
 *
 * At 7 days they are monotone instead. `childDeclaredAt` is stamped at `declareChildRegistration`,
 * strictly before the redeem → accept that mints the row, so `childDeclaredAt <= row.createdAt`.
 * The account becomes sweep-eligible at or before the row's expiry; the veto holds the sweep off
 * until this sweep retires the row; the next daily sweep then takes the account. There is no
 * ordering in which a live row points at a deleted account, and none in which an account is
 * deleted under a live decision.
 *
 * (24 hours — the other candidate — fails both halves: it expires the row while the account has
 * six days left, and it is still short enough to miss a single weekend, which is the human
 * failure mode that started this.)
 *
 * WHAT ELSE THE RETIREMENT HAS TO CARRY
 * -------------------------------------
 * Retiring the row is not one write. Three things become untrue at the same instant and are
 * therefore committed in ONE batch:
 *
 *   1. the row's `status`, to `expired` — inside the client's four-case enum (a status outside
 *      it is refused by `PendingJoinRequest(from:)` and would strand the row in the captain's
 *      queue forever), terminal, and deliberately NOT `declined`, which would tell the child
 *      their consent was refused when in truth nobody answered;
 *   2. FR-88's `users/{uid}.pendingFamilyRequest` stamp, which is the child's only readable
 *      answer to "is anyone deciding about me?" — leaving it standing is the exact permanent
 *      false positive FR-88 exists to kill, so expiry joins approve / decline / inactivate as
 *      a clearing path;
 *   3. the `accepted` invite the row was minted from. `liveFamilyInvitesFor` counts `accepted`
 *      as live, and `family.ts` already retires it on approve for this reason: left alive it
 *      keeps reading as an outstanding "awaiting approval" invitation on the requester's own
 *      dashboard — the same stale-surface complaint in a different window.
 */

import * as admin from "firebase-admin";
import {
  JOIN_REQUEST_PENDING_STATUS,
  PENDING_FAMILY_REQUEST_FIELD,
} from "./familyJoinRequestIntegrity";

type Firestore = admin.firestore.Firestore;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * How long a pending join request stays answerable. Pinned to
 * `PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS` by the argument in the module header; a test
 * asserts the two are equal so they cannot drift apart in a later edit.
 */
export const PENDING_JOIN_REQUEST_TTL_DAYS = 7;

/** Terminal status for a row nobody ever answered. See header point 1 for why not `declined`. */
export const JOIN_REQUEST_UNANSWERED_STATUS = "expired";

/**
 * Invite statuses that still read as live. Matches `liveFamilyInvitesFor` in `family.ts` —
 * `expired` and `declined` are terminal and are left alone.
 */
export const LIVE_INVITE_STATUSES = ["pending", "accepted"] as const;

/** Rows read per page. */
export const PENDING_JOIN_REQUEST_SWEEP_PAGE_SIZE = 100;
/** Upper bound on rows retired per run, so a backlog cannot blow the 5-minute job's timeout. */
export const PENDING_JOIN_REQUEST_SWEEP_MAX_RETIRED = 400;

export interface UnansweredJoinRequestSweepResult {
  scanned: number;
  retired: number;
  /** True when the per-run bound stopped the sweep early; the next run resumes. */
  truncated: boolean;
}

/** The `createdAt` before which a still-pending row is considered unanswered. */
export function unansweredJoinRequestCutoffMillis(
  nowMillis: number,
  ttlDays: number = PENDING_JOIN_REQUEST_TTL_DAYS
): number {
  return nowMillis - ttlDays * MS_PER_DAY;
}

function uniqueStrings(values: unknown[]): string[] {
  const out = new Set<string>();
  for (const value of values) {
    if (typeof value === "string" && value.length > 0) out.add(value);
  }
  return [...out];
}

/**
 * Retire every join request that has been awaiting a decision for longer than the window.
 *
 * SELF-QUENCHING rather than cursor-paged: each committed page moves its rows out of
 * `status == "pending"`, so re-running the same query from the start strictly shrinks the
 * matching set. That is simpler than a cursor and, unlike one, cannot skip a row that was
 * written while the sweep was mid-scan. Idempotent by the same property — a second run over a
 * clean population reads one empty page and writes nothing.
 */
export async function sweepUnansweredJoinRequests(
  db: Firestore,
  options: {
    cutoffMillis: number;
    pageSize?: number;
    maxRetired?: number;
  }
): Promise<UnansweredJoinRequestSweepResult> {
  const pageSize = options.pageSize ?? PENDING_JOIN_REQUEST_SWEEP_PAGE_SIZE;
  const maxRetired = options.maxRetired ?? PENDING_JOIN_REQUEST_SWEEP_MAX_RETIRED;
  const cutoff = admin.firestore.Timestamp.fromMillis(options.cutoffMillis);

  let scanned = 0;
  let retired = 0;
  let truncated = false;

  for (;;) {
    if (retired >= maxRetired) {
      truncated = true;
      break;
    }

    const snapshot = await db
      .collectionGroup("pending")
      .where("status", "==", JOIN_REQUEST_PENDING_STATUS)
      .where("createdAt", "<", cutoff)
      .orderBy("createdAt", "asc")
      .limit(pageSize)
      .get();

    if (snapshot.empty) break;
    scanned += snapshot.size;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: JOIN_REQUEST_UNANSWERED_STATUS,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const rows = snapshot.docs.map((doc) => doc.data() ?? {});

    // Deduped, because Firestore rejects a batch holding two writes to the same document and
    // one page can easily carry several rows for the same child (two families) — the same
    // hazard `inactivateFamily` handles with its `orphanedRequesterIds.delete(memberId)` dance.
    //
    // Existence-guarded, because `batch.update` on a missing document fails the WHOLE batch,
    // and a row whose account has since been deleted must stay a no-op rather than wedge the
    // sweep. Same guard, same reason, as the decline path.
    for (const userId of uniqueStrings(rows.map((row) => row.userId))) {
      const userRef = db.collection("users").doc(userId);
      const userDoc = await userRef.get();
      if (!userDoc.exists) continue;
      // Unconditional, exactly like approve / decline / inactivate. FR-88 documents the
      // accepted false negative (a child with live rows in two families carries one stamp), and
      // the field's whole contract is that it may only ever fail toward "nobody is deciding".
      batch.update(userRef, {
        [PENDING_FAMILY_REQUEST_FIELD]: admin.firestore.FieldValue.delete(),
      });
    }

    for (const inviteId of uniqueStrings(rows.map((row) => row.originInviteId))) {
      const inviteRef = db.collection("invites").doc(inviteId);
      const inviteDoc = await inviteRef.get();
      if (!inviteDoc.exists) continue;
      const status = inviteDoc.data()?.status;
      if (!LIVE_INVITE_STATUSES.includes(status as (typeof LIVE_INVITE_STATUSES)[number])) {
        continue;
      }
      batch.update(inviteRef, {
        status: "expired",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    retired += snapshot.size;

    if (snapshot.size < pageSize) break;
  }

  return { scanned, retired, truncated };
}
