/**
 * FR-69 (F-25, audit H-9) — child-trip invariants are MAINTAINED, not just checked at
 * transitions.
 *
 * `evaluateTripChildParticipation` (FR-38 / F-5b) is the one rule: for every child C on a
 * trip roster, every other member of that roster is a member of C's active family. Until
 * now it was evaluated only when someone tried to change a roster — at invite send and at
 * accept. Rosters, though, also go illegal without anyone touching them:
 *
 *  - (a) a player already mid-trip with strangers is FLAGGED as a child. Nothing about the
 *        trip changed; the child did. Every other participant is now someone the child may
 *        not play with.
 *  - (b) a family member EXITS the family while a live trip holds that family's child. The
 *        ex-member keeps their roster row and keeps playing alongside the child they are no
 *        longer family to.
 *
 * Both are repaired here, at the moment the state changes, so the invariant holds for live
 * trips continuously rather than only at the send/accept seams.
 *
 * ## What "repair" means
 *
 * The subject of the change loses live participation: their `members/{uid}` row goes (that
 * row IS the access grant — `isTripSessionMember` in `firestore.rules` reads nothing else),
 * `canonicalParticipants` loses them, and a `participant_left` event records the departure.
 * Their earlier events stay exactly as they are, attributed to them: they legitimately
 * co-produced that history while they were on the roster, and de-identifying it is
 * deletion's job (FR-50), not this sweep's.
 *
 * When the subject OWNS the trip there is no such row to pull: ending is owner-gated, so a
 * trip whose owner is removed strands every survivor with a session nobody can close (the
 * reasoning `deidentifyUserResidue` already records for a deleted owner). FR-69 states the
 * disposition for case (a) — "end the trip if the child owns it" — and case (b) inherits it
 * for the same mechanical reason.
 *
 * ## Scope discipline
 *
 * - LIVE trips only (`created` / `active`). Historical ended trips are out of scope per
 *   FR-69: they were lawful when played, and deletion/retention cover them.
 * - Only sessions where the subject currently holds a roster row. The sweep's blast radius
 *   is the state change that triggered it; a violation on a trip the subject is not on has
 *   its own trigger.
 * - The subject is always removable by construction: in (a) they are the newly flagged
 *   child, in (b) they are the ex-member — precisely the party FR-69 names. Where a roster
 *   is violating for an additional, pre-existing reason, removing the subject still strictly
 *   reduces the child's exposure, which is the fail-closed direction.
 *
 * Session discovery reuses `discoverAffectedSessionIds` — the same collection-group queries
 * the deletion sweep and the FR-61 review inventory use, so trip coverage cannot drift
 * between the three, and no new index is required.
 *
 * Db-parameterized for `fakeFirestore.ts`. Idempotent: every action is keyed on a
 * deterministic event id and predicated on state it clears, so a re-run writes nothing.
 */

import type * as admin from "firebase-admin";
import { discoverAffectedSessionIds } from "./accountDeletionDeidentify";
import { evaluateTripChildParticipation } from "./tripChildParticipation";
import {
  endLiveTripSession,
  isLiveTripSessionData,
  removeParticipantFromLiveTripRoster,
} from "./tripRosterWrites";

type Firestore = admin.firestore.Firestore;

/** FR-69(a): the child was flagged mid-trip. */
export const CHILD_TRIP_LEAVE_REASON_FLAG_SET = "child_flag_set";
/** FR-69(b): a family membership ended under a live trip holding that family's child. */
export const CHILD_TRIP_LEAVE_REASON_FAMILY_EXIT = "family_membership_ended";

export interface ChildTripInvariantSweepResult {
  /** Live sessions the subject still holds a roster row on. */
  scannedLiveSessionCount: number;
  /** Sessions the subject was removed from. */
  removedFromSessionCount: number;
  /** Sessions ended because the subject owned them. */
  endedSessionCount: number;
}

const EMPTY_RESULT: ChildTripInvariantSweepResult = {
  scannedLiveSessionCount: 0,
  removedFromSessionCount: 0,
  endedSessionCount: 0,
};

/** Deterministic ids: one row per (cause, user, trip), so re-runs overwrite. */
function leaveEventId(leaveReason: string, userId: string): string {
  return `coppa-left-${leaveReason}-${userId}`;
}

function endEventId(leaveReason: string, userId: string): string {
  return `trip-ended-${leaveReason}-${userId}`;
}

/**
 * Re-evaluate every LIVE trip `subjectUserId` is on and repair the ones the FR-38 invariant
 * no longer holds for, by removing the subject (or ending the trip they own).
 */
export async function enforceChildTripInvariantsForUser(
  db: Firestore,
  input: { subjectUserId: string; leaveReason: string }
): Promise<ChildTripInvariantSweepResult> {
  const { subjectUserId, leaveReason } = input;
  const result: ChildTripInvariantSweepResult = { ...EMPTY_RESULT };

  const sessionIds = await discoverAffectedSessionIds(db, subjectUserId);

  for (const tripSessionId of sessionIds) {
    const sessionRef = db.collection("trip_sessions").doc(tripSessionId);
    const [sessionSnapshot, memberSnapshot] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection("members").doc(subjectUserId).get(),
    ]);

    // Discovery is deliberately wide (events, prefs, invites), so most hits are trips that
    // are over, or that the subject was only invited to. Neither is this sweep's business.
    if (!sessionSnapshot.exists || !isLiveTripSessionData(sessionSnapshot.data())) {
      continue;
    }
    if (!memberSnapshot.exists) {
      continue;
    }
    result.scannedLiveSessionCount += 1;

    // The subject is already on the roster, so passing them as the joiner adds nobody: this
    // is the stored roster evaluated as it stands — the standing form of the same rule the
    // invite paths run prospectively.
    const rejection = await evaluateTripChildParticipation(db, {
      tripSessionId,
      joiningUserId: subjectUserId,
    });
    if (rejection === null) {
      continue;
    }

    const ownsTrip =
      memberSnapshot.data()?.role === "owner" ||
      sessionSnapshot.data()?.createdBy === subjectUserId;

    if (ownsTrip) {
      await endLiveTripSession(db, {
        tripSessionId,
        endedBy: subjectUserId,
        reason: leaveReason,
        eventId: endEventId(leaveReason, subjectUserId),
      });
      result.endedSessionCount += 1;
      continue;
    }

    const removed = await removeParticipantFromLiveTripRoster(db, {
      tripSessionId,
      userId: subjectUserId,
      leaveReason,
      eventId: leaveEventId(leaveReason, subjectUserId),
    });
    if (removed) {
      result.removedFromSessionCount += 1;
    }
  }

  return result;
}

/**
 * FR-69(a). Called from `applyChildProtectionsAfterFlagSet`, so it runs on every path that
 * sets the authoritative child flag: manager set, family admission, and guardian
 * confirmation.
 */
export async function sweepChildTripsAfterFlagSet(
  db: Firestore,
  childUserId: string
): Promise<ChildTripInvariantSweepResult> {
  return enforceChildTripInvariantsForUser(db, {
    subjectUserId: childUserId,
    leaveReason: CHILD_TRIP_LEAVE_REASON_FLAG_SET,
  });
}

/**
 * FR-69(b). Called from the family-membership exit paths that leave the account standing:
 * `removeFamilyMember` (including self-leave), `inactivateFamily`, and the member-flag
 * consent expiry. The deletion paths need no call — `deidentifyUserResidue` already takes
 * the deleted user off every roster and ends the live trips they owned, which restores the
 * same invariant.
 *
 * Works for either side of the exit: a departing ADULT is the outsider and loses their row;
 * a departing CHILD has no family left, so every multi-party roster holding them is illegal
 * and it is the child who leaves.
 */
export async function sweepLiveTripsAfterFamilyMembershipExit(
  db: Firestore,
  exitingUserId: string
): Promise<ChildTripInvariantSweepResult> {
  return enforceChildTripInvariantsForUser(db, {
    subjectUserId: exitingUserId,
    leaveReason: CHILD_TRIP_LEAVE_REASON_FAMILY_EXIT,
  });
}
