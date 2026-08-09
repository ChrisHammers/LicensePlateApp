import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertRegisteredAccount } from "./callableAuth";
import { familyMembershipLeaveUserUpdate } from "./wasEverInFamilyUserUpdates";
import { clearAllSearchIndexesForUser, PRIVATE_CONTACT_DOC } from "./userSearchIndex";
import { normalizeEmail, normalizePhoneE164, normalizeUsernameLower } from "./userSearchCore";
import {
  RECENT_LOGIN_MAX_AGE_SECONDS,
  isRecentLogin,
  familyCleanupAction,
  decrementedFriendCount,
  otherFriendUserId,
} from "./accountDeletionCore";

const db = admin.firestore();

const DELETE_BATCH_LIMIT = 450; // stay under Firestore's 500-op batch cap

async function deleteSubcollectionDocs(
  parentRef: admin.firestore.DocumentReference,
  subcollectionId: string
): Promise<number> {
  const docRefs = await parentRef.collection(subcollectionId).listDocuments();
  for (let start = 0; start < docRefs.length; start += DELETE_BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of docRefs.slice(start, start + DELETE_BATCH_LIMIT)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
  return docRefs.length;
}

/**
 * In-app account deletion (App Review Guideline 5.1.1(v); Privacy Policy §11, ToS §15).
 * Deletes the caller's Firebase Auth user and their personal cloud data:
 * users/{uid} (incl. fcmToken fields), users/{uid}/private/* (incl. the contact doc
 * holding email/phoneNumber), search lookup indexes, friend edges (+friendCount on the
 * surviving side), family membership, user_progression, user_achievements, and
 * public_lifetime_stats. Shared trip/gameplay events are retained de-identified so other
 * participants' trips keep working (Privacy Policy §9).
 *
 * Requires a recent sign-in (auth_time within RECENT_LOGIN_MAX_AGE_SECONDS); otherwise
 * throws failed-precondition with details.reason = "recent-login-required" so the client
 * can prompt re-authentication and retry.
 */
export const deleteAccount = enforcedCallable(async (data, context) => {
  const userId = assertRegisteredAccount(context);
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  const authTimeSeconds = Number(context.auth?.token?.auth_time ?? 0);
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!isRecentLogin(authTimeSeconds, nowSeconds, RECENT_LOGIN_MAX_AGE_SECONDS)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Recent sign-in is required to delete your account",
      { reason: "recent-login-required" }
    );
  }

  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  const userData = userDoc.data() ?? {};

  // ---- Friend edges (both directions) + friendCount on the surviving side
  const [edgesAsA, edgesAsB] = await Promise.all([
    db.collection("friends").where("userA", "==", userId).get(),
    db.collection("friends").where("userB", "==", userId).get(),
  ]);
  const edgeDocsByPath = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const doc of [...edgesAsA.docs, ...edgesAsB.docs]) {
    edgeDocsByPath.set(doc.ref.path, doc);
  }

  let removedFriendEdgeCount = 0;
  for (const edgeDoc of edgeDocsByPath.values()) {
    const batch = db.batch();
    batch.delete(edgeDoc.ref);

    const otherUserId = otherFriendUserId(edgeDoc.data(), userId);
    if (otherUserId) {
      const otherUserRef = db.collection("users").doc(otherUserId);
      const otherUserDoc = await otherUserRef.get();
      if (otherUserDoc.exists) {
        batch.update(otherUserRef, {
          friendCount: decrementedFriendCount(otherUserDoc.data()?.friendCount),
        });
      }
    }

    await batch.commit();
    removedFriendEdgeCount += 1;
  }

  // ---- Family membership (creator takes the active family down; others just leave)
  const activeFamilyId =
    typeof userData.activeFamilyId === "string" && userData.activeFamilyId.length > 0
      ? userData.activeFamilyId
      : null;
  let familyAction = "none";

  if (activeFamilyId) {
    const familyRef = db.collection("families").doc(activeFamilyId);
    const familyDoc = await familyRef.get();
    const memberRef = familyRef.collection("members").doc(userId);
    const memberDoc = await memberRef.get();

    const familyData = familyDoc.exists ? familyDoc.data()! : null;
    familyAction = familyCleanupAction({
      isMember: memberDoc.exists,
      isCreator: familyData?.creatorId === userId,
      familyStatus: typeof familyData?.status === "string" ? familyData.status : null,
    });

    if (familyAction === "inactivate_family" && familyDoc.exists) {
      // Mirrors inactivateFamily / onAuthUserDeleted: mark inactive, remove all
      // members, and clear activeFamilyId (sticky wasEverInFamily) for the others.
      const batch = db.batch();
      batch.update(familyRef, {
        status: "inactive",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const membersSnapshot = await familyRef.collection("members").get();
      for (const member of membersSnapshot.docs) {
        batch.delete(member.ref);

        if (member.id === userId) continue; // own user doc is deleted below
        const memberUserDoc = await db.collection("users").doc(member.id).get();
        const memberUserData = memberUserDoc.data();
        if (memberUserData) {
          batch.update(
            db.collection("users").doc(member.id),
            familyMembershipLeaveUserUpdate({
              isRetiredGeneral: !!memberUserData.isRetiredGeneral,
            })
          );
        }
      }

      await batch.commit();

      await writeAuditLog({
        eventType: "AUDIT_FAMILY_INACTIVATED",
        actorId: userId,
        subjectType: "family",
        subjectId: activeFamilyId,
        metadata: {
          reason: "creator_account_deleted",
          familyName: familyData?.name,
        },
        clientMetadata,
      });
    } else if (familyAction === "remove_member") {
      await memberRef.delete();
    }
  }

  // ---- Search lookup indexes (usernames / user_lookup_email / user_lookup_phone)
  const contactDoc = await userRef
    .collection("private")
    .doc(PRIVATE_CONTACT_DOC)
    .get();
  const contactData = contactDoc.data() ?? {};
  const emailHint =
    (typeof contactData.email === "string" ? contactData.email : null) ??
    (typeof userData.email === "string" ? userData.email : null);
  const phoneHint =
    (typeof contactData.phoneNumber === "string" ? contactData.phoneNumber : null) ??
    (typeof userData.phoneNumber === "string" ? userData.phoneNumber : null);
  await clearAllSearchIndexesForUser(userId, {
    userNameLower:
      (typeof userData.userNameLower === "string" ? userData.userNameLower : null) ??
      (typeof userData.userName === "string"
        ? normalizeUsernameLower(userData.userName)
        : null),
    emailLower:
      typeof contactData.emailLower === "string"
        ? contactData.emailLower
        : emailHint
          ? normalizeEmail(emailHint)
          : null,
    phoneE164:
      typeof contactData.phoneE164 === "string"
        ? contactData.phoneE164
        : phoneHint
          ? normalizePhoneE164(phoneHint)
          : null,
  });

  // ---- users/{uid}/private/* (contact email/phoneNumber, login locations, ...)
  await deleteSubcollectionDocs(userRef, "private");

  // ---- Progression / achievements / public stats keyed by uid
  const progressionRef = db.collection("user_progression").doc(userId);
  await deleteSubcollectionDocs(progressionRef, "xp_grants");
  await progressionRef.delete();

  const achievementsRef = db.collection("user_achievements").doc(userId);
  await deleteSubcollectionDocs(achievementsRef, "achievements");
  await achievementsRef.delete();

  await db.collection("public_lifetime_stats").doc(userId).delete();

  // ---- users/{uid} itself (includes fcmToken / fcmTokenUpdatedAt fields)
  await userRef.delete();

  await writeAuditLog({
    eventType: "AUDIT_ACCOUNT_DELETED",
    actorId: userId,
    subjectType: "user",
    subjectId: userId,
    metadata: {
      removedFriendEdgeCount,
      familyAction,
    },
    clientMetadata,
  });

  // ---- Firebase Auth user last so a failed cleanup above stays retryable.
  // onAuthUserDeleted then sweeps any other active families this user created.
  await admin.auth().deleteUser(userId);

  return { success: true };
});
