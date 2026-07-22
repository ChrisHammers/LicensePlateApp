/**
 * Firestore trigger: when a canonical `trip_ended` activity event is created, merge per-user aggregates into
 * `public_lifetime_stats/{uid}` with idempotency via `appliedTrips.{sessionId}`.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { KIND_TRIP_ENDED, previewTripEndedAggregates } from "./publicLifetimeStatsCore";

const db = admin.firestore();

async function familyMemberIdsForUser(userId: string): Promise<Set<string>> {
  const userSnap = await db.collection("users").doc(userId).get();
  const famId = userSnap.data()?.activeFamilyId as string | undefined;
  if (!famId) {
    return new Set();
  }
  const memSnap = await db.collection("families").doc(famId).collection("members").get();
  return new Set(memSnap.docs.map((d) => d.id));
}

async function friendUserIdsForUser(userId: string): Promise<Set<string>> {
  const [asA, asB] = await Promise.all([
    db.collection("friends").where("userA", "==", userId).where("status", "==", "accepted").get(),
    db.collection("friends").where("userB", "==", userId).where("status", "==", "accepted").get(),
  ]);
  const peers = new Set<string>();
  for (const doc of asA.docs) {
    const other = doc.data()?.userB as string | undefined;
    if (other) peers.add(other);
  }
  for (const doc of asB.docs) {
    const other = doc.data()?.userA as string | undefined;
    if (other) peers.add(other);
  }
  return peers;
}

export const onTripEndedUpdatePublicLifetimeStats = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.kind !== KIND_TRIP_ENDED) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);

    const [sessionSnap, membersSnap, gamesSnap, eventsSnap] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection("members").get(),
      sessionRef.collection("games").get(),
      sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);

    if (!sessionSnap.exists) {
      return;
    }

    const canonicalStatus = sessionSnap.data()?.canonicalStatus as string | undefined;
    const memberUserIds = membersSnap.docs.map((d) => d.id);

    const familyMemberIdsByUser: Record<string, Set<string>> = {};
    const friendUserIdsByUser: Record<string, Set<string>> = {};
    await Promise.all(
      memberUserIds.map(async (uid) => {
        const [fam, friends] = await Promise.all([
          familyMemberIdsForUser(uid),
          friendUserIdsForUser(uid),
        ]);
        familyMemberIdsByUser[uid] = fam;
        friendUserIdsByUser[uid] = friends;
      })
    );

    const preview = previewTripEndedAggregates({
      canonicalStatus,
      memberUserIds,
      gameDocs: gamesSnap.docs,
      activityEventDocs: eventsSnap.docs,
      familyMemberIdsByUser,
      friendUserIdsByUser,
    });

    if (!preview) {
      return;
    }

    for (const uid of preview.memberUserIds) {
      const deltas = preview.perUser[uid];
      if (!deltas) {
        continue;
      }
      await db.runTransaction(async (tx) => {
        const ref = db.collection("public_lifetime_stats").doc(uid);
        const doc = await tx.get(ref);
        const applied = doc.data()?.appliedTrips as Record<string, unknown> | undefined;
        if (applied && applied[sessionId] != null) {
          return;
        }
        const appliedPath = `appliedTrips.${sessionId}`;
        tx.set(
          ref,
          {
            [appliedPath]: admin.firestore.FieldValue.serverTimestamp(),
            totalCompletedTrips: admin.firestore.FieldValue.increment(deltas.totalCompletedTrips),
            totalGamesPlayed: admin.firestore.FieldValue.increment(deltas.totalGamesPlayed),
            totalDiscoveries: admin.firestore.FieldValue.increment(deltas.totalDiscoveries),
            totalWeightedScore: admin.firestore.FieldValue.increment(deltas.totalWeightedScore),
            familyOnlyTripsCount: admin.firestore.FieldValue.increment(deltas.familyOnlyTripsCount),
            friendsOnlyTripsCount: admin.firestore.FieldValue.increment(deltas.friendsOnlyTripsCount),
            mixedFriendsFamilyTripsCount: admin.firestore.FieldValue.increment(
              deltas.mixedFriendsFamilyTripsCount
            ),
            entireFamilyTripsCount: admin.firestore.FieldValue.increment(deltas.entireFamilyTripsCount),
            lastComputedAt: admin.firestore.FieldValue.serverTimestamp(),
            schemaVersion: 1,
            source: "server_v1",
          },
          { merge: true }
        );
      });
    }
  });
