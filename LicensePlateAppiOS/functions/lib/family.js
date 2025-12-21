"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.inactivateFamily = exports.changeFamilyMemberRole = exports.removeFamilyMember = exports.approveFamilyJoinRequest_CaptainStep = exports.respondToFamilyInvite_UserStep = exports.sendFamilyInvite = exports.createFamily = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const validation_1 = require("./utils/validation");
const audit_1 = require("./audit");
const notifications_1 = require("./utils/notifications");
const db = admin.firestore();
/**
 * Create a new family
 */
exports.createFamily = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { name } = data;
    const userId = context.auth.uid;
    if (!name || typeof name !== "string" || name.trim().length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Family name is required");
    }
    // Check if user already has an active family (unless retired general)
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError("not-found", "User not found");
    }
    const userData = userDoc.data();
    if (!userData.isRetiredGeneral && userData.activeFamilyId) {
        throw new functions.https.HttpsError("failed-precondition", "User already has an active family");
    }
    // Create family
    const familyData = {
        name: name.trim(),
        creatorId: userId,
        status: "active",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const familyRef = await db.collection("families").add(familyData);
    // Add creator as member with creator role
    await familyRef.collection("members").doc(userId).set({
        role: "creator",
        permissions: {
            canInvite: true,
            canEditSettings: true,
        },
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Update user's activeFamilyId (if not retired general)
    if (!userData.isRetiredGeneral) {
        await db.collection("users").doc(userId).update({
            activeFamilyId: familyRef.id,
        });
    }
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FAMILY_CREATED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyRef.id,
        metadata: { name: name.trim() },
    });
    return { familyId: familyRef.id };
});
/**
 * Send a family invite
 */
exports.sendFamilyInvite = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { toUserId, familyId, method } = data;
    const fromUserId = context.auth.uid;
    if (!toUserId || !familyId) {
        throw new functions.https.HttpsError("invalid-argument", "toUserId and familyId are required");
    }
    // Verify sender is creator or captain
    const memberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(fromUserId)
        .get();
    if (!memberDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a family member");
    }
    const memberRole = memberDoc.data().role;
    if (memberRole !== "creator" && memberRole !== "captain") {
        throw new functions.https.HttpsError("permission-denied", "Only creators and captains can invite");
    }
    // Get target user to determine role
    const targetUserDoc = await db.collection("users").doc(toUserId).get();
    if (!targetUserDoc.exists) {
        throw new functions.https.HttpsError("not-found", "User not found");
    }
    const targetUserData = targetUserDoc.data();
    const newRole = targetUserData.isRetiredGeneral
        ? "retired_general"
        : "scout"; // Default to scout for new members
    // Check if user can be added
    const canAdd = await (0, validation_1.canAddMemberToFamily)(familyId, newRole, toUserId);
    if (!canAdd.canAdd) {
        await (0, audit_1.writeAuditLog)({
            eventType: "invite_auto_rejected_user_already_in_family",
            actorId: fromUserId,
            subjectType: "user",
            subjectId: toUserId,
            metadata: { familyId, reason: canAdd.reason },
        });
        throw new functions.https.HttpsError("failed-precondition", canAdd.reason || "Cannot add user to family");
    }
    // Create invite
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 15);
    const inviteData = {
        type: "family",
        fromUserId,
        toUserId,
        familyId,
        status: "pending",
        method: method || "search",
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const inviteRef = await db.collection("invites").add(inviteData);
    // Send push notification
    const fcmToken = await (0, notifications_1.getFCMToken)(toUserId);
    if (fcmToken) {
        await (0, notifications_1.sendPushNotification)(fcmToken, "Family Invitation", "You've been invited to join a family", {
            type: "family_invite",
            inviteId: inviteRef.id,
            familyId,
            deepLink: `roadtrip-royale://invite/family?inviteId=${inviteRef.id}&familyId=${familyId}`,
        });
    }
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FAMILY_INVITE_SENT",
        actorId: fromUserId,
        subjectType: "invite",
        subjectId: inviteRef.id,
        metadata: { toUserId, familyId, method },
    });
    return { inviteId: inviteRef.id };
});
/**
 * User accepts family invite (step 1) - creates pending request
 */
exports.respondToFamilyInvite_UserStep = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { inviteId, response } = data;
    const userId = context.auth.uid;
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
    if (inviteData.status !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "Invite already responded to");
    }
    const batch = db.batch();
    // Update invite status
    batch.update(inviteDoc.ref, {
        status: response === "accept" ? "accepted" : "declined",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (response === "accept") {
        // Create pending join request (awaiting captain approval)
        const requestData = {
            userId,
            requestedBy: inviteData.fromUserId,
            method: inviteData.method,
            status: "pending",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        const requestRef = db
            .collection(`families/${inviteData.familyId}/pending`)
            .doc();
        batch.set(requestRef, requestData);
        await (0, audit_1.writeAuditLog)({
            eventType: "family_join_request_created",
            actorId: userId,
            subjectType: "invite",
            subjectId: inviteId,
            metadata: { familyId: inviteData.familyId },
        });
    }
    await batch.commit();
    return { success: true };
});
/**
 * Captain approves family join request (step 2) - adds member
 */
exports.approveFamilyJoinRequest_CaptainStep = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { familyId, requestId, response } = data;
    const userId = context.auth.uid;
    if (!familyId || !requestId || !response) {
        throw new functions.https.HttpsError("invalid-argument", "familyId, requestId, and response are required");
    }
    if (response !== "approve" && response !== "decline") {
        throw new functions.https.HttpsError("invalid-argument", "Response must be 'approve' or 'decline'");
    }
    // Verify user is creator or captain
    const memberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(userId)
        .get();
    if (!memberDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a family member");
    }
    const memberRole = memberDoc.data().role;
    if (memberRole !== "creator" && memberRole !== "captain") {
        throw new functions.https.HttpsError("permission-denied", "Only creators and captains can approve requests");
    }
    // Get request
    const requestDoc = await db
        .collection(`families/${familyId}/pending`)
        .doc(requestId)
        .get();
    if (!requestDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Request not found");
    }
    const requestData = requestDoc.data();
    if (requestData.status !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "Request already resolved");
    }
    const batch = db.batch();
    if (response === "approve") {
        // Get target user to determine role
        const targetUserDoc = await db
            .collection("users")
            .doc(requestData.userId)
            .get();
        if (!targetUserDoc.exists) {
            throw new functions.https.HttpsError("not-found", "User not found");
        }
        const targetUserData = targetUserDoc.data();
        const newRole = targetUserData.isRetiredGeneral
            ? "retired_general"
            : "scout";
        // Check if user can still be added (limits may have changed)
        const canAdd = await (0, validation_1.canAddMemberToFamily)(familyId, newRole, requestData.userId);
        if (!canAdd.canAdd) {
            throw new functions.https.HttpsError("failed-precondition", canAdd.reason || "Cannot add user to family");
        }
        // Add member
        const memberData = {
            role: newRole,
            permissions: {
                canInvite: false,
                canEditSettings: false,
            },
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        batch.set(db.collection(`families/${familyId}/members`).doc(requestData.userId), memberData);
        // Update user's activeFamilyId (if not retired general)
        if (!targetUserData.isRetiredGeneral) {
            batch.update(db.collection("users").doc(requestData.userId), {
                activeFamilyId: familyId,
            });
        }
        // Update request status
        batch.update(requestDoc.ref, {
            status: "approved",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Send push notification
        const fcmToken = await (0, notifications_1.getFCMToken)(requestData.userId);
        if (fcmToken) {
            await (0, notifications_1.sendPushNotification)(fcmToken, "Family Request Approved", "You've been approved to join the family", {
                type: "family_join_approved",
                familyId,
                deepLink: `roadtrip-royale://family/${familyId}`,
            });
        }
        await (0, audit_1.writeAuditLog)({
            eventType: "AUDIT_FAMILY_JOIN_APPROVED",
            actorId: userId,
            subjectType: "family",
            subjectId: familyId,
            metadata: { newMemberId: requestData.userId, role: newRole },
        });
    }
    else {
        // Decline request
        batch.update(requestDoc.ref, {
            status: "declined",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await (0, audit_1.writeAuditLog)({
            eventType: "family_join_request_declined",
            actorId: userId,
            subjectType: "family",
            subjectId: familyId,
            metadata: { requestId, userId: requestData.userId },
        });
    }
    await batch.commit();
    return { success: true };
});
/**
 * Remove a family member
 */
exports.removeFamilyMember = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { familyId, memberId } = data;
    const userId = context.auth.uid;
    if (!familyId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "familyId and memberId are required");
    }
    // Verify user is creator or captain
    const memberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(userId)
        .get();
    if (!memberDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a family member");
    }
    const memberRole = memberDoc.data().role;
    // Get member to remove
    const targetMemberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(memberId)
        .get();
    if (!targetMemberDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Member not found");
    }
    const targetMemberRole = targetMemberDoc.data().role;
    // Creator can remove anyone, captain can only remove non-captains
    if (memberRole === "creator") {
        // Creator can remove anyone
    }
    else if (memberRole === "captain" && targetMemberRole === "captain") {
        throw new functions.https.HttpsError("permission-denied", "Captains cannot remove other captains");
    }
    else if (memberRole !== "captain") {
        throw new functions.https.HttpsError("permission-denied", "Only creators and captains can remove members");
    }
    const batch = db.batch();
    // Remove member
    batch.delete(targetMemberDoc.ref);
    // Clear activeFamilyId if not retired general
    const userDoc = await db.collection("users").doc(memberId).get();
    const userData = userDoc.data();
    if (userData && !userData.isRetiredGeneral) {
        batch.update(db.collection("users").doc(memberId), {
            activeFamilyId: admin.firestore.FieldValue.delete(),
        });
    }
    await batch.commit();
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FAMILY_MEMBER_REMOVED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: { removedMemberId: memberId, role: targetMemberRole },
    });
    return { success: true };
});
/**
 * Change a family member's role
 */
exports.changeFamilyMemberRole = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { familyId, memberId, newRole } = data;
    const userId = context.auth.uid;
    if (!familyId || !memberId || !newRole) {
        throw new functions.https.HttpsError("invalid-argument", "familyId, memberId, and newRole are required");
    }
    // Verify user is creator or captain
    const memberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(userId)
        .get();
    if (!memberDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a family member");
    }
    const memberRole = memberDoc.data().role;
    if (memberRole !== "creator" && memberRole !== "captain") {
        throw new functions.https.HttpsError("permission-denied", "Only creators and captains can change roles");
    }
    // MVP: Only allow scout <-> sergeant changes
    // Captain assignment and creator changes not included in MVP
    if (newRole !== "scout" && newRole !== "sergeant") {
        throw new functions.https.HttpsError("invalid-argument", "MVP only supports scout and sergeant roles");
    }
    // Get target member
    const targetMemberDoc = await db
        .collection(`families/${familyId}/members`)
        .doc(memberId)
        .get();
    if (!targetMemberDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Member not found");
    }
    const currentRole = targetMemberDoc.data().role;
    // Can't change creator or captain roles in MVP
    if (currentRole === "creator" || currentRole === "captain") {
        throw new functions.https.HttpsError("permission-denied", "Cannot change creator or captain roles");
    }
    // Update role
    await targetMemberDoc.ref.update({
        role: newRole,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FAMILY_ROLE_CHANGED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: { memberId, oldRole: currentRole, newRole },
    });
    return { success: true };
});
/**
 * Inactivate a family (creator only)
 * Marks family as inactive, removes all members, and clears activeFamilyId
 */
exports.inactivateFamily = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { familyId } = data;
    const userId = context.auth.uid;
    if (!familyId) {
        throw new functions.https.HttpsError("invalid-argument", "familyId is required");
    }
    // Verify user is the creator
    const familyDoc = await db.collection("families").doc(familyId).get();
    if (!familyDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Family not found");
    }
    const familyData = familyDoc.data();
    if (familyData.creatorId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "Only the creator can inactivate the family");
    }
    // Verify family is active
    if (familyData.status !== "active") {
        throw new functions.https.HttpsError("failed-precondition", "Family is already inactive");
    }
    const batch = db.batch();
    // Mark family as inactive
    batch.update(familyDoc.ref, {
        status: "inactive",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Get all members
    const membersSnapshot = await db
        .collection(`families/${familyId}/members`)
        .get();
    // Remove all members and clear activeFamilyId
    for (const memberDoc of membersSnapshot.docs) {
        const memberId = memberDoc.id;
        // Remove member
        batch.delete(memberDoc.ref);
        // Clear activeFamilyId if not retired general
        const userDoc = await db.collection("users").doc(memberId).get();
        const userData = userDoc.data();
        if (userData && !userData.isRetiredGeneral) {
            batch.update(db.collection("users").doc(memberId), {
                activeFamilyId: admin.firestore.FieldValue.delete(),
            });
        }
    }
    await batch.commit();
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_FAMILY_INACTIVATED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: {
            reason: "creator_inactivated",
            familyName: familyData.name,
        },
    });
    return { success: true };
});
//# sourceMappingURL=family.js.map