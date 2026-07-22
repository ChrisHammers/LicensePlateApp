import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { familyMembershipLeaveUserUpdate } from "./wasEverInFamilyUserUpdates";

const db = admin.firestore();

/**
 * Handle user deletion - inactivate family if creator
 */
export const onAuthUserDeleted = functions.auth
  .user()
  .onDelete(async (user) => {
    const userId = user.uid;

    // Check if user is a family creator
    const familiesSnapshot = await db
      .collection("families")
      .where("creatorId", "==", userId)
      .where("status", "==", "active")
      .get();

    const batch = db.batch();

    for (const familyDoc of familiesSnapshot.docs) {
      const familyId = familyDoc.id;
      const familyData = familyDoc.data();

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

      await writeAuditLog({
        eventType: "AUDIT_FAMILY_INACTIVATED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: {
          reason: "creator_deleted",
          familyName: familyData.name,
        },
      });
    }

    await batch.commit();

    console.log(
      `Inactivated ${familiesSnapshot.size} families due to creator deletion`
    );

    return null;
  });

