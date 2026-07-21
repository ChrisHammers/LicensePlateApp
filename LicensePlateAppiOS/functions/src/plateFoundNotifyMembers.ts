/**
 * Coalesced FCM when peers find plates (`region_found` activity events).
 * Buffers per (sessionId, recipientUid) for ~90s, then one push per flush.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { KIND_REGION_FOUND, PK } from "./gameplayEventResolver";
import {
  parseCommonConfigGameMode,
  parseTeamsDataBase64,
} from "./publicLifetimeStatsCore";
import { getFCMTokenForPush, sendPushNotification } from "./utils/notifications";
import {
  buildPlateFoundNotificationCopy,
  classifyPlateFoundRelationship,
  mergePlateFoundBuffer,
  PlateFoundPendingItem,
  pushCategoryForRelationship,
} from "./plateFoundNotifyCore";
import { buildDisplayName } from "./userSearchCore";

const db = admin.firestore();

const BUFFERS = "plate_found_notify_buffers";

function bufferDocId(sessionId: string, recipientUid: string): string {
  return `${sessionId}__${recipientUid}`;
}

function readPayloadRegionId(payload: Record<string, unknown> | null | undefined): string {
  if (!payload) return "";
  const regionId = payload[PK.regionId];
  return typeof regionId === "string" ? regionId : "";
}

function primaryLicensePlateGame(
  gameDocs: admin.firestore.QueryDocumentSnapshot[]
): admin.firestore.DocumentData | null {
  const sorted = [...gameDocs].sort((a, b) => a.id.localeCompare(b.id));
  const licensePlate = sorted.find((d) => {
    const def = d.data()?.gameDefinitionId;
    return def === "license_plate" || def === undefined || def === null || def === "";
  });
  return (licensePlate ?? sorted[0])?.data() ?? null;
}

async function actorDisplayName(actorId: string): Promise<string> {
  const snap = await db.collection("users").doc(actorId).get();
  const data = snap.data() || {};
  return buildDisplayName({
    userName:
      (typeof data.userName === "string" && data.userName) ||
      (typeof data.username === "string" && data.username) ||
      undefined,
    firstName: typeof data.firstName === "string" ? data.firstName : null,
    lastName: typeof data.lastName === "string" ? data.lastName : null,
  });
}

export const onRegionFoundNotifyMembers = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.kind !== KIND_REGION_FOUND) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const actorId = (data.actorId as string | undefined) || "";
    if (!actorId) {
      return;
    }

    const payload = data.payload as Record<string, unknown> | null | undefined;
    const regionId = readPayloadRegionId(payload);
    if (!regionId) {
      return;
    }

    const sessionRef = db.collection("trip_sessions").doc(sessionId);
    const [sessionSnap, membersSnap, gamesSnap] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection("members").get(),
      sessionRef.collection("games").get(),
    ]);

    if (!sessionSnap.exists) {
      return;
    }

    const memberIds = membersSnap.docs.map((d) => d.id);
    if (memberIds.length <= 1) {
      return;
    }

    const tripName = (sessionSnap.data()?.name as string | undefined) ?? "Trip";
    const gameData = primaryLicensePlateGame(gamesSnap.docs);
    const gameMode = parseCommonConfigGameMode(
      (gameData?.commonConfigDataBase64 as string | undefined) ?? undefined
    );
    const teams = parseTeamsDataBase64(
      (gameData?.teamsDataBase64 as string | null | undefined) ?? null
    );

    const displayName = await actorDisplayName(actorId);
    const nowMs = Date.now();
    const item: PlateFoundPendingItem = {
      regionId,
      actorId,
      actorDisplayName: displayName,
      atMs: nowMs,
    };

    await Promise.all(
      memberIds.map(async (recipientUid) => {
        if (recipientUid === actorId) {
          return;
        }
        const relationship = classifyPlateFoundRelationship({
          gameMode,
          actorId,
          recipientId: recipientUid,
          teams,
        });
        const category = pushCategoryForRelationship(relationship);
        const fcmToken = await getFCMTokenForPush(recipientUid, category);
        if (!fcmToken) {
          return;
        }

        const bufferRef = db.collection(BUFFERS).doc(bufferDocId(sessionId, recipientUid));
        await db.runTransaction(async (tx) => {
          const buf = await tx.get(bufferRef);
          const existing = buf.data() || {};
          const existingPending = Array.isArray(existing.pending)
            ? (existing.pending as PlateFoundPendingItem[])
            : [];
          const existingFlushAtMs =
            typeof existing.flushAtMs === "number" ? (existing.flushAtMs as number) : null;
          const merged = mergePlateFoundBuffer({
            existingPending,
            existingFlushAtMs,
            nowMs,
            item,
          });
          tx.set(
            bufferRef,
            {
              sessionId,
              recipientUid,
              tripName,
              pending: merged.pending,
              flushAtMs: merged.flushAtMs,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        });
      })
    );
  });

/**
 * Flush due plate-found coalesce buffers (every 1 minute; buffers schedule ~90s ahead).
 */
export const flushPlateFoundNotifyBuffers = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    const nowMs = Date.now();
    const due = await db.collection(BUFFERS).where("flushAtMs", "<=", nowMs).limit(200).get();
    if (due.empty) {
      return;
    }

    await Promise.all(
      due.docs.map(async (doc) => {
        const claimed = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          if (!fresh.exists) {
            return null;
          }
          const freshData = fresh.data() || {};
          const freshPending = Array.isArray(freshData.pending)
            ? (freshData.pending as PlateFoundPendingItem[])
            : [];
          const flushAtMs =
            typeof freshData.flushAtMs === "number" ? (freshData.flushAtMs as number) : null;
          if (flushAtMs == null || flushAtMs > nowMs || freshPending.length === 0) {
            return null;
          }
          tx.delete(doc.ref);
          return {
            recipientUid: freshData.recipientUid as string,
            sessionId: freshData.sessionId as string,
            tripName: (freshData.tripName as string | undefined) ?? "Trip",
            pending: freshPending,
          };
        });

        if (!claimed?.recipientUid || !claimed.sessionId) {
          return;
        }

        // Prefer whatever plate-found category is still enabled at flush time.
        const fcmToken =
          (await getFCMTokenForPush(claimed.recipientUid, "plateFoundByCoPilots")) ||
          (await getFCMTokenForPush(claimed.recipientUid, "plateFoundByOpponent"));
        if (!fcmToken) {
          return;
        }

        const copy = buildPlateFoundNotificationCopy({
          tripName: claimed.tripName,
          pending: claimed.pending,
        });

        try {
          await sendPushNotification(fcmToken, copy.title, copy.body, {
            type: "plate_found",
            tripSessionId: claimed.sessionId,
            deepLink: `roadtrip-royale://trip/${claimed.sessionId}`,
            findCount: String(claimed.pending.length),
          });
        } catch (error) {
          console.error(`plate_found push failed for ${claimed.recipientUid}:`, error);
        }
      })
    );
  });
