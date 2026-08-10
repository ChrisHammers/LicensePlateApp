import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Scheduled function to expire invites and share codes
 * Runs every 5 minutes
 *
 * This pass only flips status fields — the UI relies on seeing "expired" invites and
 * revoked share codes. Hard deletion happens later, in the daily retention jobs in
 * `retention.ts` (FR-49), once the grace period has elapsed.
 */
export const expireInvitesAndCodes = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    // Expire pending invites past expiresAt. Every invite type now carries a finite
    // expiry — friend invites included, see FRIEND_INVITE_EXPIRY_DAYS in retentionCore.ts
    // (FR-49b) — so this no longer filters by type.
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

    // Expire pending trip invites past expiresAt
    const tripInvitesSnapshot = await db
      .collection("trip_invites")
      .where("status", "==", "pending")
      .where("expiresAt", "<", now)
      .get();

    const tripInviteBatch = db.batch();
    tripInvitesSnapshot.forEach((doc) => {
      tripInviteBatch.update(doc.ref, {
        status: "expired",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    await tripInviteBatch.commit();

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

    console.log(
      `Expired ${invitesSnapshot.size} invites, ${tripInvitesSnapshot.size} trip invites, and ${codesSnapshot.size} codes`
    );

    return null;
  });

