/**
 * Family-only trips for children — COPPA F-5b (FR-38, with FR-13 / FR-24 falling out of it).
 *
 * ONE invariant, evaluated over the *prospective* roster (current participants + whoever is
 * about to join):
 *
 *   for every child C in the roster, every other member of the roster is a member of C's
 *   active family.
 *
 * Both directions of FR-38 and both actor cases are corollaries, which is why this is a
 * single rule rather than four:
 *  - invite aimed at a child          ⇒ C is the joiner; sender + every existing
 *                                        participant must be in C's family (FR-13);
 *  - invite aimed at anyone else into a trip that already holds a child
 *                                      ⇒ C is an existing participant; the new user must be
 *                                        in C's family;
 *  - a child SENDING an invite         ⇒ C is the sender; the target must be in C's family
 *                                        (FR-24);
 *  - accept/response re-verification   ⇒ same call with the roster as it stands now, so a
 *                                        roster that changed between send and accept cannot
 *                                        launder a mixed trip.
 *
 * An UNCONSENTED child (flag true, no active family) has no family, so every multi-party
 * roster containing them fails — which is the FR-28 posture expressed in trip terms.
 *
 * Db-parameterized for `fakeFirestore.ts`. Cost is bounded by roster size: one members
 * listing, one `users/{uid}` read per participant, and one family-members listing per
 * distinct child family (cached). Adults-only trips pay the roster reads and nothing else.
 */

import type * as admin from "firebase-admin";
import { isChildAccountUserData } from "./childAccountCore";

type Firestore = admin.firestore.Firestore;

export type TripChildParticipationRejection =
  /** The user about to join is the child whose family the roster violates. */
  | { kind: "child_joiner"; childUserId: string }
  /** Someone already on the roster (possibly the sender) is that child. */
  | { kind: "child_participant"; childUserId: string };

function activeFamilyIdOf(data: Record<string, unknown> | undefined): string | null {
  const familyId = data?.activeFamilyId;
  return typeof familyId === "string" && familyId.length > 0 ? familyId : null;
}

/**
 * Returns `null` when the prospective roster is allowed, or the reason it is not.
 *
 * `additionalParticipantIds` covers participants that are guaranteed to be on the roster
 * but may not have a `members` doc yet — specifically the sender of a brand-new trip,
 * whose owner row `sendTripInvite` creates in the same batch as the invite.
 */
export async function evaluateTripChildParticipation(
  db: Firestore,
  input: {
    tripSessionId: string;
    joiningUserId: string;
    additionalParticipantIds?: readonly string[];
  }
): Promise<TripChildParticipationRejection | null> {
  const membersSnapshot = await db
    .collection(`trip_sessions/${input.tripSessionId}/members`)
    .get();

  const rosterIds = new Set<string>(membersSnapshot.docs.map((doc) => doc.id));
  for (const id of input.additionalParticipantIds ?? []) {
    rosterIds.add(id);
  }
  rosterIds.add(input.joiningUserId);

  const orderedIds = [...rosterIds];
  const userSnapshots = await Promise.all(
    orderedIds.map((id) => db.collection("users").doc(id).get())
  );

  const childFamilyByUserId = new Map<string, string | null>();
  orderedIds.forEach((id, index) => {
    const data = userSnapshots[index].data() as Record<string, unknown> | undefined;
    if (isChildAccountUserData(data)) {
      childFamilyByUserId.set(id, activeFamilyIdOf(data));
    }
  });

  if (childFamilyByUserId.size === 0) {
    return null;
  }

  // Evaluate the joiner first so a caller inviting a child gets the non-disclosing
  // `child_joiner` reason even when the roster also violates some other child's family.
  const evaluationOrder = [
    ...(childFamilyByUserId.has(input.joiningUserId) ? [input.joiningUserId] : []),
    ...orderedIds.filter((id) => id !== input.joiningUserId),
  ];

  const familyMemberIdsByFamilyId = new Map<string, Set<string>>();

  for (const childUserId of evaluationOrder) {
    if (!childFamilyByUserId.has(childUserId)) continue;

    const otherIds = orderedIds.filter((id) => id !== childUserId);
    if (otherIds.length === 0) continue; // solo trip — nobody to be exposed to

    const rejection: TripChildParticipationRejection =
      childUserId === input.joiningUserId
        ? { kind: "child_joiner", childUserId }
        : { kind: "child_participant", childUserId };

    const familyId = childFamilyByUserId.get(childUserId) ?? null;
    if (familyId === null) {
      return rejection; // unconsented child: no family, so no shared trip
    }

    let familyMemberIds = familyMemberIdsByFamilyId.get(familyId);
    if (!familyMemberIds) {
      const familyMembersSnapshot = await db
        .collection(`families/${familyId}/members`)
        .get();
      familyMemberIds = new Set(familyMembersSnapshot.docs.map((doc) => doc.id));
      familyMemberIdsByFamilyId.set(familyId, familyMemberIds);
    }

    if (otherIds.some((id) => !familyMemberIds!.has(id))) {
      return rejection;
    }
  }

  return null;
}
