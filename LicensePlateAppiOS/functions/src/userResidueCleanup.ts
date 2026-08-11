/**
 * Shared, db-parameterized cleanup primitives — COPPA F-5a.
 *
 * Extracted here (rather than living inline in `accountDeletion.ts`) because the child
 * flag-set pipeline (FR-4 / FR-36) reuses the exact same machinery:
 *  - `removeAllFriendEdgesForUser` — deletes both directions of `friends` edges and
 *    decrements `friendCount` on the surviving side (previously inline in deleteAccount).
 *  - `searchIndexHintsForUser` — the username/email/phone hints `clearAllSearchIndexesForUser`
 *    needs, resolved from `users/{uid}` + `users/{uid}/private/contact`.
 *  - `expireOutOfFamilyPendingInvitesForChild` — FR-36: pending friend/family/trip invites
 *    targeting a newly flagged child from senders OUTSIDE the child's family flip to
 *    "expired" (reusing the `expiration.ts` status-flip semantics; the retention job hard
 *    deletes them later).
 *
 * Everything here is idempotent: re-running against an already-clean store finds nothing.
 */

import * as admin from "firebase-admin";
import {
  decrementedFriendCount,
  otherFriendUserId,
} from "./accountDeletionCore";
import { PRIVATE_CONTACT_DOC } from "./userSearchIndex";
import {
  normalizeEmail,
  normalizePhoneE164,
  normalizeUsernameLower,
} from "./userSearchCore";

type Firestore = admin.firestore.Firestore;

/**
 * Delete every `friends` edge naming `userId` (either side) and decrement the other
 * side's `friendCount`. Returns the number of removed edges. Per-edge batches keep the
 * operation resumable — a crash mid-way leaves the remaining edges discoverable.
 */
export async function removeAllFriendEdgesForUser(
  db: Firestore,
  userId: string
): Promise<number> {
  const [edgesAsA, edgesAsB] = await Promise.all([
    db.collection("friends").where("userA", "==", userId).get(),
    db.collection("friends").where("userB", "==", userId).get(),
  ]);
  const edgeDocsByPath = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const doc of [...edgesAsA.docs, ...edgesAsB.docs]) {
    edgeDocsByPath.set(doc.ref.path, doc);
  }

  let removedFriendEdgeCount = 0;
  for (const edgeDoc of edgeDocsByPath.values()) {
    const batch = db.batch();
    batch.delete(edgeDoc.ref);

    const otherUserId = otherFriendUserId(edgeDoc.data(), userId);
    if (otherUserId) {
      const otherUserRef = db.collection("users").doc(otherUserId);
      const otherUserDoc = await otherUserRef.get();
      if (otherUserDoc.exists) {
        batch.update(otherUserRef, {
          friendCount: decrementedFriendCount(otherUserDoc.data()?.friendCount),
        });
      }
    }

    await batch.commit();
    removedFriendEdgeCount += 1;
  }
  return removedFriendEdgeCount;
}

export interface SearchIndexHints {
  userNameLower: string | null;
  emailLower: string | null;
  phoneE164: string | null;
}

/**
 * Resolve the hints `clearAllSearchIndexesForUser` needs. Contact identifiers live in
 * `users/{uid}/private/contact` (FR-43); legacy top-level fields remain as fallbacks
 * for older dev docs.
 */
export async function searchIndexHintsForUser(
  db: Firestore,
  userId: string,
  userData: Record<string, unknown>
): Promise<SearchIndexHints> {
  const contactDoc = await db
    .collection("users")
    .doc(userId)
    .collection("private")
    .doc(PRIVATE_CONTACT_DOC)
    .get();
  const contactData = contactDoc.data() ?? {};

  const emailHint =
    (typeof contactData.email === "string" ? contactData.email : null) ??
    (typeof userData.email === "string" ? userData.email : null);
  const phoneHint =
    (typeof contactData.phoneNumber === "string" ? contactData.phoneNumber : null) ??
    (typeof userData.phoneNumber === "string" ? userData.phoneNumber : null);

  return {
    userNameLower:
      (typeof userData.userNameLower === "string" ? userData.userNameLower : null) ??
      (typeof userData.userName === "string"
        ? normalizeUsernameLower(userData.userName)
        : null),
    emailLower:
      typeof contactData.emailLower === "string"
        ? contactData.emailLower
        : emailHint
          ? normalizeEmail(emailHint)
          : null,
    phoneE164:
      typeof contactData.phoneE164 === "string"
        ? contactData.phoneE164
        : phoneHint
          ? normalizePhoneE164(phoneHint)
          : null,
  };
}

/**
 * FR-36: expire pending `invites` (friend + family types) and `trip_invites` that target
 * the child and were sent by someone outside the child's family. In-family invites stay:
 * family-only play is the child's permitted surface.
 */
export async function expireOutOfFamilyPendingInvitesForChild(
  db: Firestore,
  input: { childUserId: string; familyMemberIds: readonly string[] }
): Promise<number> {
  const familyMembers = new Set(input.familyMemberIds);
  let expiredCount = 0;

  const invitesSnap = await db
    .collection("invites")
    .where("toUserId", "==", input.childUserId)
    .where("status", "==", "pending")
    .get();
  const inviteBatch = db.batch();
  let inviteOps = 0;
  for (const doc of invitesSnap.docs) {
    const fromUserId = doc.data().fromUserId;
    if (typeof fromUserId === "string" && familyMembers.has(fromUserId)) {
      continue;
    }
    // Mirrors expiration.ts: invites flip status only.
    inviteBatch.update(doc.ref, { status: "expired" });
    inviteOps += 1;
  }
  if (inviteOps > 0) {
    await inviteBatch.commit();
    expiredCount += inviteOps;
  }

  const tripInvitesSnap = await db
    .collection("trip_invites")
    .where("toUserId", "==", input.childUserId)
    .where("status", "==", "pending")
    .get();
  const tripBatch = db.batch();
  let tripOps = 0;
  for (const doc of tripInvitesSnap.docs) {
    const fromUserId = doc.data().fromUserId;
    if (typeof fromUserId === "string" && familyMembers.has(fromUserId)) {
      continue;
    }
    // Mirrors expiration.ts: trip invites also stamp respondedAt.
    tripBatch.update(doc.ref, {
      status: "expired",
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tripOps += 1;
  }
  if (tripOps > 0) {
    await tripBatch.commit();
    expiredCount += tripOps;
  }

  return expiredCount;
}
