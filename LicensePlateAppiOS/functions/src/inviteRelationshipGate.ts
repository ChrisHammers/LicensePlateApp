/**
 * Trip-invite relationship gate — COPPA remediation FR-47 (F-10, audit F2 remainder).
 *
 * `sendTripInvite` may only target someone the sender already has a relationship with:
 * an accepted friendship edge, or shared membership of the same active family. This is the
 * server-side enforcement of a policy the client has always applied on its own — the invite
 * picker builds its candidate list from friends ∪ family and nothing else
 * (`InvitePlayersViewModel.loadCandidates`) — so no legitimate flow changes shape. What
 * changes is that a hand-rolled call can no longer reach a stranger.
 *
 * WHY THE REJECTION REUSES THE CHILD-TARGET WORDING
 * -------------------------------------------------
 * This is the subtle part, and it is deliberate. FR-24 requires that a sender can never tell
 * "this account is a child" apart from "this account opted out of contact search", which is
 * why a child target is refused with `CHILD_TARGET_NOT_SEARCHABLE_MESSAGE`. Introducing a
 * *distinct* rejection for "not friends or family" would have re-opened exactly that oracle
 * from the other side: on this surface, post-FR-47, an adult stranger would produce the new
 * wording while a child stranger still produced the "not searchable" wording — so any
 * difference between the two replies would identify the target as a child.
 *
 * So both refusals are byte-identical: same `permission-denied` code, same message, and no
 * `details` payload on either (a `details.reason` here would leak through the same channel).
 * `assertTripInviteRelationship` therefore throws the child-target error verbatim, and
 * `inviteRelationshipGate.test.ts` pins the two against each other.
 *
 * Ordering: the FR-13/24/38 child checks in `tripInvites.ts` run BEFORE this gate and are
 * unchanged — a child-target or family-only-trip rejection always wins. This gate only ever
 * decides cases the child rules already allowed.
 *
 * Db-parameterized for `testSupport/fakeFirestore.ts`. Cost: one `friends` doc read, and for
 * a non-friend, two `users` reads plus two family-member reads.
 */

import * as functions from "firebase-functions";
import type * as admin from "firebase-admin";
import { CHILD_TARGET_NOT_SEARCHABLE_MESSAGE } from "./childAccountCore";

type Firestore = admin.firestore.Firestore;

/**
 * Canonical `friends/{id}` document id: the two uids sorted and joined. Exported so
 * `friends.ts` and this gate can never drift onto different id schemes — a divergence would
 * silently make the gate read the wrong document and refuse real friends.
 */
export function friendshipEdgeId(userA: string, userB: string): string {
  const sorted = [userA, userB].sort();
  return `${sorted[0]}_${sorted[1]}`;
}

function activeFamilyIdOf(data: Record<string, unknown> | undefined): string | null {
  const familyId = data?.activeFamilyId;
  return typeof familyId === "string" && familyId.length > 0 ? familyId : null;
}

/** An `accepted` edge in either direction. Pending invites do not count as a relationship. */
export async function hasAcceptedFriendship(
  db: Firestore,
  userA: string,
  userB: string
): Promise<boolean> {
  const snapshot = await db
    .collection("friends")
    .doc(friendshipEdgeId(userA, userB))
    .get();
  return snapshot.exists && snapshot.data()?.status === "accepted";
}

/**
 * Both users name the same `activeFamilyId` AND both still hold a member doc in it.
 *
 * The membership docs are the authority; `activeFamilyId` alone is a user-doc projection
 * that can outlive a removal, and treating it as sufficient would let a removed member keep
 * inviting the family they were just taken out of.
 */
export async function sharesActiveFamily(
  db: Firestore,
  userA: string,
  userB: string
): Promise<boolean> {
  const [snapshotA, snapshotB] = await Promise.all([
    db.collection("users").doc(userA).get(),
    db.collection("users").doc(userB).get(),
  ]);

  const familyIdA = activeFamilyIdOf(snapshotA.data() as Record<string, unknown> | undefined);
  const familyIdB = activeFamilyIdOf(snapshotB.data() as Record<string, unknown> | undefined);
  if (familyIdA === null || familyIdB === null || familyIdA !== familyIdB) {
    return false;
  }

  const [memberA, memberB] = await Promise.all([
    db.collection(`families/${familyIdA}/members`).doc(userA).get(),
    db.collection(`families/${familyIdA}/members`).doc(userB).get(),
  ]);
  return memberA.exists && memberB.exists;
}

/** FR-47: accepted friendship OR shared active family. */
export async function hasFriendshipOrFamilyRelationship(
  db: Firestore,
  userA: string,
  userB: string
): Promise<boolean> {
  if (await hasAcceptedFriendship(db, userA, userB)) return true;
  return sharesActiveFamily(db, userA, userB);
}

/**
 * FR-47: refuse a trip invite aimed at someone the sender has no relationship with.
 *
 * Throws the child-target rejection verbatim — see the module header for why the two must be
 * indistinguishable.
 */
export async function assertTripInviteRelationship(
  db: Firestore,
  fromUserId: string,
  toUserId: string
): Promise<void> {
  if (await hasFriendshipOrFamilyRelationship(db, fromUserId, toUserId)) {
    return;
  }
  throw new functions.https.HttpsError(
    "permission-denied",
    CHILD_TARGET_NOT_SEARCHABLE_MESSAGE
  );
}
