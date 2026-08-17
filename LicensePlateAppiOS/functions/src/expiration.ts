import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { currentRevenueCatApiKey } from "./accountDeletion";
import { deleteProvisionalChildAccountIfNeverConsented } from "./provisionalChildAccounts";
import {
  sweepUnansweredJoinRequests,
  unansweredJoinRequestCutoffMillis,
} from "./pendingJoinRequestExpiry";

const db = admin.firestore();

/**
 * COPPA FR-60(c), expiry half: a family invite that times out unaccepted is the second way a
 * redemption window closes without consent. The child entered a code — which is what minted
 * their uid — and then nothing happened, so there is no captain decision coming and no basis
 * to keep the account.
 *
 * The helper is a no-op for every other recipient (adults, consented children, and sticky
 * post-revocation children), so this is safe to run over whatever expired in this pass. It is
 * also non-fatal per invite: a failure must not abort the status-flip job that every other
 * invite in the batch depends on, and the FR-77 backstop sweep re-attempts anything missed.
 */
async function cleanUpProvisionalChildrenForExpiredInvites(
  invites: admin.firestore.QueryDocumentSnapshot[]
): Promise<void> {
  const recipientIds = new Set<string>();
  for (const invite of invites) {
    const data = invite.data();
    if (data.type !== "family") continue;
    if (typeof data.toUserId === "string" && data.toUserId.length > 0) {
      recipientIds.add(data.toUserId);
    }
  }

  for (const userId of recipientIds) {
    try {
      await deleteProvisionalChildAccountIfNeverConsented(db, {
        userId,
        actorId: userId,
        clientMetadata: null,
        revenueCatApiKey: currentRevenueCatApiKey(),
      });
    } catch (error) {
      functions.logger.error(
        "FR-60(c): provisional child cleanup after invite expiry failed; backstop sweep will retry",
        { childUserId: userId, error }
      );
    }
  }
}

/**
 * Scheduled function to expire invites and share codes
 * Runs every 5 minutes
 *
 * This pass only flips status fields — the UI relies on seeing "expired" invites and
 * revoked share codes. Hard deletion happens later, in the daily retention jobs in
 * `retention.ts` (FR-49), once the grace period has elapsed.
 *
 * The one exception is FR-60(c)'s transient-account cleanup below: a never-consented child's
 * whole account is deleted when their family invite expires, because that account exists only
 * for the consent request that just lapsed.
 *
 * Device pass 2026-08-17: this job also owns the fourth clock — unanswered join requests. It
 * does NOT retire a pending row because that row's invite lapsed; see
 * `pendingJoinRequestExpiry.ts` for why the redemption window is the wrong clock for a decision
 * awaiting a human. What it guarantees is that every pending row has exactly ONE owner of its
 * terminal state, so none is left orphaned by the invite sweep above.
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

    // Unanswered join requests, on their own 7-day clock. Deliberately NOT followed by an
    // inline FR-60(c) cleanup of the children whose rows just retired: `inactivateFamily` set
    // the precedent for exactly this case and left those accounts to the daily FR-77 backstop,
    // which now picks them up on its next run because retiring the row is what lifts the
    // `hasLiveJoinRequest` veto. Keeping the deletion machinery out of a 5-minute job also
    // keeps this pass bounded.
    const joinRequestSweep = await sweepUnansweredJoinRequests(db, {
      cutoffMillis: unansweredJoinRequestCutoffMillis(now.toMillis()),
    });

    // FR-60(c): strictly after the status flip commits, so a cleanup failure cannot leave an
    // invite stuck "pending" forever.
    await cleanUpProvisionalChildrenForExpiredInvites(invitesSnapshot.docs);

    console.log(
      `Expired ${invitesSnapshot.size} invites, ${tripInvitesSnapshot.size} trip invites, ` +
        `${codesSnapshot.size} codes, and ${joinRequestSweep.retired} unanswered join requests` +
        `${joinRequestSweep.truncated ? " (truncated; next run resumes)" : ""}`
    );

    return null;
  });

