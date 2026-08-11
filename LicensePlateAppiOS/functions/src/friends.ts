import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  checkFriendCap,
  isUserSearchable,
  assertUserIsRegistered,
  recipientNotRegisteredMessage,
} from "./utils/validation";
import { writeAuditLog } from "./audit";
import { getFCMTokenForSocialPush, sendPushNotification } from "./utils/notifications";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertRegisteredAccount } from "./callableAuth";
import {
  assertCallerIsNotChild,
  assertTargetIsNotChild,
} from "./childAccessGuards";
import { friendInviteExpiresAtMillis } from "./retentionCore";

const db = admin.firestore();

/**
 * Send a friend invite
 */
export const sendFriendInvite = enforcedCallable(
  async (data, context) => {
    const fromUserId = assertRegisteredAccount(context);

    const { toUserId, method } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!toUserId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "toUserId is required"
      );
    }

    try {
      await assertUserIsRegistered(toUserId);
    } catch (error) {
      if (error instanceof Error && error.message === "User not found") {
        throw new functions.https.HttpsError("not-found", "User not found");
      }
      throw new functions.https.HttpsError(
        "failed-precondition",
        recipientNotRegisteredMessage
      );
    }

    // FR-24 (COPPA F-5b): no child may initiate friendship — consented or not. Friendship
    // is stranger contact, which sits outside `consentScope` (§11.1).
    await assertCallerIsNotChild(db, fromUserId);
    // FR-14: no child may be the target either. Unlike family invites there is no
    // carve-out: a friend edge is not a parent-managed relationship.
    await assertTargetIsNotChild(db, toUserId);

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
          clientMetadata,
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

    // Create invite.
    // Friend invites carry a finite expiry (FR-49b): the every-5-minutes pass in
    // `expiration.ts` flips a lapsed invite to "expired", and the daily retention job
    // deletes it once the grace period has passed. Previously this was a 100-year
    // sentinel, which kept the invite (and its two user ids) alive indefinitely.
    const expiresAtMillis = friendInviteExpiresAtMillis(Date.now());

    const inviteData = {
      type: "friend",
      fromUserId,
      toUserId,
      status: "pending",
      method: method || "search",
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMillis),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const inviteRef = await db.collection("invites").add(inviteData);

    // Send push notification (gated by recipient notificationPrefs.friend)
    const fcmToken = await getFCMTokenForSocialPush(toUserId, "friend");
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
      clientMetadata,
    });

    return { inviteId: inviteRef.id };
  }
);

/**
 * Respond to a friend invite (accept or decline)
 */
export const respondToFriendInvite = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { inviteId, response } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

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

    // FR-14 completion: the guard on `sendFriendInvite` is not sufficient on its own,
    // because `redeemShareCode` also mints `invites` rows (fromUserId = code creator,
    // toUserId = redeemer) and children must keep redeeming codes — their route back into a
    // family. Without this check a friend-type share code redeemed by a child would produce
    // exactly the stranger friend edge FR-14 exists to prevent; an in-family friend invite
    // that predates the flag (FR-36 deliberately spares those) would do the same.
    // Accepting is what creates the edge, so that is where the check belongs — DECLINING
    // stays open, since refusing contact is always protective.
    if (response === "accept") {
      for (const partyId of [inviteData.fromUserId, inviteData.toUserId]) {
        if (typeof partyId === "string") {
          await assertTargetIsNotChild(db, partyId);
        }
      }
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
        clientMetadata,
      });
    } else {
      await writeAuditLog({
        eventType: "friend_request_declined",
        actorId: userId,
        subjectType: "invite",
        subjectId: inviteId,
        metadata: { fromUserId: inviteData.fromUserId },
        clientMetadata,
      });
    }

    await batch.commit();

    return { success: true };
  }
);

/**
 * Remove an accepted friendship (unfriend). Updates friendCount for both users.
 */
export const removeFriend = enforcedCallable(async (data, context) => {
  const userId = assertRegisteredAccount(context);

  const { friendshipId } = data as { friendshipId?: string };
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (!friendshipId || typeof friendshipId !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "friendshipId is required"
    );
  }

  const friendshipRef = db.collection("friends").doc(friendshipId);
  const friendshipDoc = await friendshipRef.get();

  if (!friendshipDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Friendship not found");
  }

  const fd = friendshipDoc.data()!;
  const userA = fd.userA as string;
  const userB = fd.userB as string;

  if (userId !== userA && userId !== userB) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not authorized to remove this friendship"
    );
  }

  if (fd.status !== "accepted") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Only accepted friendships can be removed this way"
    );
  }

  const userARef = db.collection("users").doc(userA);
  const userBRef = db.collection("users").doc(userB);

  const [userADoc, userBDoc] = await Promise.all([
    userARef.get(),
    userBRef.get(),
  ]);

  const countA = Math.max(0, (userADoc.data()?.friendCount || 0) - 1);
  const countB = Math.max(0, (userBDoc.data()?.friendCount || 0) - 1);

  const batch = db.batch();
  batch.delete(friendshipRef);
  batch.update(userARef, { friendCount: countA });
  batch.update(userBRef, { friendCount: countB });
  await batch.commit();

  await writeAuditLog({
    eventType: "AUDIT_FRIENDSHIP_REMOVED",
    actorId: userId,
    subjectType: "friendship",
    subjectId: friendshipId,
    metadata: { otherUserId: userId === userA ? userB : userA },
    clientMetadata,
  });

  return { success: true };
});

function generateFriendshipId(userA: string, userB: string): string {
  const sorted = [userA, userB].sort();
  return `${sorted[0]}_${sorted[1]}`;
}

