import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { checkFriendCap, isUserSearchable } from "./utils/validation";
import { writeAuditLog } from "./audit";
import { getFCMToken, sendPushNotification } from "./utils/notifications";

const db = admin.firestore();

/**
 * Send a friend invite
 */
export const sendFriendInvite = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { toUserId, method } = data;
    const fromUserId = context.auth.uid;

    if (!toUserId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "toUserId is required"
      );
    }

    // Check friend cap for sender
    const senderCap = await checkFriendCap(fromUserId);
    if (!senderCap.canAdd) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Friend cap reached (100)"
      );
    }

    // Check friend cap for recipient
    const recipientCap = await checkFriendCap(toUserId);
    if (!recipientCap.canAdd) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Recipient has reached friend cap"
      );
    }

    // Check privacy if searching by email/phone
    if (method === "email" || method === "phone") {
      const searchable = await isUserSearchable(
        toUserId,
        method === "email" ? "email" : "phone"
      );
      if (!searchable) {
        await writeAuditLog({
          eventType: "invite_auto_rejected_not_searchable",
          actorId: fromUserId,
          subjectType: "user",
          subjectId: toUserId,
          metadata: { method },
        });
        throw new functions.https.HttpsError(
          "permission-denied",
          "User is not searchable by this method"
        );
      }
    }

    // Check if friendship already exists
    const friendshipId = generateFriendshipId(fromUserId, toUserId);
    const friendshipDoc = await db
      .collection("friends")
      .doc(friendshipId)
      .get();

    if (friendshipDoc.exists) {
      throw new functions.https.HttpsError(
        "already-exists",
        "Friendship already exists"
      );
    }

    // Check if pending invite exists
    const existingInvite = await db
      .collection("invites")
      .where("fromUserId", "==", fromUserId)
      .where("toUserId", "==", toUserId)
      .where("type", "==", "friend")
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (!existingInvite.empty) {
      throw new functions.https.HttpsError(
        "already-exists",
        "Pending invite already exists"
      );
    }

    // Create invite
    // Friend invites don't expire - set to far future date (100 years from now)
    const expiresAt = new Date();
    expiresAt.setFullYear(expiresAt.getFullYear() + 100);

    const inviteData = {
      type: "friend",
      fromUserId,
      toUserId,
      status: "pending",
      method: method || "search",
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const inviteRef = await db.collection("invites").add(inviteData);

    // Send push notification
    const fcmToken = await getFCMToken(toUserId);
    if (fcmToken) {
      await sendPushNotification(
        fcmToken,
        "New Friend Request",
        "You have a new friend request",
        {
          type: "friend_invite",
          inviteId: inviteRef.id,
          deepLink: `roadtrip-royale://invite/friend?inviteId=${inviteRef.id}`,
        }
      );
    }

    await writeAuditLog({
      eventType: "AUDIT_FRIEND_REQUEST_SENT",
      actorId: fromUserId,
      subjectType: "invite",
      subjectId: inviteRef.id,
      metadata: { toUserId, method },
    });

    return { inviteId: inviteRef.id };
  }
);

/**
 * Respond to a friend invite (accept or decline)
 */
export const respondToFriendInvite = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { inviteId, response } = data;
    const userId = context.auth.uid;

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

    // Get invite
    const inviteDoc = await db.collection("invites").doc(inviteId).get();

    if (!inviteDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Invite not found");
    }

    const inviteData = inviteDoc.data()!;

    // Verify user is the recipient
    if (inviteData.toUserId !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not authorized to respond to this invite"
      );
    }

    // Check if already responded
    if (inviteData.status !== "pending") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Invite already responded to"
      );
    }

    const batch = db.batch();

    // Update invite status
    batch.update(inviteDoc.ref, {
      status: response === "accept" ? "accepted" : "declined",
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (response === "accept") {
      // Create friendship
      const friendshipId = generateFriendshipId(
        inviteData.fromUserId,
        inviteData.toUserId
      );

      const friendshipData = {
        userA: inviteData.fromUserId,
        userB: inviteData.toUserId,
        status: "accepted",
        initiatedBy: inviteData.fromUserId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      batch.set(
        db.collection("friends").doc(friendshipId),
        friendshipData
      );

      // Increment friendCount for both users (transaction)
      const fromUserRef = db.collection("users").doc(inviteData.fromUserId);
      const toUserRef = db.collection("users").doc(inviteData.toUserId);

      const fromUserDoc = await fromUserRef.get();
      const toUserDoc = await toUserRef.get();

      const fromFriendCount = (fromUserDoc.data()?.friendCount || 0) + 1;
      const toFriendCount = (toUserDoc.data()?.friendCount || 0) + 1;

      batch.update(fromUserRef, { friendCount: fromFriendCount });
      batch.update(toUserRef, { friendCount: toFriendCount });

      await writeAuditLog({
        eventType: "AUDIT_FRIENDSHIP_ACCEPTED",
        actorId: userId,
        subjectType: "friendship",
        subjectId: friendshipId,
        metadata: { fromUserId: inviteData.fromUserId },
      });
    } else {
      await writeAuditLog({
        eventType: "friend_request_declined",
        actorId: userId,
        subjectType: "invite",
        subjectId: inviteId,
        metadata: { fromUserId: inviteData.fromUserId },
      });
    }

    await batch.commit();

    return { success: true };
  }
);

function generateFriendshipId(userA: string, userB: string): string {
  const sorted = [userA, userB].sort();
  return `${sorted[0]}_${sorted[1]}`;
}

