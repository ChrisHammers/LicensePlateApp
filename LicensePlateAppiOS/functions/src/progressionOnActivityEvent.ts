/**
 * Firestore trigger: merge per-user progression into `user_progression/{uid}` when canonical
 * activity events that award XP are created. Idempotent via `appliedProgressionEvents` +
 * per-component `appliedProgressionScopes`.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND, KIND_DISCOVERY_REJECTED } from "./gameplayEventResolver";
import {
  KIND_GAME_ENDED,
  KIND_GAME_COMPLETED,
  KIND_TRIP_ENDED,
  previewProgressionComponentsForActivityEvent,
} from "./progressionCore";
import {
  activityEventComponentXpGrantId,
  stageXpGrantsIfAbsent,
  type XpGrantWriteInput,
} from "./xpGrantLedgerCore";

const db = admin.firestore();

const PROGRESSION_KINDS = new Set([
  KIND_REGION_FOUND,
  KIND_DISCOVERY_REJECTED,
  KIND_GAME_ENDED,
  KIND_GAME_COMPLETED,
  KIND_TRIP_ENDED,
]);

/**
 * Reads `appliedProgressionEvents` / `appliedProgressionScopes` as a string-keyed map.
 * Supports nested maps (preferred) and legacy top-level keys `fieldName.<id>` from older set() encoding.
 */
function getMergedStringKeyMap(
  docData: Record<string, unknown>,
  nestedFieldName: "appliedProgressionEvents" | "appliedProgressionScopes"
): Record<string, unknown> | undefined {
  const nested = docData[nestedFieldName];
  if (nested !== null && nested !== undefined && !Array.isArray(nested) && typeof nested === "object") {
    return nested as Record<string, unknown>;
  }
  const prefix = `${nestedFieldName}.`;
  const synthetic: Record<string, unknown> = {};
  for (const k of Object.keys(docData)) {
    if (k.startsWith(prefix) && k.length > prefix.length) {
      synthetic[k.slice(prefix.length)] = docData[k] as unknown;
    }
  }
  return Object.keys(synthetic).length > 0 ? synthetic : undefined;
}

function eventTimestampSeconds(data: admin.firestore.DocumentData): number | undefined {
  const ts = data.timestamp;
  if (ts && typeof ts.seconds === "number") {
    return ts.seconds + (ts.nanoseconds || 0) / 1e9;
  }
  if (typeof data.timestamp === "number") {
    return data.timestamp;
  }
  return undefined;
}

export const onActivityEventUpdateUserProgression = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) {
      return;
    }
    const kind = data.kind as string;
    if (!PROGRESSION_KINDS.has(kind)) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const eventId = context.params.eventId as string;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);
    const payload = data.payload as Record<string, unknown> | null | undefined;

    const [membersSnap, gamesSnap, eventsSnap] = await Promise.all([
      sessionRef.collection("members").get(),
      sessionRef.collection("games").get(),
      sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);

    const memberUserIds = membersSnap.docs.map((d) => d.id).sort();
    const componentsByUser = previewProgressionComponentsForActivityEvent({
      kind,
      actorId: data.actorId as string | null | undefined,
      payload,
      memberUserIds,
      sessionId,
      eventTimestampSeconds: eventTimestampSeconds(data),
      gameDocs: gamesSnap.docs,
      activityEventDocs: eventsSnap.docs,
    });

    const deltaKeys = Object.keys(componentsByUser).sort();
    const uids = deltaKeys.filter((uid) => memberUserIds.includes(uid));

    if (uids.length === 0) {
      return;
    }

    await Promise.all(
      uids.map((uid) =>
        db.runTransaction(async (tx) => {
          const ref = db.collection("user_progression").doc(uid);
          const doc = await tx.get(ref);
          const docData = doc.data() || {};
          const applied = getMergedStringKeyMap(docData as Record<string, unknown>, "appliedProgressionEvents");
          if (applied && applied[eventId] != null) {
            return;
          }
          const scopesMap = getMergedStringKeyMap(docData as Record<string, unknown>, "appliedProgressionScopes") || {};

          const planned = componentsByUser[uid] || [];
          const fresh = planned.filter((c) => scopesMap[c.scopeKey] == null);

          const update: Record<string, unknown> = {
            schemaVersion: 1,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            appliedProgressionEvents: {
              [eventId]: admin.firestore.FieldValue.serverTimestamp(),
            },
          };

          if (fresh.length === 0) {
            tx.set(ref, update, { merge: true });
            return;
          }

          let totalXp = 0;
          let acceptedRegionFindCount = 0;
          let competitiveFirstPlaceFinishes = 0;
          let awardEverCompetitiveFirstPlace = false;
          const newScopes: Record<string, admin.firestore.FieldValue> = {};
          const grantInputs: XpGrantWriteInput[] = [];

          for (const c of fresh) {
            totalXp += c.amount;
            acceptedRegionFindCount += c.acceptedRegionFindCount ?? 0;
            competitiveFirstPlaceFinishes += c.competitiveFirstPlaceFinishes ?? 0;
            if (c.awardEverCompetitiveFirstPlace) awardEverCompetitiveFirstPlace = true;
            newScopes[c.scopeKey] = admin.firestore.FieldValue.serverTimestamp();
            grantInputs.push({
              grantId: activityEventComponentXpGrantId(uid, eventId, c.scopeKey),
              amount: c.amount,
              reason: c.reason,
              sourceType: "activity_event",
              sourceId: eventId,
              idempotencyKey: c.scopeKey,
              sessionId,
            });
          }

          // All grant reads must complete before any writes in this transaction.
          await stageXpGrantsIfAbsent(tx, db, uid, grantInputs);

          update.appliedProgressionScopes = newScopes;
          if (totalXp !== 0) {
            update.totalXp = admin.firestore.FieldValue.increment(totalXp);
          }
          if (acceptedRegionFindCount !== 0) {
            update.acceptedRegionFindCount = admin.firestore.FieldValue.increment(acceptedRegionFindCount);
          }
          if (competitiveFirstPlaceFinishes !== 0) {
            update.competitiveFirstPlaceFinishes = admin.firestore.FieldValue.increment(
              competitiveFirstPlaceFinishes
            );
          }
          if (awardEverCompetitiveFirstPlace) {
            update.everCompetitiveFirstPlace = true;
          }

          tx.set(ref, update, { merge: true });
        })
      )
    );
  });
