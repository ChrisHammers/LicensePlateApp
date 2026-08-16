/**
 * COPPA FR-60(c) + FR-77 — the redemption-window account and how it stops existing.
 *
 * Under FR-60's local-first model an under-13 player has no backend identity at all until
 * they enter a share code. That one act mints an anonymous uid, declares it, and redeems —
 * so from then until the captain decides there is a real `users/{uid}` on the server for a
 * child nobody has consented for. That window is measured in minutes to days, and FR-60(c)
 * requires it to close by DELETION rather than by aging into the general child population:
 *
 *   - declined  → `approveFamilyJoinRequest_CaptainStep`'s decline branch deletes inline;
 *   - expired   → `expireInvitesAndCodes` deletes when the family invite times out unaccepted;
 *   - anything the two inline paths missed → the 7-day scheduled backstop in `retention.ts`.
 *
 * THE ONE ACCOUNT THIS MUST NEVER TOUCH is the sticky post-revocation child (FR-28): a child
 * who WAS consented and then had it revoked keeps `isChildAccount: true` with no
 * `activeFamilyId` — byte-identical to a provisional child on those two fields alone. They
 * are entitled to the FR-28 restricted state and the OD-3 retention window, and deleting
 * their data as "transient residue" would destroy the very history the parent's deletion
 * offer (FR-63(a)) exists to let the parent decide about. `wasEverInFamily` is what tells
 * them apart — it is server-written on every membership grant and never cleared — and
 * `childDeclaredAt` is a second, independent guard: it is deleted at admission, so a child
 * who ever reached a family is invisible to the sweep even if `wasEverInFamily` were lost.
 *
 * THE OTHER ACCOUNT THIS MUST NEVER TOUCH (added 2026-08-16 after the device pass) is one
 * whose captain has not answered yet — see `hasLiveJoinRequest`. Every route in here fires on
 * "the decision is in, or is never coming"; a still-pending row means neither, and deleting
 * then leaves the captain a request they can never approve.
 *
 * The device-local age answer and ratchet survive all of this untouched: the protection is
 * device-scoped, not account-scoped, so a declined child re-enters a fresh code later and
 * re-provisions cleanly as a child.
 */

import * as admin from "firebase-admin";
import { isUnconsentedChildUserData } from "./childAccountCore";
import {
  executeAccountDeletionForUser,
  type AccountDeletionDeps,
} from "./accountDeletion";
import type { ClientMetadata } from "./clientMetadata";

type Firestore = admin.firestore.Firestore;

/**
 * Server-owned marker stamped by `declareChildRegistration` and deleted at family admission.
 * Its presence IS "this account is inside its redemption window"; it is the sweep's cursor
 * field, and it is listed in `firestore.rules`' server-controlled key guard so no client can
 * forge or clear it.
 *
 * A server timestamp is required rather than the doc's `createdAt`: `createdAt` is
 * client-supplied from the local `AppUser`, which under FR-60 was created the day the app
 * was installed — possibly months before the child ever entered a code. Sweeping on that
 * would delete a legitimately-just-provisioned account on its first night.
 */
export const CHILD_DECLARED_AT_FIELD = "childDeclaredAt";

/** FR-77: backstop window for redemption-window accounts the inline paths missed. */
export const PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS = 7;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * A child account that has NEVER been consented for: flagged, no active family, and no
 * membership anywhere in its history.
 *
 * `wasEverInFamily` is the whole discrimination (see the module header). It is set true by
 * `familyMembershipGrantUserUpdate` at admission and by `familyMembershipLeaveUserUpdate` on
 * every exit, and nothing ever sets it back to false — so `!== true` means "no family has
 * ever admitted this account", which is exactly FR-60(c)'s never-consented population.
 */
export function isNeverConsentedProvisionalChildUserData(
  data: Record<string, unknown> | undefined | null
): boolean {
  return isUnconsentedChildUserData(data) && data?.wasEverInFamily !== true;
}

/** Redemption-window accounts declared strictly before this instant are swept. */
export function provisionalChildDeletionCutoffMillis(
  nowMillis: number,
  windowDays: number = PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS
): number {
  return nowMillis - windowDays * MS_PER_DAY;
}

export interface ProvisionalChildCleanupDeps {
  /**
   * Deletes the Firebase Auth user. Injected (rather than calling `admin.auth()` directly)
   * so the whole path runs against `FakeFirestore` in unit tests, and so a missing-user
   * error can be swallowed as the no-op it is.
   */
  deleteAuthUser: (userId: string) => Promise<void>;
  accountDeletionDeps?: AccountDeletionDeps;
}

const liveDeps: ProvisionalChildCleanupDeps = {
  deleteAuthUser: async (userId: string) => {
    try {
      await admin.auth().deleteUser(userId);
    } catch (error) {
      // Idempotence: a retry after a partial run finds the auth user already gone.
      if ((error as { code?: string }).code !== "auth/user-not-found") {
        throw error;
      }
    }
  },
};

export interface ProvisionalChildCleanupResult {
  deleted: boolean;
  /** Why the account was left alone — for logs and for the tests that pin the carve-out. */
  reason:
    | "deleted"
    | "not_provisional_child"
    | "no_user_doc"
    | "live_join_request";
}

/**
 * Is a captain still holding an undecided consent request for this account?
 *
 * THE THIRD CARVE-OUT, added after the 2026-08-16 device pass. The two the module header
 * describes are both about WHO the account belongs to; this one is about WHEN. A
 * redemption-window account is deletable because "there is no captain decision coming"
 * (`expiration.ts`) or because one just arrived and refused (`family.ts`). Neither is true
 * while a row sits pending, and every path into here could reach one that was:
 *
 *   - invite expiry — a child who redeemed the same code twice left one invite unaccepted;
 *     it lapses on the 15-minute TTL and this cleanup fired, deleting the account out from
 *     under the OTHER invite's live pending row. No captain acted at all;
 *   - a decline that resolved one duplicate row while a sibling row was still pending;
 *   - the FR-77 backstop reaching an account whose captain simply took longer than 7 days.
 *
 * In each case the deletion strands a row the captain can then never approve ("User not
 * found") — the exact unrecoverable state FR-66(a) keeps the decline branch open to avoid.
 *
 * Fail-safe on error, like every other ambiguity in this module: if the query itself fails
 * (a not-yet-built collection-group index, a transient outage) we answer "yes, there might
 * be one" and skip the deletion. The FR-77 backstop re-attempts later, and the decline and
 * expiry callers already treat a skip as non-fatal.
 */
async function hasLiveJoinRequest(
  db: Firestore,
  userId: string
): Promise<boolean> {
  try {
    const snapshot = await db
      .collectionGroup("pending")
      .where("userId", "==", userId)
      .where("status", "==", "pending")
      .limit(1)
      .get();
    return !snapshot.empty;
  } catch (error) {
    console.error(
      `FR-60(c): could not check live join requests for ${userId}; skipping deletion`,
      error
    );
    return true;
  }
}

/**
 * Deletes `userId` outright IF — and only if — it is a never-consented provisional child.
 *
 * Reuses `executeAccountDeletionForUser` rather than a bespoke delete: FR-60(c) says "via the
 * existing deletion machinery", and that function is already the one place that knows every
 * uid-keyed location (search indexes, private subcollection, progression, achievements,
 * public stats, rate-limit counters, shared-residue de-identification). It is idempotent, so
 * a retry after a partial failure re-enters from the top and finds nothing left to do.
 *
 * Ordering matches `deleteAccount`: Firestore first, Firebase Auth user LAST, so a failed
 * cleanup leaves the account still addressable and the whole operation retryable.
 *
 * NOT deleted: the uid-only `AUDIT_CHILD_REGISTRATION_DECLARED` row. That row carries no
 * personal information and FR-77 keeps the consent/lifecycle audit types exempt from every
 * retention path — it is the §312.5 evidence that the declaration happened, not residue.
 */
export async function deleteProvisionalChildAccountIfNeverConsented(
  db: Firestore,
  input: {
    userId: string;
    actorId: string;
    clientMetadata: ClientMetadata | null;
    revenueCatApiKey?: string | null;
  },
  deps: ProvisionalChildCleanupDeps = liveDeps
): Promise<ProvisionalChildCleanupResult> {
  const snapshot = await db.collection("users").doc(input.userId).get();
  if (!snapshot.exists) {
    return { deleted: false, reason: "no_user_doc" };
  }
  if (!isNeverConsentedProvisionalChildUserData(snapshot.data())) {
    return { deleted: false, reason: "not_provisional_child" };
  }
  // ORDERING, and it is load-bearing. `isNeverConsentedProvisionalChildUserData` reads
  // `activeFamilyId` / `wasEverInFamily`, both of which an APPROVAL writes in the same batch
  // as the membership grant — so an approved child is already invisible here the instant that
  // batch commits, and callers must always commit before calling this. What the predicate
  // cannot see is a decision that has not been made yet: that is the check below.
  if (await hasLiveJoinRequest(db, input.userId)) {
    return { deleted: false, reason: "live_join_request" };
  }

  await executeAccountDeletionForUser(
    db,
    {
      userId: input.userId,
      actorId: input.actorId,
      clientMetadata: input.clientMetadata,
      revenueCatApiKey: input.revenueCatApiKey ?? null,
    },
    deps.accountDeletionDeps
  );
  await deps.deleteAuthUser(input.userId);

  return { deleted: true, reason: "deleted" };
}

export interface ProvisionalChildSweepResult {
  scanned: number;
  deleted: number;
  /** Scanned but left alone (already consented, or admitted since the marker was written). */
  skipped: number;
  /** True when the per-run bound stopped the sweep early; the next run resumes. */
  truncated: boolean;
}

/** Upper bound on deletions per sweep so a backlog cannot blow the function timeout. */
export const PROVISIONAL_CHILD_SWEEP_MAX_DELETES = 200;
/** Upper bound on documents read per sweep. */
export const PROVISIONAL_CHILD_SWEEP_MAX_SCANNED = 2000;
/** Page size for the cursor-paged scan. */
export const PROVISIONAL_CHILD_SWEEP_PAGE_SIZE = 100;

/**
 * FR-77 backstop: delete every redemption-window account whose declaration is older than the
 * window and which no family ever admitted.
 *
 * Single-field inequality + `orderBy` on the same field, so Firestore serves it from the
 * automatic single-field index — no composite index to deploy. Cursor-paged and idempotent
 * for the same reasons `purgeDocumentsOlderThan` is; a second run over a clean population
 * reads one empty page and deletes nothing.
 *
 * The `isNeverConsentedProvisionalChildUserData` re-check is not redundant with the query:
 * the marker is deleted at admission, but a doc can be admitted between the page read and
 * the delete, and `deleteProvisionalChildAccountIfNeverConsented` re-reads the doc anyway.
 * Fail-safe by construction — every ambiguity resolves toward NOT deleting.
 */
export async function sweepExpiredProvisionalChildAccounts(
  db: Firestore,
  options: {
    cutoffMillis: number;
    actorId: string;
    revenueCatApiKey?: string | null;
    maxDeletes?: number;
    maxScanned?: number;
    pageSize?: number;
  },
  deps: ProvisionalChildCleanupDeps = liveDeps
): Promise<ProvisionalChildSweepResult> {
  const maxDeletes = options.maxDeletes ?? PROVISIONAL_CHILD_SWEEP_MAX_DELETES;
  const maxScanned = options.maxScanned ?? PROVISIONAL_CHILD_SWEEP_MAX_SCANNED;
  const pageSize = options.pageSize ?? PROVISIONAL_CHILD_SWEEP_PAGE_SIZE;
  const cutoff = admin.firestore.Timestamp.fromMillis(options.cutoffMillis);

  let scanned = 0;
  let deleted = 0;
  let skipped = 0;
  let truncated = false;
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    if (deleted >= maxDeletes || scanned >= maxScanned) {
      truncated = true;
      break;
    }

    let query: admin.firestore.Query = db
      .collection("users")
      .where(CHILD_DECLARED_AT_FIELD, "<", cutoff)
      .orderBy(CHILD_DECLARED_AT_FIELD, "asc")
      .limit(pageSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
    scanned += snapshot.size;

    for (const doc of snapshot.docs) {
      const outcome = await deleteProvisionalChildAccountIfNeverConsented(
        db,
        {
          userId: doc.id,
          actorId: options.actorId,
          clientMetadata: null,
          revenueCatApiKey: options.revenueCatApiKey ?? null,
        },
        deps
      );
      if (outcome.deleted) {
        deleted += 1;
      } else {
        skipped += 1;
      }
    }

    if (snapshot.size < pageSize) {
      break;
    }
  }

  return { scanned, deleted, skipped, truncated };
}
