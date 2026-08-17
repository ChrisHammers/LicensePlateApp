import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  sweepUnansweredJoinRequests,
  unansweredJoinRequestCutoffMillis,
} from "./pendingJoinRequestExpiry";

const db = admin.firestore();

/**
 * REMOVED 2026-08-17 — `cleanUpProvisionalChildrenForExpiredInvites`.
 *
 * This pass used to delete a provisional child's whole ACCOUNT the moment their family invite
 * lapsed on its 15-minute TTL. In the field that fired 15 minutes after a captain handed out a
 * share code: the child redeemed it (which mints the invite) and had not yet tapped Accept, so
 * no pending row existed, `hasLiveJoinRequest` correctly found nothing to veto, and the sweep
 * deleted a live, reachable child mid-flow.
 *
 * It is the same category error `pendingJoinRequestExpiry.ts` was written to correct, applied
 * one layer down. The 15 minutes is a REDEMPTION window — it bounds how long a short,
 * human-typed secret stays usable. It is not, and never was, a statement about how long the
 * human being holding the phone has to finish. Deleting the account on it destroys the very
 * thing the longer clock exists to protect, and it does so silently, before anyone has decided
 * anything.
 *
 * The correct reaper is already in place and is the one wave 6 chose for exactly this case:
 * FR-77's daily backstop (`retention.ts` → `sweepProvisionalChildAccounts`, on
 * `PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS = 7`), vetoed by `hasLiveJoinRequest`. The comment
 * beside the join-request sweep below already stated that policy — this deletion was the last
 * caller contradicting it.
 *
 * Deleting rather than gating (pre-release rule, 2026-08-10): an inline account-deletion in a
 * 5-minute cron with no clock of its own has no correct configuration.
 */

/**
 * Scheduled function to expire invites and share codes
 * Runs every 5 minutes
 *
 * This pass only flips status fields — the UI relies on seeing "expired" invites and
 * revoked share codes. Hard deletion happens later, in the daily retention jobs in
 * `retention.ts` (FR-49), once the grace period has elapsed.
 *
 * There are NO exceptions to that any more. It had one — an inline FR-60(c) account deletion
 * on invite expiry — and deleting a live child 15 minutes after a captain shared a code is
 * what it actually did; see the note at the top of this file.
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

    console.log(
      `Expired ${invitesSnapshot.size} invites, ${tripInvitesSnapshot.size} trip invites, ` +
        `${codesSnapshot.size} codes, and ${joinRequestSweep.retired} unanswered join requests` +
        `${joinRequestSweep.truncated ? " (truncated; next run resumes)" : ""}`
    );

    return null;
  });

