/**
 * Firestore trigger: notify trip members when a canonical `trip_ended` activity event is created.
 * Skips the actor who ended the trip. Best-effort FCM; sync still delivers via activity_events listeners.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { getFCMToken, sendPushNotification } from "./utils/notifications";
import { KIND_TRIP_ENDED } from "./publicLifetimeStatsCore";

const db = admin.firestore();

export const onTripEndedNotifyMembers = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.kind !== KIND_TRIP_ENDED) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const actorId = data.actorId as string | undefined;

    const sessionRef = db.collection("trip_sessions").doc(sessionId);
    const [sessionSnap, membersSnap] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection("members").get(),
    ]);

    if (!sessionSnap.exists) {
      return;
    }

    const tripName = (sessionSnap.data()?.name as string | undefined) ?? "Trip";
    const title = "Trip ended";
    const body = `${tripName} has ended. Open the app for your recap.`;

    await Promise.all(
      membersSnap.docs.map(async (memberDoc) => {
        const uid = memberDoc.id;
        if (actorId && uid === actorId) {
          return;
        }
        const fcmToken = await getFCMToken(uid);
        if (!fcmToken) {
          return;
        }
        try {
          await sendPushNotification(fcmToken, title, body, {
            type: "trip_ended",
            tripSessionId: sessionId,
          });
        } catch (error) {
          console.error(`trip_ended push failed for ${uid}:`, error);
        }
      })
    );
  });
