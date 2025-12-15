import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Add a pending invitation to a user's document
 * Called when a captain invites a user to a family
 */
export const addPendingInvitation = onCall(
  {region: "us-central1"},
  async (request) => {
    // Verify user is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const {invitedUserID, familyFirebaseID, role, invitedBy, invitedAt} =
      request.data;

    // Validate input
    if (!invitedUserID || !familyFirebaseID || !role) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields"
      );
    }

    const captainUID = request.auth.uid;

    try {
      // Verify the requester is a captain of the family
      const memberDoc = await admin.firestore()
        .collection("families")
        .doc(familyFirebaseID)
        .collection("members")
        .doc(captainUID)
        .get();

      if (!memberDoc.exists) {
        throw new HttpsError(
          "permission-denied",
          "User is not a member of this family"
        );
      }

      const memberData = memberDoc.data();
      if (memberData?.role !== "captain" || !memberData?.isActive) {
        throw new HttpsError(
          "permission-denied",
          "Only captains can invite members"
        );
      }

      // Get current pending invitations
      const userDoc = await admin.firestore()
        .collection("users")
        .doc(invitedUserID)
        .get();

      if (!userDoc.exists) {
        throw new HttpsError(
          "not-found",
          "Invited user not found"
        );
      }

      const userData = userDoc.data();
      const pendingInvitations = userData?.pendingFamilyInvitations || [];

      // Check if invitation already exists
      const invitationExists = pendingInvitations.some(
        (inv: {familyFirebaseID: string}) =>
          inv.familyFirebaseID === familyFirebaseID
      );

      if (invitationExists) {
        return {success: true, message: "Invitation already exists"};
      }

      // Add new invitation
      // Parse invitedAt - can be ISO string or timestamp
      let invitedAtDate: Date;
      if (typeof invitedAt === "string") {
        invitedAtDate = new Date(invitedAt);
      } else if (invitedAt) {
        invitedAtDate = new Date(invitedAt);
      } else {
        invitedAtDate = new Date();
      }

      const newInvitation = {
        familyFirebaseID,
        role,
        invitedAt: admin.firestore.Timestamp.fromDate(invitedAtDate),
        invitedBy: invitedBy || captainUID,
      };

      pendingInvitations.push(newInvitation);

      // Update user document
      await admin.firestore()
        .collection("users")
        .doc(invitedUserID)
        .update({
          pendingFamilyInvitations: pendingInvitations,
        });

      return {success: true, message: "Invitation added successfully"};
    } catch (error: unknown) {
      console.error("Error adding pending invitation:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Failed to add invitation",
        error
      );
    }
  }
);

/**
 * Remove a pending invitation from a user's document
 * Called when:
 * - A captain cancels an invitation
 * - A user accepts/declines an invitation
 */
export const removePendingInvitation = onCall(
  {region: "us-central1"},
  async (request) => {
    // Verify user is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const {userID, familyFirebaseID} = request.data;

    // Validate input
    if (!userID || !familyFirebaseID) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields"
      );
    }

    const requesterUID = request.auth.uid;

    try {
      // Verify the requester has permission:
      // 1. They are the invited user (can accept/decline their own invitation)
      // 2. OR they are a captain of the family (can cancel invitations)
      const isInvitedUser = requesterUID === userID;

      let isCaptain = false;
      if (!isInvitedUser) {
        const memberDoc = await admin.firestore()
          .collection("families")
          .doc(familyFirebaseID)
          .collection("members")
          .doc(requesterUID)
          .get();

        if (memberDoc.exists) {
          const memberData = memberDoc.data();
          isCaptain =
            memberData?.role === "captain" && memberData?.isActive === true;
        }
      }

      if (!isInvitedUser && !isCaptain) {
        throw new HttpsError(
          "permission-denied",
          "Not authorized to remove this invitation"
        );
      }

      // Get current pending invitations
      const userDoc = await admin.firestore()
        .collection("users")
        .doc(userID)
        .get();

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data();
      const pendingInvitations = userData?.pendingFamilyInvitations || [];

      // Remove invitation
      const updatedInvitations = pendingInvitations.filter(
        (inv: {familyFirebaseID: string}) =>
          inv.familyFirebaseID !== familyFirebaseID
      );

      // Update user document
      await admin.firestore()
        .collection("users")
        .doc(userID)
        .update({
          pendingFamilyInvitations: updatedInvitations,
        });

      return {success: true, message: "Invitation removed successfully"};
    } catch (error: unknown) {
      console.error("Error removing pending invitation:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Failed to remove invitation",
        error
      );
    }
  }
);
