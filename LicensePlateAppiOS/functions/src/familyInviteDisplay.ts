/**
 * Denormalized display fields stamped onto family invite docs so invitees
 * can render name / creator / captains without reading member-only families/.
 */

import * as admin from "firebase-admin";
import { buildDisplayName } from "./userSearchCore";

export type FamilyInviteCaptainPreview = {
  displayName: string;
  userName: string;
  role: "creator" | "captain";
  avatarId: string | null;
  userId: string;
};

export type FamilyInviteDisplaySnapshot = {
  familyName: string;
  creatorDisplayName: string;
  creatorUserName: string;
  creatorAvatarId: string | null;
  fromUserDisplayName: string;
  fromUserUserName: string;
  fromUserAvatarId: string | null;
  /** JSON string for SwiftData storage */
  captainsPreviewJSON: string;
  /** Native array for Firestore clients / debugging */
  captainsPreview: FamilyInviteCaptainPreview[];
};

type UserDocData = Record<string, unknown> | undefined;

function userNameFromData(data: UserDocData): string {
  if (!data) return "";
  if (typeof data.userName === "string" && data.userName) return data.userName;
  if (typeof data.username === "string" && data.username) return data.username;
  return "";
}

function avatarIdFromData(data: UserDocData): string | null {
  if (typeof data?.avatarId === "string" && data.avatarId.length > 0) {
    return data.avatarId;
  }
  return null;
}

function displayFieldsFromUserData(
  data: UserDocData
): { displayName: string; userName: string; avatarId: string | null } {
  const userName = userNameFromData(data);
  const displayName = buildDisplayName({
    userName,
    firstName: typeof data?.firstName === "string" ? data.firstName : null,
    lastName: typeof data?.lastName === "string" ? data.lastName : null,
  });
  return { displayName, userName, avatarId: avatarIdFromData(data) };
}

/**
 * Pure builder for unit tests — accepts already-loaded family + user docs.
 */
export function buildFamilyInviteDisplaySnapshotFromData(params: {
  familyName: string;
  creatorId: string;
  fromUserId: string;
  /** Map of userId -> user doc data */
  usersById: Record<string, UserDocData>;
  /** Members with role creator or captain (userId + role) */
  captainMembers: Array<{ userId: string; role: string }>;
}): FamilyInviteDisplaySnapshot {
  const { familyName, creatorId, fromUserId, usersById, captainMembers } =
    params;

  const creatorFields = displayFieldsFromUserData(usersById[creatorId]);
  const fromFields = displayFieldsFromUserData(usersById[fromUserId]);

  const captains: FamilyInviteCaptainPreview[] = [];
  const seen = new Set<string>();

  // Creator first, then other captains
  const ordered = [
    ...captainMembers.filter((m) => m.role === "creator"),
    ...captainMembers.filter((m) => m.role === "captain"),
  ];

  for (const member of ordered) {
    if (seen.has(member.userId)) continue;
    if (member.role !== "creator" && member.role !== "captain") continue;
    seen.add(member.userId);
    const fields = displayFieldsFromUserData(usersById[member.userId]);
    captains.push({
      displayName: fields.displayName,
      userName: fields.userName,
      role: member.role,
      avatarId: fields.avatarId,
      userId: member.userId,
    });
  }

  // Ensure creator appears even if missing from members query
  if (!seen.has(creatorId)) {
    captains.unshift({
      displayName: creatorFields.displayName,
      userName: creatorFields.userName,
      role: "creator",
      avatarId: creatorFields.avatarId,
      userId: creatorId,
    });
  }

  return {
    familyName,
    creatorDisplayName: creatorFields.displayName,
    creatorUserName: creatorFields.userName,
    creatorAvatarId: creatorFields.avatarId,
    fromUserDisplayName: fromFields.displayName,
    fromUserUserName: fromFields.userName,
    fromUserAvatarId: fromFields.avatarId,
    captainsPreviewJSON: JSON.stringify(captains),
    captainsPreview: captains,
  };
}

/**
 * Load family + captain members + user profiles and build the invite snapshot.
 */
export async function buildFamilyInviteDisplaySnapshot(
  familyId: string,
  fromUserId: string
): Promise<FamilyInviteDisplaySnapshot | null> {
  const db = admin.firestore();
  const familySnap = await db.collection("families").doc(familyId).get();
  if (!familySnap.exists) {
    return null;
  }

  const familyData = familySnap.data()!;
  const familyName =
    typeof familyData.name === "string" ? familyData.name.trim() : "";
  const creatorId =
    typeof familyData.creatorId === "string" ? familyData.creatorId : "";

  if (!familyName || !creatorId) {
    return null;
  }

  const membersSnap = await db
    .collection(`families/${familyId}/members`)
    .get();

  const captainMembers: Array<{ userId: string; role: string }> = [];
  for (const doc of membersSnap.docs) {
    const role = doc.data()?.role;
    if (role === "creator" || role === "captain") {
      captainMembers.push({ userId: doc.id, role });
    }
  }

  const userIds = new Set<string>([creatorId, fromUserId]);
  for (const m of captainMembers) {
    userIds.add(m.userId);
  }

  const usersById: Record<string, UserDocData> = {};
  await Promise.all(
    [...userIds].map(async (uid) => {
      const snap = await db.collection("users").doc(uid).get();
      usersById[uid] = snap.exists
        ? (snap.data() as Record<string, unknown>)
        : undefined;
    })
  );

  return buildFamilyInviteDisplaySnapshotFromData({
    familyName,
    creatorId,
    fromUserId,
    usersById,
    captainMembers,
  });
}
