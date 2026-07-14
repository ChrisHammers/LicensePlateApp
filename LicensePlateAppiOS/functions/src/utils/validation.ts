import * as admin from "firebase-admin";

const db = admin.firestore();

export interface RoleCounts {
  captains: number;
  scoutsSergeants: number;
  retiredGenerals: number;
}

/**
 * Get role counts for a family
 */
export async function getFamilyRoleCounts(
  familyId: string
): Promise<RoleCounts> {
  const membersRef = db.collection(`families/${familyId}/members`);
  const snapshot = await membersRef.get();

  let captains = 0;
  let scoutsSergeants = 0;
  let retiredGenerals = 0;

  snapshot.forEach((doc) => {
    const role = doc.data().role;
    if (role === "captain") {
      captains++;
    } else if (role === "scout" || role === "sergeant") {
      scoutsSergeants++;
    } else if (role === "retired_general") {
      retiredGenerals++;
    }
  });

  return { captains, scoutsSergeants, retiredGenerals };
}

/**
 * Check if user can be added to family based on role limits
 */
export async function canAddMemberToFamily(
  familyId: string,
  newRole: string,
  userId: string
): Promise<{ canAdd: boolean; reason?: string }> {
  const counts = await getFamilyRoleCounts(familyId);

  // Check role-specific limits
  if (newRole === "captain" && counts.captains >= 2) {
    return { canAdd: false, reason: "Maximum 2 captains allowed" };
  }

  if (
    (newRole === "scout" || newRole === "sergeant") &&
    counts.scoutsSergeants >= 4
  ) {
    return { canAdd: false, reason: "Maximum 4 scouts/sergeants combined" };
  }

  if (newRole === "retired_general" && counts.retiredGenerals >= 4) {
    return { canAdd: false, reason: "Maximum 4 retired generals allowed" };
  }

  // Check if user is already in an active family (unless retired general)
  const userDoc = await db.collection("users").doc(userId).get();
  const userData = userDoc.data();

  if (!userData?.isRetiredGeneral) {
    if (userData?.activeFamilyId && userData.activeFamilyId !== familyId) {
      return {
        canAdd: false,
        reason: "User is already in another active family",
      };
    }
  }

  return { canAdd: true };
}

/**
 * Check if user has reached friend cap (100)
 */
export async function checkFriendCap(
  userId: string
): Promise<{ canAdd: boolean; currentCount: number }> {
  const userDoc = await db.collection("users").doc(userId).get();
  const friendCount = userDoc.data()?.friendCount || 0;

  return {
    canAdd: friendCount < 100,
    currentCount: friendCount,
  };
}

/**
 * Check if user is searchable by email/phone.
 * Prefers privacy.emailSearchable / phoneSearchable when present; falls back to
 * legacy top-level isEmailPublic / isPhonePublic for older docs.
 */
export async function isUserSearchable(
  userId: string,
  searchType: "email" | "phone"
): Promise<boolean> {
  const userDoc = await db.collection("users").doc(userId).get();
  const data = userDoc.data() || {};
  const privacy = data.privacy || {};

  if (searchType === "email") {
    if (typeof privacy.emailSearchable === "boolean") {
      return privacy.emailSearchable === true;
    }
    return data.isEmailPublic === true;
  } else {
    if (typeof privacy.phoneSearchable === "boolean") {
      return privacy.phoneSearchable === true;
    }
    return data.isPhonePublic === true;
  }
}

const recipientNotRegisteredMessage =
  "Recipient has not created a registered account";

/**
 * Rejects invite targets that have not upgraded from an anonymous account.
 * Missing `isRegistered` is treated as registered (legacy users).
 */
export async function assertUserIsRegistered(userId: string): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new Error("User not found");
  }
  if (userDoc.data()?.isRegistered === false) {
    throw new Error(recipientNotRegisteredMessage);
  }
}

export { recipientNotRegisteredMessage };
