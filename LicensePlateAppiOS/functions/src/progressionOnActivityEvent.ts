/**
 * Firestore trigger: merge per-user progression into `user_progression/{uid}` when canonical
 * `region_found` or `game_ended` activity events are created. Idempotent via `appliedProgressionEvents.{eventId}`.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND } from "./gameplayEventResolver";
import { KIND_GAME_ENDED, previewProgressionDeltasForActivityEvent } from "./progressionCore";

const db = admin.firestore();

export const onActivityEventUpdateUserProgression = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) {
      return;
    }
    const kind = data.kind as string;
    if (kind !== KIND_REGION_FOUND && kind !== KIND_GAME_ENDED) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const eventId = context.params.eventId as string;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);

    const [membersSnap, gamesSnap, eventsSnap] = await Promise.all([
      sessionRef.collection("members").get(),
      sessionRef.collection("games").get(),
      sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);

    const memberUserIds = membersSnap.docs.map((d) => d.id).sort();
    const deltasByUser = previewProgressionDeltasForActivityEvent({
      kind,
      actorId: data.actorId as string | null | undefined,
      payload: data.payload as Record<string, unknown> | null | undefined,
      memberUserIds,
      gameDocs: gamesSnap.docs,
      activityEventDocs: eventsSnap.docs,
    });

    const uids = Object.keys(deltasByUser).filter((uid) => memberUserIds.includes(uid));
    if (uids.length === 0) {
      return;
    }

    await Promise.all(
      uids.map((uid) =>
        db.runTransaction(async (tx) => {
          const ref = db.collection("user_progression").doc(uid);
          const doc = await tx.get(ref);
          const applied = doc.data()?.appliedProgressionEvents as Record<string, unknown> | undefined;
          if (applied && applied[eventId] != null) {
            return;
          }
          const d = deltasByUser[uid];
          if (!d) {
            return;
          }

          const appliedPath = `appliedProgressionEvents.${eventId}`;
          const update: Record<string, unknown> = {
            [appliedPath]: admin.firestore.FieldValue.serverTimestamp(),
            schemaVersion: 1,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          if (d.totalXp !== 0) {
            update.totalXp = admin.firestore.FieldValue.increment(d.totalXp);
          }
          if (d.acceptedRegionFindCount !== 0) {
            update.acceptedRegionFindCount = admin.firestore.FieldValue.increment(d.acceptedRegionFindCount);
          }
          if (d.competitiveFirstPlaceFinishes !== 0) {
            update.competitiveFirstPlaceFinishes = admin.firestore.FieldValue.increment(d.competitiveFirstPlaceFinishes);
          }
          if (d.awardEverCompetitiveFirstPlace) {
            update.everCompetitiveFirstPlace = true;
          }

          tx.set(ref, update, { merge: true });
        })
      )
    );
  });
