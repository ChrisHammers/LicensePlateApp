/**
 * Child access guards — COPPA F-5b (FR-13, FR-14, FR-15, FR-24).
 *
 * The callable-side half of the enforcement sweep: one shared place that answers
 * "is this uid a child?" and throws the agreed, non-disclosing rejection.
 *
 * Two axes, deliberately distinct from F-5a's `assertNotUnconsentedChild`:
 *  - **Actor** (FR-24): `assertCallerIsNotChild` rejects EVERY child caller — consented or
 *    not. Stranger-contact initiation is outside `consentScope` even with a parent's
 *    consent, so this is strictly wider than the FR-28 unconsented-child gate and the two
 *    are layered, not substituted.
 *  - **Target** (FR-14): `assertTargetIsNotChild` rejects invites *aimed at* a child,
 *    reusing the privacy-opt-out wording verbatim so a sender learns nothing about the
 *    target. FR-15's narrower family-invite variant is applied inline in `family.ts`,
 *    where the target's user doc is already loaded (see `isChildWithActiveFamilyUserData`).
 *
 * Db-parameterized (like `assertNotUnconsentedChild`) so the whole matrix is unit-testable
 * against `testSupport/fakeFirestore.ts`. One `users/{uid}` read per guard; a missing doc
 * or missing flag means adult (§4).
 */

import * as functions from "firebase-functions";
import type * as admin from "firebase-admin";
import {
  CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
  CHILD_CALLER_REJECTION_REASON,
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
  isChildAccountUserData,
} from "./childAccountCore";

type Firestore = admin.firestore.Firestore;

async function loadUserData(
  db: Firestore,
  userId: string
): Promise<Record<string, unknown> | undefined> {
  const snapshot = await db.collection("users").doc(userId).get();
  return snapshot.data() as Record<string, unknown> | undefined;
}

/** `users/{uid}.isChildAccount == true`. Missing doc / missing flag ⇒ false. */
export async function isChildAccount(
  db: Firestore,
  userId: string
): Promise<boolean> {
  return isChildAccountUserData(await loadUserData(db, userId));
}

/**
 * FR-24: rejects a child CALLER on the stranger-contact callables
 * (`sendFriendInvite`, `sendFamilyInvite`, `createFamily`, `createShareCode`).
 *
 * Never applied to `redeemShareCode`, `respondToFamilyInvite_UserStep` or `deleteAccount`
 * — those are a child's path back into consented play and out of the system.
 */
export async function assertCallerIsNotChild(
  db: Firestore,
  userId: string
): Promise<void> {
  if (await isChildAccount(db, userId)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
      { reason: CHILD_CALLER_REJECTION_REASON }
    );
  }
}

/**
 * FR-14: rejects a child TARGET outright (`sendFriendInvite`). Friendship is stranger
 * contact by definition — there is no family carve-out that makes it acceptable.
 */
export async function assertTargetIsNotChild(
  db: Firestore,
  userId: string
): Promise<void> {
  if (await isChildAccount(db, userId)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      CHILD_TARGET_NOT_SEARCHABLE_MESSAGE
    );
  }
}
