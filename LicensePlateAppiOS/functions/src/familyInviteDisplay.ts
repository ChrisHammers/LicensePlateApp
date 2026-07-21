/**
 * Minimal family invite display: stamp familyName only.
 * Inviter identity comes from invite.fromUserId + client getUser.
 */

import * as admin from "firebase-admin";

/**
 * Load the family's display name for invite denormalization.
 */
export async function loadFamilyName(
  familyId: string
): Promise<string | null> {
  const db = admin.firestore();
  const familySnap = await db.collection("families").doc(familyId).get();
  if (!familySnap.exists) {
    return null;
  }
  const name = familySnap.data()?.name;
  if (typeof name !== "string") {
    return null;
  }
  const trimmed = name.trim();
  return trimmed.length > 0 ? trimmed : null;
}
