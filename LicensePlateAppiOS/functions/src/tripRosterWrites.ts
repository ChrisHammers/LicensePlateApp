/**
 * Server-initiated trip-roster mutations — the two writes a Cloud Function makes to a LIVE
 * trip when no participant pressed a button.
 *
 * Both already existed, one each, buried in the paths that needed them:
 *  - ending an orphaned live trip lived inline in `deidentifyUserResidue` (FR-50, step 2a);
 *  - taking one participant off a roster lived inline in `runOwnerRemoveParticipantTransaction`
 *    (the owner kick).
 * FR-69 needs both from a third caller, so they are extracted here rather than forked: the
 * deletion sweep now calls `endLiveTripSession`, and the wire shape of a server-authored
 * `trip_ended` / `participant_left` event is defined in exactly one place.
 *
 * Db-parameterized (`fakeFirestore.ts`), like every other flow module. Both writes are
 * idempotent through DETERMINISTIC event ids: the caller owns the id, a re-run overwrites
 * the same document rather than appending a second row, and the members-notify /
 * lifetime-stats `onCreate` triggers therefore fire exactly once.
 */

import * as admin from "firebase-admin";
import { KIND_PARTICIPANT_LEFT, KIND_TRIP_ENDED, PK } from "./payloadKeys";
import { filterCanonicalParticipantsRemoveUser } from "./gameplayEventResolver";

type Firestore = admin.firestore.Firestore;

/**
 * The member doc's own document id, written into the document as a field (§3.1.1 item 19).
 *
 * `trip_sessions/{id}/members/{uid}` IS the membership authority — every server read derives
 * the user from `doc.id`. Firestore cannot query by document id across a collection group, so
 * that authority was un-queryable BY USER purely by construction, and a trip could never
 * follow an account to a second device. Writing the id into the doc makes
 * `collectionGroup("members").where("memberUserId","==",uid)` possible without adding a second
 * roster representation: if `memberUserId != doc.id` that is a bug with one obvious fix, not a
 * reconciliation problem.
 *
 * NOT named `userId`, deliberately. The rules block that authorizes the collection-group query
 * is a recursive wildcard (`match /{path=**}/members/{memberId}`) and is therefore ALSO
 * evaluated against `families/{familyId}/members/{memberId}`. Family member docs carry no user
 * field today (`family.ts`), but that is an absence, not a guarantee — a name only trip member
 * docs will ever carry makes the collision structurally impossible instead of merely absent.
 * If you are about to stamp this field on a family member doc: don't. Read
 * `firestore.rules`' "Account-scoped trip discovery" block first.
 */
export const TRIP_MEMBER_USER_ID_FIELD = "memberUserId";

export type TripMemberRole = "owner" | "member";

export interface TripMemberDocInput {
  /**
   * The uid this member doc is KEYED BY — `members/{userId}`. It is the document's own id and
   * nothing else; never pass a caller-supplied value that is not the id being written to, and
   * never pass a real uid when writing a de-identification TOMBSTONE row (see
   * `accountDeletionDeidentify.ts`, which deliberately does not use this helper).
   */
  userId: string;
  role: TripMemberRole;
}

/**
 * The one place a `trip_sessions/{id}/members/{uid}` document's fields are composed.
 *
 * Four call sites create member docs — `ensureOwnerMemberIfCreatorPayload` and
 * `ensureOwnerMemberIfTripDocCreatedByMatches` (tripSessionCanonical.ts), the sender/owner
 * seed and the accept path (tripInvites.ts) — and they cannot drift apart while they all go
 * through here. The two invite writes are plain `batch.set` with no merge, so including the
 * field in the payload is also what keeps a re-accept from dropping it.
 *
 * EVERY create site must go through here, because nothing repairs an EXISTING row written
 * without the field — the append-race path named above only creates a row that is missing
 * entirely, it never adds the field to one already there. A member doc missing `memberUserId`
 * is a trip permanently invisible to the very account that owns it, on every device. A new
 * create site adds itself to this helper, never composes the fields itself.
 * (`tripMemberUserIdStamp.test.ts` pins all four by name, and its source scan fails if a fifth
 * writes a member doc any other way.)
 */
export function tripMemberDocFields(input: TripMemberDocInput): Record<string, unknown> {
  return {
    role: input.role,
    joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    [TRIP_MEMBER_USER_ID_FIELD]: input.userId,
  };
}

/** `canonicalStatus` values that mean the trip is still being played. */
export const LIVE_TRIP_SESSION_STATUSES: readonly string[] = ["created", "active"];

/** True while a trip is still live — the only trips FR-69 and FR-50 may mutate. */
export function isLiveTripSessionData(
  data: Record<string, unknown> | undefined | null
): boolean {
  return LIVE_TRIP_SESSION_STATUSES.includes(String(data?.canonicalStatus ?? ""));
}

export interface EndLiveTripSessionInput {
  tripSessionId: string;
  /** Stamped as `canonicalEndedBy` and as the event's `actorId`. */
  endedBy: string;
  /** `payload.reason` on the emitted `trip_ended` event. */
  reason: string;
  /** Deterministic `activity_events` doc id — re-runs overwrite, never duplicate. */
  eventId: string;
}

/**
 * End a live trip server-side: the session doc goes terminal, a canonical `trip_ended`
 * event is appended (so survivors get the normal remote-end + recap flow, and the
 * lifetime-stats one-shot runs), and any game still marked open gets an end stamp so
 * recaps read coherently.
 *
 * Callers gate liveness themselves (`isLiveTripSessionData`) — they have already read the
 * session document to decide there is anything to do.
 */
export async function endLiveTripSession(
  db: Firestore,
  input: EndLiveTripSessionInput
): Promise<void> {
  const sessionRef = db.collection("trip_sessions").doc(input.tripSessionId);
  const gamesSnapshot = await sessionRef.collection("games").get();

  const batch = db.batch();
  batch.set(
    sessionRef,
    {
      canonicalStatus: "ended",
      canonicalEndedAt: admin.firestore.FieldValue.serverTimestamp(),
      canonicalEndedBy: input.endedBy,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncVersion: admin.firestore.FieldValue.increment(1),
    },
    { merge: true }
  );
  batch.set(
    sessionRef.collection("activity_events").doc(input.eventId),
    {
      sessionId: input.tripSessionId,
      kind: KIND_TRIP_ENDED,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      actorId: input.endedBy,
      payload: { reason: input.reason },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  for (const gameDoc of gamesSnapshot.docs) {
    if (!gameDoc.data().endedAt) {
      batch.set(
        gameDoc.ref,
        {
          endedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  }
  await batch.commit();
}

export interface RemoveTripParticipantInput {
  tripSessionId: string;
  /** The participant leaving the live roster. */
  userId: string;
  /** `payload.leaveReason` — the server's account of why (`voluntary` / `kicked` / FR-69). */
  leaveReason: string;
  /** Deterministic `activity_events` doc id — re-runs overwrite, never duplicate. */
  eventId: string;
}

/**
 * Take one participant off a live roster, with the same write set the owner kick uses:
 * the `members/{uid}` doc goes (it is what `isTripSessionMember` reads, so live
 * participation ends with it), `canonicalParticipants` loses the row, and a
 * `participant_left` event records the departure in the append-only log — their earlier
 * events stay exactly as they are, attributed to them.
 *
 * `actorId` is the leaver, matching a voluntary leave: no human initiated this, and
 * `leaveReason` carries the truth. Returns false when the user is already off the roster,
 * which is what makes a re-run a no-op.
 */
export async function removeParticipantFromLiveTripRoster(
  db: Firestore,
  input: RemoveTripParticipantInput
): Promise<boolean> {
  const sessionRef = db.collection("trip_sessions").doc(input.tripSessionId);
  const memberRef = sessionRef.collection("members").doc(input.userId);
  const [memberSnapshot, sessionSnapshot] = await Promise.all([
    memberRef.get(),
    sessionRef.get(),
  ]);
  if (!memberSnapshot.exists) {
    return false;
  }

  const batch = db.batch();
  batch.delete(memberRef);
  if (sessionSnapshot.exists) {
    const participants = sessionSnapshot.data()?.canonicalParticipants;
    const sessionUpdate: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (Array.isArray(participants)) {
      sessionUpdate.canonicalParticipants = filterCanonicalParticipantsRemoveUser(
        participants,
        input.userId
      );
    }
    batch.update(sessionRef, sessionUpdate);
  }
  batch.set(
    sessionRef.collection("activity_events").doc(input.eventId),
    {
      sessionId: input.tripSessionId,
      kind: KIND_PARTICIPANT_LEFT,
      timestamp: admin.firestore.Timestamp.now(),
      actorId: input.userId,
      payload: {
        [PK.participantId]: input.userId,
        [PK.leaveReason]: input.leaveReason,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await batch.commit();
  return true;
}
