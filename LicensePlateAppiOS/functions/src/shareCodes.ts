import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { clientMetadataWrite, normalizeClientMetadata } from "./clientMetadata";

const db = admin.firestore();

/**
 * Generate a random 6-character alphanumeric code
 */
function generateRandomCode(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * Create a share code (friend or family type)
 * TTL: 15 minutes, multi-use
 */
export const createShareCode = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { type, familyId } = data;
    const userId = context.auth.uid;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (type !== "friend" && type !== "family") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Type must be 'friend' or 'family'"
      );
    }

    if (type === "family" && !familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId required for family codes"
      );
    }

    // Generate random code
    const code = generateRandomCode();

    // 15 minute TTL
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 15);

    const codeData: any = {
      type,
      createdBy: userId,
      code,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRevoked: false,
      ...clientMetadataWrite(clientMetadata),
    };

    if (familyId) {
      codeData.familyId = familyId;
    }

    const codeRef = await db.collection("share_codes").add(codeData);

    await writeAuditLog({
      eventType: "share_code_generated",
      actorId: userId,
      subjectType: "invite",
      subjectId: codeRef.id,
      metadata: { type, familyId },
      clientMetadata,
    });

    return {
      codeId: codeRef.id,
      code,
      expiresAt: expiresAt.toISOString(),
    };
  }
);

/**
 * Redeem a share code and create an invite
 */
export const redeemShareCode = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { code } = data;
    const userId = context.auth.uid;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!code) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Code is required"
      );
    }

    // Find code
    const codesSnapshot = await db
      .collection("share_codes")
      .where("code", "==", code)
      .limit(1)
      .get();

    if (codesSnapshot.empty) {
      throw new functions.https.HttpsError("not-found", "Code not found");
    }

    const codeDoc = codesSnapshot.docs[0];
    const codeData = codeDoc.data();

    // Check if expired or revoked
    const expiresAt = codeData.expiresAt.toDate();
    if (expiresAt < new Date() || codeData.isRevoked) {
      throw new functions.https.HttpsError("invalid-argument", "Code expired");
    }

    // Prevent self-invite
    if (codeData.createdBy === userId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Cannot use your own code"
      );
    }

    // Create invite
    const expiresAtInvite = new Date();
    expiresAtInvite.setMinutes(expiresAtInvite.getMinutes() + 15);

    const inviteData: any = {
      type: codeData.type,
      fromUserId: codeData.createdBy,
      toUserId: userId,
      status: "pending",
      method: "code",
      codeId: codeDoc.id,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAtInvite),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      ...clientMetadataWrite(clientMetadata),
    };

    if (codeData.familyId) {
      inviteData.familyId = codeData.familyId;
    }

    const inviteRef = await db.collection("invites").add(inviteData);

    await writeAuditLog({
      eventType: "share_code_used",
      actorId: userId,
      subjectType: "invite",
      subjectId: inviteRef.id,
      metadata: { codeId: codeDoc.id, type: codeData.type },
      clientMetadata,
    });

    return {
      inviteId: inviteRef.id,
      type: codeData.type,
      familyId: codeData.familyId,
    };
  }
);

