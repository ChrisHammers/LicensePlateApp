import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { canAddMemberToFamily, assertUserIsRegistered, recipientNotRegisteredMessage, isUserSearchable } from "./utils/validation";
import { writeAuditLog } from "./audit";
import { auditValueHash } from "./auditRedaction";
import { getFCMTokenForSocialPush, sendPushNotification } from "./utils/notifications";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertRegisteredAccount } from "./callableAuth";
import { loadFamilyName } from "./familyInviteDisplay";
import {
  PENDING_FAMILY_INVITE_EXISTS_MESSAGE,
  shouldRejectDuplicatePendingFamilyInvite,
} from "./familyInviteDuplicate";
import {
  familyMembershipGrantUserUpdate,
  familyMembershipLeaveUserUpdate,
} from "./wasEverInFamilyUserUpdates";
import { canRemoveFamilyMember } from "./familyMemberRemovalPolicy";
import {
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
  CORRECTION_REASON_NEW_GUARDIAN_CLEARED,
  evaluateApprovalChildDeclaration,
  isChildWithActiveFamilyUserData,
  sanitizedChildLinkedPlatforms,
} from "./childAccountCore";
import {
  writeChildConsentCorrected,
  writeChildConsentGranted,
  writeChildMembershipRevocation,
} from "./childConsent";
import { applyChildProtectionsAfterFlagSet } from "./familyChildStatusFlows";
import { assertCallerIsNotChild } from "./childAccessGuards";

const db = admin.firestore();

/**
 * Create a new family
 */
export const createFamily = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { name } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!name || typeof name !== "string" || name.trim().length === 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Family name is required"
      );
    }

    // FR-24 (COPPA F-5b): a child cannot found a family — that would make them their own
    // consenting manager (§4: parent/manager = creator|captain) and hand them the
    // authority to admit strangers.
    await assertCallerIsNotChild(db, userId);

    // Check if user already has an active family (unless retired general)
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data()!;
    
    if (!userData.isRetiredGeneral && userData.activeFamilyId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "User already has an active family"
      );
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

    await db.collection("users").doc(userId).update(
      familyMembershipGrantUserUpdate({
        familyId: familyRef.id,
        isRetiredGeneral: !!userData.isRetiredGeneral,
      })
    );

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_CREATED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyRef.id,
      metadata: { name: name.trim() },
      clientMetadata,
    });

    return { familyId: familyRef.id };
  }
);

/**
 * Send a family invite
 */
export const sendFamilyInvite = enforcedCallable(
  async (data, context) => {
    const fromUserId = assertRegisteredAccount(context);

    const { toUserId, familyId, method } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!toUserId || !familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "toUserId and familyId are required"
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

    // FR-24 (COPPA F-5b): a child never sends family invites. Managers are creators or
    // captains and no MVP path makes a child either, but the guard is the server-side
    // backstop behind the client hiding the control.
    await assertCallerIsNotChild(db, fromUserId);

    // Verify sender is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(fromUserId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can invite"
      );
    }

    // Get target user to determine role
    const targetUserDoc = await db.collection("users").doc(toUserId).get();
    if (!targetUserDoc.exists) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const targetUserData = targetUserDoc.data()!;

    // FR-15 (COPPA F-5b): a child who already belongs to a parent-managed family may not be
    // invited into another one — that would swap their consenting manager without any
    // consent capture. Checked on EVERY method (including `search`, which skips the
    // email/phone privacy gate below) and worded exactly like the privacy opt-out so the
    // sender cannot infer the target is a child. Inviting an UNCONSENTED child (flag true,
    // no active family) stays allowed: that is the path back to consented play.
    if (isChildWithActiveFamilyUserData(targetUserData)) {
      await writeAuditLog({
        eventType: "invite_auto_rejected_not_searchable",
        actorId: fromUserId,
        subjectType: "user",
        subjectId: toUserId,
        metadata: { familyId, method: method || "search" },
        clientMetadata,
      });
      throw new functions.https.HttpsError(
        "permission-denied",
        CHILD_TARGET_NOT_SEARCHABLE_MESSAGE
      );
    }

    const newRole = targetUserData.isRetiredGeneral
      ? "retired_general"
      : "scout"; // Default to scout for new members

    // Check if user can be added
    const canAdd = await canAddMemberToFamily(familyId, newRole, toUserId);
    if (!canAdd.canAdd) {
      await writeAuditLog({
        eventType: "invite_auto_rejected_user_already_in_family",
        actorId: fromUserId,
        subjectType: "user",
        subjectId: toUserId,
        metadata: { familyId, reason: canAdd.reason },
        clientMetadata,
      });
      throw new functions.https.HttpsError(
        "failed-precondition",
        canAdd.reason || "Cannot add user to family"
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
          metadata: { familyId, method },
          clientMetadata,
        });
        throw new functions.https.HttpsError(
          "permission-denied",
          "User is not searchable by this method"
        );
      }
    }

    // Reject duplicate pending invites for the same family + invitee (any captain/creator)
    const existingInvite = await db
      .collection("invites")
      .where("familyId", "==", familyId)
      .where("toUserId", "==", toUserId)
      .where("type", "==", "family")
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (shouldRejectDuplicatePendingFamilyInvite(existingInvite.empty)) {
      throw new functions.https.HttpsError(
        "already-exists",
        PENDING_FAMILY_INVITE_EXISTS_MESSAGE
      );
    }

    // Create invite
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 15);

    const familyName = await loadFamilyName(familyId);

    const inviteData: Record<string, unknown> = {
      type: "family",
      fromUserId,
      toUserId,
      familyId,
      status: "pending",
      method: method || "search",
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (familyName) {
      inviteData.familyName = familyName;
    }

    const inviteRef = await db.collection("invites").add(inviteData);

    // Send push notification (gated by recipient notificationPrefs.family)
    const fcmToken = await getFCMTokenForSocialPush(toUserId, "family");
    if (fcmToken) {
      await sendPushNotification(
        fcmToken,
        "Family Invitation",
        familyName
          ? `You've been invited to join ${familyName}`
          : "You've been invited to join a family",
        {
          type: "family_invite",
          inviteId: inviteRef.id,
          familyId,
          deepLink: `roadtrip-royale://invite/family?inviteId=${inviteRef.id}&familyId=${familyId}`,
        }
      );
    }

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_INVITE_SENT",
      actorId: fromUserId,
      subjectType: "invite",
      subjectId: inviteRef.id,
      metadata: { toUserId, familyId, method },
      clientMetadata,
    });

    return { inviteId: inviteRef.id };
  }
);

/**
 * User accepts family invite (step 1) - creates pending request
 */
export const respondToFamilyInvite_UserStep = enforcedCallable(
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

    let pendingRequestId: string | null = null;
    const familyId =
      typeof inviteData.familyId === "string" ? inviteData.familyId : null;

    if (response === "accept") {
      if (!familyId) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Invite is missing familyId"
        );
      }

      // Create pending join request (awaiting captain approval)
      const requestData = {
        userId,
        requestedBy: inviteData.fromUserId,
        method: inviteData.method,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const requestRef = db.collection(`families/${familyId}/pending`).doc();
      pendingRequestId = requestRef.id;

      batch.set(requestRef, requestData);

      await writeAuditLog({
        eventType: "family_join_request_created",
        actorId: userId,
        subjectType: "invite",
        subjectId: inviteId,
        metadata: { familyId },
        clientMetadata,
      });
    }

    await batch.commit();

    // Notify creators/captains that a join request needs approval (Family pref gated).
    if (response === "accept" && familyId && pendingRequestId) {
      await notifyFamilyManagersOfJoinRequest({
        familyId,
        requestId: pendingRequestId,
        requesterUserId: userId,
      });
    }

    return { success: true };
  }
);

/**
 * FCM creators/captains when someone accepts an invite and needs approval.
 */
async function notifyFamilyManagersOfJoinRequest(args: {
  familyId: string;
  requestId: string;
  requesterUserId: string;
}): Promise<void> {
  const { familyId, requestId, requesterUserId } = args;
  const membersSnap = await db.collection(`families/${familyId}/members`).get();
  const managerIds: string[] = [];
  membersSnap.forEach((doc) => {
    const role = doc.data().role;
    if (role === "creator" || role === "captain") {
      managerIds.push(doc.id);
    }
  });

  const deepLink = `roadtrip-royale://family/${familyId}/pending`;
  await Promise.all(
    managerIds.map(async (managerId) => {
      if (managerId === requesterUserId) {
        return;
      }
      const fcmToken = await getFCMTokenForSocialPush(managerId, "family");
      if (!fcmToken) {
        return;
      }
      try {
        await sendPushNotification(
          fcmToken,
          "Family Join Request",
          "Someone wants to join your family",
          {
            type: "family_join_request",
            familyId,
            requestId,
            deepLink,
          }
        );
      } catch (error) {
        console.error(
          `Error sending family_join_request push to ${managerId}:`,
          error
        );
      }
    })
  );
}

/**
 * Captain approves family join request (step 2) - adds member
 */
export const approveFamilyJoinRequest_CaptainStep = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, requestId, response } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !requestId || !response) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId, requestId, and response are required"
      );
    }

    if (response !== "approve" && response !== "decline") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Response must be 'approve' or 'decline'"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can approve requests"
      );
    }

    // Get request
    const requestDoc = await db
      .collection(`families/${familyId}/pending`)
      .doc(requestId)
      .get();

    if (!requestDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Request not found");
    }

    const requestData = requestDoc.data()!;

    if (requestData.status !== "pending") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Request already resolved"
      );
    }

    const batch = db.batch();

    // COPPA FR-25: child follow-ons that must run only after the membership batch
    // commits (index purge, invite/friend cleanup, consent record).
    let childFollowUp:
      | { kind: "grant"; expectedAgeOutYear?: number; targetUserData: Record<string, unknown> }
      | { kind: "clear_new_guardian" }
      | null = null;

    if (response === "approve") {
      // Get target user to determine role
      const targetUserDoc = await db
        .collection("users")
        .doc(requestData.userId)
        .get();

      if (!targetUserDoc.exists) {
        throw new functions.https.HttpsError("not-found", "User not found");
      }

      const targetUserData = targetUserDoc.data()!;
      const newRole = targetUserData.isRetiredGeneral
        ? "retired_general"
        : "scout";

      // COPPA FR-1 / FR-25: the approval payload may (and, for sticky targets, MUST)
      // declare the member's child status. `isChild: true` is a consent capture and
      // requires both acknowledgments (FR-31); `isChild: false` on a flagged target is
      // the new-guardian correction. Absent `isChild` on a flagged target is rejected —
      // a child flag is never silently laundered through re-admission.
      const childDecision = evaluateApprovalChildDeclaration({
        payloadIsChild: data?.isChild,
        consentAcknowledged: data?.consentAcknowledged,
        guardianAffirmed: data?.guardianAffirmed,
        expectedAgeOutYear: data?.expectedAgeOutYear,
        targetIsChildAccount: targetUserData.isChildAccount === true,
        nowYear: new Date().getUTCFullYear(),
      });
      if (childDecision.kind === "reject") {
        throw new functions.https.HttpsError(childDecision.code, childDecision.message);
      }
      if (childDecision.kind === "grant") {
        childFollowUp = {
          kind: "grant",
          expectedAgeOutYear: childDecision.expectedAgeOutYear,
          targetUserData,
        };
      } else if (childDecision.kind === "clear_new_guardian") {
        childFollowUp = { kind: "clear_new_guardian" };
      }

      // Check if user can still be added (limits may have changed)
      const canAdd = await canAddMemberToFamily(
        familyId,
        newRole,
        requestData.userId
      );
      if (!canAdd.canAdd) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          canAdd.reason || "Cannot add user to family"
        );
      }

      // Add member
      const memberData: Record<string, unknown> = {
        role: newRole,
        permissions: {
          canInvite: false,
          canEditSettings: false,
        },
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (childDecision.kind === "grant") {
        memberData.isChild = true; // server-written projection (§7.2)
      } else if (childDecision.kind === "clear_new_guardian") {
        memberData.isChild = false;
      }

      batch.set(
        db.collection(`families/${familyId}/members`).doc(requestData.userId),
        memberData
      );

      // Sticky family unlock + activeFamilyId (skip activeFamilyId for retired general).
      // FR-4/FR-25: the child flag and the FR-35(b) linkedPlatforms strip ride the same
      // batched user update as the membership grant.
      const grantUpdate = familyMembershipGrantUserUpdate({
        familyId,
        isRetiredGeneral: !!targetUserData.isRetiredGeneral,
        isChild:
          childDecision.kind === "grant"
            ? true
            : childDecision.kind === "clear_new_guardian"
              ? false
              : undefined,
      });
      if (childDecision.kind === "grant") {
        const linkedPlatforms = sanitizedChildLinkedPlatforms(
          targetUserData.linkedPlatforms
        );
        if (linkedPlatforms && linkedPlatforms.changed) {
          grantUpdate.linkedPlatforms = linkedPlatforms.sanitized;
        }
      }
      batch.update(
        db.collection("users").doc(requestData.userId),
        grantUpdate
      );

      // Update request status
      batch.update(requestDoc.ref, {
        status: "approved",
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Retire the matching accepted invite, mirroring the decline branch: left in
      // "accepted" forever, it reads as a live "awaiting approval" request on the
      // requester's dashboard after they later leave or are removed (F-8 bug B).
      const approvedMatchingInvites = await db
        .collection("invites")
        .where("familyId", "==", familyId)
        .where("toUserId", "==", requestData.userId)
        .where("type", "==", "family")
        .where("status", "==", "accepted")
        .limit(5)
        .get();

      for (const inviteDoc of approvedMatchingInvites.docs) {
        // "expired" (not a new status): the client parses unknown statuses as
        // .pending, which would resurrect the invite as live. Expired is terminal
        // client-side and the retention job cleans it up.
        batch.update(inviteDoc.ref, {
          status: "expired",
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Send push notification (gated by recipient notificationPrefs.family)
      const fcmToken = await getFCMTokenForSocialPush(requestData.userId, "family");
      if (fcmToken) {
        await sendPushNotification(
          fcmToken,
          "Family Request Approved",
          "You've been approved to join the family",
          {
            type: "family_join_approved",
            familyId,
            deepLink: `roadtrip-royale://family/${familyId}`,
          }
        );
      }

      await writeAuditLog({
        eventType: "AUDIT_FAMILY_JOIN_APPROVED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: { newMemberId: requestData.userId, role: newRole },
        clientMetadata,
      });
    } else {
      // Decline request — also flip the matching accepted invite so the requester's empty dashboard clears
      batch.update(requestDoc.ref, {
        status: "declined",
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const matchingInvites = await db
        .collection("invites")
        .where("familyId", "==", familyId)
        .where("toUserId", "==", requestData.userId)
        .where("type", "==", "family")
        .where("status", "==", "accepted")
        .limit(5)
        .get();

      for (const inviteDoc of matchingInvites.docs) {
        batch.update(inviteDoc.ref, {
          status: "declined",
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await writeAuditLog({
        eventType: "family_join_request_declined",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: {
          requestId,
          userId: requestData.userId,
          declinedInviteCount: matchingInvites.size,
        },
        clientMetadata,
      });
    }

    await batch.commit();

    // COPPA FR-4/FR-25 follow-ons (non-atomic, idempotent; the F-5b syncer exclusion is
    // the purge backstop). Runs only after the membership batch has committed.
    if (childFollowUp?.kind === "grant") {
      const membersSnapshot = await db
        .collection(`families/${familyId}/members`)
        .get();
      const cleanup = await applyChildProtectionsAfterFlagSet(db, {
        childUserId: requestData.userId,
        familyMemberIds: membersSnapshot.docs.map((doc) => doc.id),
        childUserData: childFollowUp.targetUserData,
      });

      await writeChildConsentGranted(db, {
        familyId,
        childUserId: requestData.userId,
        actorId: userId,
        actorRole: memberRole,
        method: "family_admission",
        expectedAgeOutYear: childFollowUp.expectedAgeOutYear,
        removedFriendEdgeCount: cleanup.removedFriendEdgeCount,
        clientMetadata,
      });
    } else if (childFollowUp?.kind === "clear_new_guardian") {
      // FR-25: new guardian explicitly declared not-a-child. Flag already cleared in the
      // batch; search indexes rebuild via the normal profile-sync triggers.
      await writeChildConsentCorrected(db, {
        familyId,
        childUserId: requestData.userId,
        actorId: userId,
        actorRole: memberRole,
        method: "readmission_declaration",
        reason: CORRECTION_REASON_NEW_GUARDIAN_CLEARED,
        clientMetadata,
      });
    }

    return { success: true };
  }
);

/**
 * Remove a family member
 */
export const removeFamilyMember = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, memberId } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !memberId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId and memberId are required"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;

    // Get member to remove
    const targetMemberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(memberId)
      .get();

    if (!targetMemberDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Member not found");
    }

    const targetMemberRole = targetMemberDoc.data()!.role;
    // COPPA FR-6: detect the child projection BEFORE the member doc is deleted.
    const targetWasChild = targetMemberDoc.data()!.isChild === true;
    const isSelf = memberId === userId;
    const decision = canRemoveFamilyMember({
      actorRole: memberRole,
      targetRole: targetMemberRole,
      isSelf,
    });
    if (!decision.allowed) {
      throw new functions.https.HttpsError(decision.code, decision.message);
    }

    const batch = db.batch();

    // Remove member
    batch.delete(targetMemberDoc.ref);

    // Clear activeFamilyId if not retired general; sticky-flag for legacy members
    const userDoc = await db.collection("users").doc(memberId).get();
    const userData = userDoc.data();
    if (userData) {
      batch.update(
        db.collection("users").doc(memberId),
        familyMembershipLeaveUserUpdate({
          isRetiredGeneral: !!userData.isRetiredGeneral,
        })
      );
    }

    await batch.commit();

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_MEMBER_REMOVED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: { removedMemberId: memberId, role: targetMemberRole },
      clientMetadata,
    });

    // COPPA FR-6: a flagged child's membership just ended — consent is revoked, the
    // sticky `isChildAccount` flag is untouched (protection persists, collection stops).
    if (targetWasChild) {
      await writeChildMembershipRevocation(db, {
        familyId,
        childUserId: memberId,
        actorId: userId,
        actorRole: isSelf ? targetMemberRole : memberRole,
        method: "remove_family_member",
        reason: isSelf ? "member_left_family" : "parent_removed_child",
        clientMetadata,
      });
    }

    return { success: true };
  }
);

/**
 * Change a family member's role
 */
export const changeFamilyMemberRole = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, memberId, newRole } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !memberId || !newRole) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId, memberId, and newRole are required"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can change roles"
      );
    }

    // MVP: Only allow scout <-> sergeant changes
    // Captain assignment and creator changes not included in MVP
    if (newRole !== "scout" && newRole !== "sergeant") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "MVP only supports scout and sergeant roles"
      );
    }

    // Get target member
    const targetMemberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(memberId)
      .get();

    if (!targetMemberDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Member not found");
    }

    const currentRole = targetMemberDoc.data()!.role;

    // Can't change creator or captain roles in MVP
    if (currentRole === "creator" || currentRole === "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Cannot change Captain roles"
      );
    }

    // Update role
    await targetMemberDoc.ref.update({
      role: newRole,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_ROLE_CHANGED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: { memberId, oldRole: currentRole, newRole },
      clientMetadata,
    });

    return { success: true };
  }
);

/**
 * Inactivate a family (creator only)
 * Marks family as inactive, removes all members, and clears activeFamilyId
 */
export const inactivateFamily = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId is required"
      );
    }

    // Verify user is the creator
    const familyDoc = await db.collection("families").doc(familyId).get();
    if (!familyDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Family not found");
    }

    const familyData = familyDoc.data()!;
    if (familyData.creatorId !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the Captain who created the family can delete it"
      );
    }

    // Verify family is active
    if (familyData.status !== "active") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Family is already inactive"
      );
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

    // COPPA FR-6: capture flagged children BEFORE their member docs are deleted.
    const childMemberIds: string[] = [];

    // Remove all members and clear activeFamilyId
    for (const memberDoc of membersSnapshot.docs) {
      const memberId = memberDoc.id;

      if (memberDoc.data()?.isChild === true) {
        childMemberIds.push(memberId);
      }

      // Remove member
      batch.delete(memberDoc.ref);

      // Clear activeFamilyId if not retired general; sticky-flag for legacy members
      const userDoc = await db.collection("users").doc(memberId).get();
      const userData = userDoc.data();
      if (userData) {
        batch.update(
          db.collection("users").doc(memberId),
          familyMembershipLeaveUserUpdate({
            isRetiredGeneral: !!userData.isRetiredGeneral,
          })
        );
      }
    }

    await batch.commit();

    // COPPA FR-6: every flagged child's membership ended with the family; consent is
    // revoked while the sticky `isChildAccount` flag stays true.
    for (const childUserId of childMemberIds) {
      await writeChildMembershipRevocation(db, {
        familyId,
        childUserId,
        actorId: userId,
        actorRole: "creator",
        method: "inactivate_family",
        reason: "family_inactivated",
        clientMetadata,
      });
    }

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_INACTIVATED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: {
        reason: "creator_inactivated",
        familyNameHash: auditValueHash(familyData.name),
      },
      clientMetadata,
    });

    return { success: true };
  }
);

