"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.removeFriend = exports.respondToFriendInvite = exports.sendFriendInvite = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const validation_1 = require("./utils/validation");
const audit_1 = require("./audit");
const notifications_1 = require("./utils/notifications");
const clientMetadata_1 = require("./clientMetadata");
const db = admin.firestore();
/**
 * Send a friend invite
 */
exports.sendFriendInvite = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { toUserId, method } = data;
    const fromUserId = context.auth.uid;
    const clientMetadata = (0, clientMetadata_1.normalizeClientMetadata)(data === null || data === void 0 ? void 0 : data.clientMetadata);
    if (!toUserId) {
        throw new functions.https.HttpsError("invalid-argument", "toUserId is required");
    }
    // Check friend cap for sender
    const senderCap = await (0, validation_1.checkFriendCap)(fromUserId);
    if (!senderCap.canAdd) {
        throw new functions.https.HttpsError("resource-exhausted", "Friend cap reached (100)");
    }
    // Check friend cap for recipient
    const recipientCap = await (0, validation_1.checkFriendCap)(toUserId);
    if (!recipientCap.canAdd) {
        throw new functions.https.HttpsError("failed-precondition", "Recipient has reached friend cap");
    }
    // Check privacy if searching by email/phone
    if (method === "email" || method === "phone") {
        const searchable = await (0, validation_1.isUserSearchable)(toUserId, method === "email" ? "email" : "phone");
        if (!searchable) {
            await (0, audit_1.writeAuditLog)({
                eventType: "invite_auto_rejected_not_searchable",
                actorId: fromUserId,
                subjectType: "user",
                subjectId: toUserId,
                metadata: { method },
                clientMetadata,
            });
            throw new functions.https.HttpsError("permission-denied", "User is not searchable by this method");
        }
    }
    // Check if friendship already exists
    const friendshipId = generateFriendshipId(fromUserId, toUserId);
    const friendshipDoc = await db
        .collection("friends")
        .doc(friendshipId)
        .get();
    if (friendshipDoc.exists) {
        throw new functions.https.HttpsError("already-exists", "Friendship already exists");
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
        throw new functions.https.HttpsError("already-exists", "Pending invite already exists");
    }
    // Create invite
    // Friend invites don't expire - set to far future date (100 years from now)
    const expiresAt = new Date();
    expiresAt.setFullYear(expiresAt.getFullYear() + 100);
    const inviteData = Object.assign(Object.assign({ type: "friend", fromUserId,
        toUserId, status: "pending", method: method || "search", expiresAt: admin.firestore.Timestamp.fromDate(expiresAt) }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)), { createdAt: admin.firestore.FieldValue.serverTimestamp() });
    const inviteRef = await db.collection("invites").add(inviteData);
    // Send push notification
    const fcmToken = await (0, notifications_1.getFCMToken)(toUserId);
    if (fcmToken) {
        await (0, notifications_1.sendPushNotification)(fcmToken, "New Friend Request", "You have a new friend request", {
            type: "friend_invite",
            inviteId: inviteRef.id,
            deepLink: `roadtrip-royale://invite/friend?inviteId=${inviteRef.id}`,
        });
    }
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FRIEND_REQUEST_SENT",
        actorId: fromUserId,
        subjectType: "invite",
        subjectId: inviteRef.id,
        metadata: { toUserId, method },
        clientMetadata,
    });
    return { inviteId: inviteRef.id };
});
/**
 * Respond to a friend invite (accept or decline)
 */
exports.respondToFriendInvite = functions.https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { inviteId, response } = data;
    const userId = context.auth.uid;
    const clientMetadata = (0, clientMetadata_1.normalizeClientMetadata)(data === null || data === void 0 ? void 0 : data.clientMetadata);
    if (!inviteId || !response) {
        throw new functions.https.HttpsError("invalid-argument", "inviteId and response are required");
    }
    if (response !== "accept" && response !== "decline") {
        throw new functions.https.HttpsError("invalid-argument", "Response must be 'accept' or 'decline'");
    }
    // Get invite
    const inviteDoc = await db.collection("invites").doc(inviteId).get();
    if (!inviteDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Invite not found");
    }
    const inviteData = inviteDoc.data();
    // Verify user is the recipient
    if (inviteData.toUserId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "Not authorized to respond to this invite");
    }
    // Check if already responded
    if (inviteData.status !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "Invite already responded to");
    }
    const batch = db.batch();
    // Update invite status
    batch.update(inviteDoc.ref, Object.assign({ status: response === "accept" ? "accepted" : "declined", respondedAt: admin.firestore.FieldValue.serverTimestamp() }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)));
    if (response === "accept") {
        // Create friendship
        const friendshipId = generateFriendshipId(inviteData.fromUserId, inviteData.toUserId);
        const friendshipData = Object.assign({ userA: inviteData.fromUserId, userB: inviteData.toUserId, status: "accepted", initiatedBy: inviteData.fromUserId, createdAt: admin.firestore.FieldValue.serverTimestamp(), respondedAt: admin.firestore.FieldValue.serverTimestamp() }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata));
        batch.set(db.collection("friends").doc(friendshipId), friendshipData);
        // Increment friendCount for both users (transaction)
        const fromUserRef = db.collection("users").doc(inviteData.fromUserId);
        const toUserRef = db.collection("users").doc(inviteData.toUserId);
        const fromUserDoc = await fromUserRef.get();
        const toUserDoc = await toUserRef.get();
        const fromFriendCount = (((_a = fromUserDoc.data()) === null || _a === void 0 ? void 0 : _a.friendCount) || 0) + 1;
        const toFriendCount = (((_b = toUserDoc.data()) === null || _b === void 0 ? void 0 : _b.friendCount) || 0) + 1;
        batch.update(fromUserRef, Object.assign({ friendCount: fromFriendCount }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)));
        batch.update(toUserRef, Object.assign({ friendCount: toFriendCount }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)));
        await (0, audit_1.writeAuditLog)({
            eventType: "AUDIT_FRIENDSHIP_ACCEPTED",
            actorId: userId,
            subjectType: "friendship",
            subjectId: friendshipId,
            metadata: { fromUserId: inviteData.fromUserId },
            clientMetadata,
        });
    }
    else {
        await (0, audit_1.writeAuditLog)({
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
});
/**
 * Remove an accepted friendship (unfriend). Updates friendCount for both users.
 */
exports.removeFriend = functions.https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { friendshipId } = data;
    const userId = context.auth.uid;
    const clientMetadata = (0, clientMetadata_1.normalizeClientMetadata)(data === null || data === void 0 ? void 0 : data.clientMetadata);
    if (!friendshipId || typeof friendshipId !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "friendshipId is required");
    }
    const friendshipRef = db.collection("friends").doc(friendshipId);
    const friendshipDoc = await friendshipRef.get();
    if (!friendshipDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Friendship not found");
    }
    const fd = friendshipDoc.data();
    const userA = fd.userA;
    const userB = fd.userB;
    if (userId !== userA && userId !== userB) {
        throw new functions.https.HttpsError("permission-denied", "Not authorized to remove this friendship");
    }
    if (fd.status !== "accepted") {
        throw new functions.https.HttpsError("failed-precondition", "Only accepted friendships can be removed this way");
    }
    const userARef = db.collection("users").doc(userA);
    const userBRef = db.collection("users").doc(userB);
    const [userADoc, userBDoc] = await Promise.all([
        userARef.get(),
        userBRef.get(),
    ]);
    const countA = Math.max(0, (((_a = userADoc.data()) === null || _a === void 0 ? void 0 : _a.friendCount) || 0) - 1);
    const countB = Math.max(0, (((_b = userBDoc.data()) === null || _b === void 0 ? void 0 : _b.friendCount) || 0) - 1);
    const batch = db.batch();
    batch.delete(friendshipRef);
    batch.update(userARef, Object.assign({ friendCount: countA }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)));
    batch.update(userBRef, Object.assign({ friendCount: countB }, (0, clientMetadata_1.clientMetadataWrite)(clientMetadata)));
    await batch.commit();
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FRIENDSHIP_REMOVED",
        actorId: userId,
        subjectType: "friendship",
        subjectId: friendshipId,
        metadata: { otherUserId: userId === userA ? userB : userA },
        clientMetadata,
    });
    return { success: true };
});
function generateFriendshipId(userA, userB) {
    const sorted = [userA, userB].sort();
    return `${sorted[0]}_${sorted[1]}`;
}
//# sourceMappingURL=friends.js.map