/**
 * De-identify a deleted user's residue in *shared* data (COPPA G2 / FR-50).
 *
 * `deleteAccount` erases everything that is the user's alone. What it cannot erase is data
 * co-owned by other participants: a multiplayer trip's append-only `activity_events` belong to
 * the trip, not to one player. This module makes the Privacy Policy §9 promise ("retained
 * de-identified") literally true by rewriting those shared docs so nothing left behind names
 * the uid, and by deleting the uid-keyed docs that carry no shared value at all.
 *
 * Takes `uid` + `db` and nothing else, so `requestChildDataDeletion` can reuse it verbatim.
 *
 * ## Query strategy
 *
 * Trip subcollections are keyed by uid (`members/{uid}`) rather than carrying a queryable uid
 * field, so there is no single query that finds every session the user touched. Instead:
 *
 * 1. **Discover** the affected session ids with collection-group queries over the fields that
 *    *are* queryable — `activity_events.actorId`, `activity_events.payload.participantId`
 *    (covers events another member wrote *about* this user, e.g. an owner kick), and
 *    `participant_prefs.userId` — plus `trip_sessions.createdBy` / `.canonicalEndedBy` and the
 *    user's `trip_invites`. Every membership path writes at least one of these: joining writes a
 *    `participant_joined` event with `actorId = uid`, and trip creation stamps `createdBy`.
 *    (Collection-group scope needs explicit `fieldOverrides` — see firestore.indexes.json.)
 * 2. **Sweep** each discovered session directly by doc id (`members/{uid}` etc.), which needs no
 *    index at all, and page its `activity_events` to rewrite the ones naming the uid.
 * 3. **Sweep** the flat collections by field equality (`invites`, `trip_invites`, `share_codes`,
 *    `plate_found_notify_buffers`, and `private.userId` for the per-doc client_metadata sidecars).
 *
 * ## Idempotency & resumability
 *
 * Every write is an unconditional delete or a full-field overwrite, and every predicate is
 * self-clearing: once an event's `actorId` is the tombstone the discovery query no longer
 * returns it. A second run therefore writes nothing.
 *
 * For resumability the per-session order is deliberate: the discovery signals are cleared
 * *last*. Cheap uid-keyed docs (`members`, `participant_prefs`, watermarks) go first and the
 * `activity_events` rewrite goes last, so a crash at any point leaves at least one event still
 * carrying the uid — which re-discovers the session on the next run. Flat-collection sweeps run
 * after the per-session work for the same reason (`trip_invites` is itself a discovery source).
 */

import * as admin from "firebase-admin";
import {
  deletedUserTombstoneIdFor,
  deidentifyEventFields,
  deidentifySessionFields,
} from "./accountDeletionDeidentifyCore";

/** Stay under Firestore's 500-op batch cap (mirrors accountDeletion.ts). */
const DEIDENTIFY_BATCH_LIMIT = 450;

/** Page size for scanning one session's activity_events. */
const EVENT_PAGE_SIZE = 400;

type Firestore = admin.firestore.Firestore;
type DocumentReference = admin.firestore.DocumentReference;

type PendingWrite =
  | { kind: "delete"; ref: DocumentReference }
  | { kind: "update"; ref: DocumentReference; data: Record<string, unknown> }
  | { kind: "setMerge"; ref: DocumentReference; data: Record<string, unknown> };

export interface DeidentifySummary {
  sessionCount: number;
  rewrittenEventCount: number;
  removedMemberCount: number;
  removedPrefsCount: number;
  removedWatermarkCount: number;
  removedClientMetadataCount: number;
  removedInviteCount: number;
  tombstonedShareCodeCount: number;
  removedNotifyBufferCount: number;
  endedOwnedSessionCount: number;
}

async function commitWrites(db: Firestore, writes: PendingWrite[]): Promise<void> {
  for (let start = 0; start < writes.length; start += DEIDENTIFY_BATCH_LIMIT) {
    const batch = db.batch();
    for (const write of writes.slice(start, start + DEIDENTIFY_BATCH_LIMIT)) {
      if (write.kind === "delete") {
        batch.delete(write.ref);
      } else if (write.kind === "setMerge") {
        batch.set(write.ref, write.data, { merge: true });
      } else {
        batch.update(write.ref, write.data);
      }
    }
    await batch.commit();
  }
}

/** Session ids reachable from every queryable signal the user leaves behind. */
async function discoverAffectedSessionIds(
  db: Firestore,
  userId: string
): Promise<string[]> {
  const ids = new Set<string>();

  const [byActor, byPayloadParticipant, byPrefs, byCreator, byEnder, invitesFrom, invitesTo] =
    await Promise.all([
      db.collectionGroup("activity_events").where("actorId", "==", userId).get(),
      db.collectionGroup("activity_events").where("payload.participantId", "==", userId).get(),
      db.collectionGroup("participant_prefs").where("userId", "==", userId).get(),
      db.collection("trip_sessions").where("createdBy", "==", userId).get(),
      db.collection("trip_sessions").where("canonicalEndedBy", "==", userId).get(),
      db.collection("trip_invites").where("fromUserId", "==", userId).get(),
      db.collection("trip_invites").where("toUserId", "==", userId).get(),
    ]);

  for (const snap of [byActor, byPayloadParticipant, byPrefs]) {
    for (const doc of snap.docs) {
      const sessionId = doc.ref.parent.parent?.id;
      if (sessionId) ids.add(sessionId);
    }
  }
  for (const snap of [byCreator, byEnder]) {
    for (const doc of snap.docs) {
      ids.add(doc.id);
    }
  }
  for (const snap of [invitesFrom, invitesTo]) {
    for (const doc of snap.docs) {
      const sessionId = doc.data()?.tripSessionId;
      if (typeof sessionId === "string" && sessionId) ids.add(sessionId);
    }
  }

  return [...ids].sort();
}

/**
 * Rewrite every activity_event in one session that names the uid.
 * Paged by document id so a large trip never loads at once.
 */
async function deidentifySessionEvents(
  db: Firestore,
  sessionRef: DocumentReference,
  userId: string
): Promise<number> {
  const events = sessionRef.collection("activity_events");
  let cursor: string | null = null;
  let rewritten = 0;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let query = events
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(EVENT_PAGE_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }
    const snap = await query.get();
    if (snap.empty) break;

    const writes: PendingWrite[] = [];
    for (const doc of snap.docs) {
      const update = deidentifyEventFields(doc.data(), userId);
      if (update) {
        writes.push({ kind: "update", ref: doc.ref, data: { ...update } });
      }
    }
    await commitWrites(db, writes);
    rewritten += writes.length;

    if (snap.docs.length < EVENT_PAGE_SIZE) break;
    cursor = snap.docs[snap.docs.length - 1].id;
  }

  return rewritten;
}

/**
 * Delete the deleted user's per-game fairness watermarks.
 * Blind deletes by doc id — a delete on a missing doc is a no-op, so this needs no reads
 * beyond listing the session's games and is trivially idempotent.
 */
async function deleteSessionWatermarks(
  db: Firestore,
  sessionRef: DocumentReference,
  userId: string
): Promise<number> {
  const gameRefs = await sessionRef.collection("games").listDocuments();
  const writes: PendingWrite[] = gameRefs.map((gameRef) => ({
    kind: "delete" as const,
    ref: gameRef.collection("fairness_ack_watermarks").doc(userId),
  }));
  await commitWrites(db, writes);
  return writes.length;
}

/**
 * De-identify all shared residue for `userId`. Safe to call repeatedly and safe to
 * re-run after a partial failure.
 */
export async function deidentifyUserResidue(
  db: Firestore,
  userId: string
): Promise<DeidentifySummary> {
  const summary: DeidentifySummary = {
    sessionCount: 0,
    rewrittenEventCount: 0,
    removedMemberCount: 0,
    removedPrefsCount: 0,
    removedWatermarkCount: 0,
    removedClientMetadataCount: 0,
    removedInviteCount: 0,
    tombstonedShareCodeCount: 0,
    removedNotifyBufferCount: 0,
    endedOwnedSessionCount: 0,
  };

  const tombstoneId = deletedUserTombstoneIdFor(userId);
  const sessionIds = await discoverAffectedSessionIds(db, userId);
  summary.sessionCount = sessionIds.length;

  for (const sessionId of sessionIds) {
    const sessionRef = db.collection("trip_sessions").doc(sessionId);

    // 1. uid-keyed docs that carry no shared value — drop them outright.
    const memberRef = sessionRef.collection("members").doc(userId);
    const prefsRef = sessionRef.collection("participant_prefs").doc(userId);
    const [memberSnap, prefsSnap] = await Promise.all([memberRef.get(), prefsRef.get()]);
    const uidKeyedWrites: PendingWrite[] = [];
    if (memberSnap.exists) {
      uidKeyedWrites.push({ kind: "delete", ref: memberRef });
      // Preserve the roster's historical shape: participant hydration
      // (fetchTripBootstrapForMember) and canonicalParticipants rebuilds both
      // derive from `members`, so the deleted participant must survive as a
      // tombstone row or trips visibly lose a participant. The id is unique per
      // deleted user (hash-suffixed), so multiple deleted users keep distinct
      // rows on rosters and leaderboards. It never matches a real auth uid, so
      // it grants no access under isTripSessionMember.
      const memberData = memberSnap.data() ?? {};
      uidKeyedWrites.push({
        kind: "setMerge",
        ref: sessionRef.collection("members").doc(tombstoneId),
        data: {
          role: "member",
          joinedAt: memberData.joinedAt ?? admin.firestore.FieldValue.serverTimestamp(),
          ...(memberData.teamId ? { teamId: memberData.teamId } : {}),
          tombstone: true,
        },
      });
      summary.removedMemberCount += 1;
    }
    if (prefsSnap.exists) {
      uidKeyedWrites.push({ kind: "delete", ref: prefsRef });
      summary.removedPrefsCount += 1;
    }
    await commitWrites(db, uidKeyedWrites);

    summary.removedWatermarkCount += await deleteSessionWatermarks(db, sessionRef, userId);

    // 2. Parent doc: createdBy / canonicalEndedBy / the canonicalParticipants roster.
    const sessionSnap = await sessionRef.get();
    if (sessionSnap.exists) {
      const sessionData = sessionSnap.data() ?? {};

      // 2a. End any still-live trip the deleted user OWNS. Ending is owner-gated
      // client-side and one-active-trip blocks new trips, so an orphaned active
      // session would strand every survivor. The trip_ended event doc id is
      // deterministic, so re-runs are idempotent and the members-notify trigger
      // fires exactly once; survivors get the normal remote-end + recap flow.
      const status = String(sessionData.canonicalStatus ?? "");
      if (
        String(sessionData.createdBy ?? "") === userId &&
        (status === "created" || status === "active")
      ) {
        const endWrites: PendingWrite[] = [
          {
            kind: "setMerge",
            ref: sessionRef,
            data: {
              canonicalStatus: "ended",
              canonicalEndedAt: admin.firestore.FieldValue.serverTimestamp(),
              canonicalEndedBy: tombstoneId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              syncVersion: admin.firestore.FieldValue.increment(1),
            },
          },
          {
            kind: "setMerge",
            ref: sessionRef.collection("activity_events").doc(`trip-ended-${tombstoneId}`),
            data: {
              sessionId,
              kind: "trip_ended",
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              actorId: tombstoneId,
              payload: { reason: "owner_account_deleted" },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
        ];
        // Stamp an end on games still marked open so recaps read coherently.
        const gamesSnap = await sessionRef.collection("games").get();
        for (const gameDoc of gamesSnap.docs) {
          if (!gameDoc.data().endedAt) {
            endWrites.push({
              kind: "setMerge",
              ref: gameDoc.ref,
              data: {
                endedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            });
          }
        }
        await commitWrites(db, endWrites);
        summary.endedOwnedSessionCount += 1;
      }

      const update = deidentifySessionFields(sessionData, userId);
      if (update) {
        await commitWrites(db, [{ kind: "update", ref: sessionRef, data: update }]);
      }
    }

    // 3. Shared events last — they are the discovery signal that makes a re-run complete.
    summary.rewrittenEventCount += await deidentifySessionEvents(db, sessionRef, userId);
  }

  // Per-doc client_metadata sidecars ({userId, clientMetadata}) under games / activity_events.
  const clientMetadataSnap = await db
    .collectionGroup("private")
    .where("userId", "==", userId)
    .get();
  await commitWrites(
    db,
    clientMetadataSnap.docs.map((doc) => ({ kind: "delete" as const, ref: doc.ref }))
  );
  summary.removedClientMetadataCount = clientMetadataSnap.size;

  // Coalesced push buffers addressed to the deleted user.
  const buffersSnap = await db
    .collection("plate_found_notify_buffers")
    .where("recipientUid", "==", userId)
    .get();
  await commitWrites(
    db,
    buffersSnap.docs.map((doc) => ({ kind: "delete" as const, ref: doc.ref }))
  );
  summary.removedNotifyBufferCount = buffersSnap.size;

  // Share codes: tombstone the author and revoke, so redeeming can never mint a *new*
  // invite naming the deleted user (redeemShareCode copies createdBy into fromUserId).
  const shareCodesSnap = await db
    .collection("share_codes")
    .where("createdBy", "==", userId)
    .get();
  await commitWrites(
    db,
    shareCodesSnap.docs.map((doc) => ({
      kind: "update" as const,
      ref: doc.ref,
      data: { createdBy: deletedUserTombstoneIdFor(userId), isRevoked: true },
    }))
  );
  summary.tombstonedShareCodeCount = shareCodesSnap.size;

  // Invites last: trip_invites is a session-discovery source.
  const inviteRefs = new Map<string, DocumentReference>();
  for (const collectionId of ["invites", "trip_invites"]) {
    const [from, to] = await Promise.all([
      db.collection(collectionId).where("fromUserId", "==", userId).get(),
      db.collection(collectionId).where("toUserId", "==", userId).get(),
    ]);
    for (const doc of [...from.docs, ...to.docs]) {
      inviteRefs.set(doc.ref.path, doc.ref);
    }
  }
  await commitWrites(
    db,
    [...inviteRefs.values()].map((ref) => ({ kind: "delete" as const, ref }))
  );
  summary.removedInviteCount = inviteRefs.size;

  return summary;
}
