/**
 * Trip invites — server-authoritative (Step 08).
 *
 * MVP trust model: trip invites are low-privilege (gameplay / leaderboards). Bad actors may probe
 * trip metadata; tighten with friendship-only invites, rate limits, and captcha in production.
 * Share/QR flows should mirror friend/family: joining is not assumed until the server records accept.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { getFCMToken, sendPushNotification } from "./utils/notifications";
import { KIND_PARTICIPANT_INVITED, KIND_PARTICIPANT_JOINED, PK } from "./gameplayEventResolver";
import { syncCanonicalParticipantsFromMembers } from "./tripSessionCanonical";

const db = admin.firestore();

const DEFAULT_INVITE_DAYS = 7;

export const sendTripInvite = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const fromUserId = context.auth.uid;
  const { toUserId, tripSessionId, tripName, method, expiresAtMs } = data;

  if (!toUserId || typeof toUserId !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "toUserId is required"
    );
  }
  if (!tripSessionId || typeof tripSessionId !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "tripSessionId is required"
    );
  }
  if (!tripName || typeof tripName !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "tripName is required"
    );
  }

  if (toUserId === fromUserId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Cannot invite yourself"
    );
  }

  // TODO(step-08-hardening): Gate by friendship/family relationship once invite eligibility policy is finalized.
  // TODO(step-08-hardening): Add per-user rate limiting / anti-abuse controls for invite spam prevention.

  const sessionRef = db.collection("trip_sessions").doc(tripSessionId);
  const recipientMemberRef = sessionRef.collection("members").doc(toUserId);
  const recipientMemberSnap = await recipientMemberRef.get();
  if (recipientMemberSnap.exists) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "User is already a participant in this trip"
    );
  }

  let expiresAt: admin.firestore.Timestamp;
  if (typeof expiresAtMs === "number" && expiresAtMs > Date.now()) {
    expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);
  } else {
    const d = new Date();
    d.setDate(d.getDate() + DEFAULT_INVITE_DAYS);
    expiresAt = admin.firestore.Timestamp.fromDate(d);
  }

  const existingPending = await db
    .collection("trip_invites")
    .where("tripSessionId", "==", tripSessionId)
    .where("fromUserId", "==", fromUserId)
    .where("toUserId", "==", toUserId)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  if (!existingPending.empty) {
    const doc = existingPending.docs[0];
    return { inviteId: doc.id };
  }

  const batch = db.batch();

  batch.set(
    sessionRef,
    {
      name: tripName,
      createdBy: fromUserId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const ownerMemberRef = sessionRef.collection("members").doc(fromUserId);
  const ownerSnap = await ownerMemberRef.get();
  if (!ownerSnap.exists) {
    batch.set(ownerMemberRef, {
      role: "owner",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const inviteRef = db.collection("trip_invites").doc();
  const inviteMethod = typeof method === "string" ? method : "search";
  batch.set(inviteRef, {
    tripSessionId,
    tripName,
    fromUserId,
    toUserId,
    status: "pending",
    method: inviteMethod,
    expiresAt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const invEvRef = sessionRef.collection("activity_events").doc(`inv_${inviteRef.id}`);
  batch.set(invEvRef, {
    sessionId: tripSessionId,
    kind: KIND_PARTICIPANT_INVITED,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actorId: fromUserId,
    payload: {
      [PK.fromUserId]: fromUserId,
      [PK.toUserId]: toUserId,
      [PK.inviteId]: inviteRef.id,
      [PK.inviteMethod]: inviteMethod,
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  await syncCanonicalParticipantsFromMembers(tripSessionId);

  const fcmToken = await getFCMToken(toUserId);
  if (fcmToken) {
    await sendPushNotification(
      fcmToken,
      "New trip invite",
      "You have been invited to a trip",
      {
        type: "trip_invite",
        inviteId: inviteRef.id,
        tripSessionId,
        deepLink: `roadtrip-royale://invite/trip?inviteId=${inviteRef.id}`,
      }
    );
  }
  // TODO(step-08-ux): Wire trip invite deep-link route in iOS DeepLinkHandler + pending invites entry point.

  await writeAuditLog({
    eventType: "AUDIT_TRIP_INVITE_SENT",
    actorId: fromUserId,
    subjectType: "invite",
    subjectId: inviteRef.id,
    metadata: { toUserId, tripSessionId, method: method || "search" },
  });

  return { inviteId: inviteRef.id };
});

export const respondToTripInvite = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const userId = context.auth.uid;
    const { inviteId, response } = data;

    if (!inviteId || !response) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "inviteId and response are required"
      );
    }

    if (response !== "accept" && response !== "decline") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Response must be 'accept' or 'decline'"
      );
    }

    const inviteRef = db.collection("trip_invites").doc(inviteId);
    const inviteDoc = await inviteRef.get();

    if (!inviteDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Invite not found");
    }

    const inviteData = inviteDoc.data()!;

    if (inviteData.toUserId !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not authorized to respond to this invite"
      );
    }

    if (inviteData.status !== "pending") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Invite already responded to"
      );
    }

    const exp = inviteData.expiresAt as admin.firestore.Timestamp | undefined;
    if (exp && exp.toMillis() < Date.now()) {
      await inviteRef.update({
        status: "expired",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Invite has expired"
      );
    }

    const batch = db.batch();
    batch.update(inviteRef, {
      status: response === "accept" ? "accepted" : "declined",
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (response === "accept") {
      const tripSessionId = inviteData.tripSessionId as string;
      const sessionDocRef = db.collection("trip_sessions").doc(tripSessionId);
      const memberRef = sessionDocRef.collection("members").doc(userId);
      batch.set(memberRef, {
        role: "member",
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      batch.update(sessionDocRef, {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const joinEvRef = sessionDocRef.collection("activity_events").doc(`join_${inviteId}`);
      batch.set(joinEvRef, {
        sessionId: tripSessionId,
        kind: KIND_PARTICIPANT_JOINED,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        actorId: userId,
        payload: {
          [PK.participantId]: userId,
          [PK.inviteId]: inviteId,
          [PK.fromUserId]: inviteData.fromUserId as string,
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    if (response === "accept") {
      await syncCanonicalParticipantsFromMembers(inviteData.tripSessionId as string);
    }

    await writeAuditLog({
      eventType:
        response === "accept"
          ? "AUDIT_TRIP_INVITE_ACCEPTED"
          : "AUDIT_TRIP_INVITE_DECLINED",
      actorId: userId,
      subjectType: "invite",
      subjectId: inviteId,
      metadata: { fromUserId: inviteData.fromUserId },
    });

    return { success: true };
  }
);

export const cancelTripInvite = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const userId = context.auth.uid;
  const { inviteId } = data;

  if (!inviteId || typeof inviteId !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "inviteId is required"
    );
  }

  const inviteRef = db.collection("trip_invites").doc(inviteId);
  const inviteDoc = await inviteRef.get();

  if (!inviteDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Invite not found");
  }

  const inviteData = inviteDoc.data()!;

  if (inviteData.fromUserId !== userId) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the sender can cancel this invite"
    );
  }

  if (inviteData.status !== "pending") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Invite is no longer pending"
    );
  }

  await inviteRef.update({
    status: "canceled",
    respondedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await writeAuditLog({
    eventType: "AUDIT_TRIP_INVITE_CANCELED",
    actorId: userId,
    subjectType: "invite",
    subjectId: inviteId,
    metadata: { toUserId: inviteData.toUserId },
  });

  return { success: true };
});
