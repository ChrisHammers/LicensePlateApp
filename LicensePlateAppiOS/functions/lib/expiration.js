"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expireInvitesAndCodes = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const db = admin.firestore();
/**
 * Scheduled function to expire invites and share codes
 * Runs every 5 minutes
 */
exports.expireInvitesAndCodes = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    // Expire invites
    const invitesSnapshot = await db
        .collection("invites")
        .where("status", "==", "pending")
        .where("expiresAt", "<", now)
        .get();
    const inviteBatch = db.batch();
    invitesSnapshot.forEach((doc) => {
        inviteBatch.update(doc.ref, {
            status: "expired",
        });
    });
    await inviteBatch.commit();
    // Expire share codes (mark as revoked)
    const codesSnapshot = await db
        .collection("share_codes")
        .where("isRevoked", "==", false)
        .where("expiresAt", "<", now)
        .get();
    const codeBatch = db.batch();
    codesSnapshot.forEach((doc) => {
        codeBatch.update(doc.ref, {
            isRevoked: true,
        });
    });
    await codeBatch.commit();
    console.log(`Expired ${invitesSnapshot.size} invites and ${codesSnapshot.size} codes`);
    return null;
});
//# sourceMappingURL=expiration.js.map