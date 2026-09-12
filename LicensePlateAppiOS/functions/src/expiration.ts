import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  sweepUnansweredJoinRequests,
  unansweredJoinRequestCutoffMillis,
} from "./pendingJoinRequestExpiry";
import { flipExpiredDocuments } from "./retentionCore";
import { DEVICE_TRANSFER_CODE_COLLECTION } from "./deviceTransferCore";

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
 *
 * FR-77 (closes audit L-7), 2026-08-30: all three status flips now go through
 * `flipExpiredDocuments`, so each is paged and bounded like every `retentionCore` sweep. They
 * used to be unbounded `.get()`s staged into a single `WriteBatch` — which is capped at 500
 * operations, so the 501st expired row would have thrown and wedged the whole pass. See that
 * function for the self-quenching argument.
 */
export const expireInvitesAndCodes = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    // Expire pending invites past expiresAt. Every invite type now carries a finite
    // expiry — friend invites included, see FRIEND_INVITE_EXPIRY_DAYS in retentionCore.ts
    // (FR-49b) — so this no longer filters by type.
    const invitesResult = await flipExpiredDocuments(db, {
      collection: "invites",
      match: { field: "status", value: "pending" },
      timestampField: "expiresAt",
      cutoff: now,
      update: { status: "expired" },
    });

    // Expire pending trip invites past expiresAt
    const tripInvitesResult = await flipExpiredDocuments(db, {
      collection: "trip_invites",
      match: { field: "status", value: "pending" },
      timestampField: "expiresAt",
      cutoff: now,
      update: {
        status: "expired",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });

    // Expire share codes (mark as revoked)
    const codesResult = await flipExpiredDocuments(db, {
      collection: "share_codes",
      match: { field: "isRevoked", value: false },
      timestampField: "expiresAt",
      cutoff: now,
      update: { isRevoked: true },
    });

    // FR-84 (F-41): device transfer codes flip the same way, on the same 15-minute clock.
    // Redemption does NOT depend on this pass — `evaluateDeviceTransferRedemption` reads
    // `expiresAtMillis` inline and refuses a lapsed code whether or not the sweep has run. It
    // exists so this collection has an owner of its terminal state like every other code
    // collection: without it, `device_transfer_codes` would be the one place where
    // `isRevoked == false` does not mean "live", which is exactly the shape a future query
    // gets wrong.
    const transferCodesResult = await flipExpiredDocuments(db, {
      collection: DEVICE_TRANSFER_CODE_COLLECTION,
      match: { field: "isRevoked", value: false },
      timestampField: "expiresAt",
      cutoff: now,
      update: { isRevoked: true },
    });

    // Unanswered join requests, on their own 7-day clock. Deliberately NOT followed by an
    // inline FR-60(c) cleanup of the children whose rows just retired: `inactivateFamily` set
    // the precedent for exactly this case and left those accounts to the daily FR-77 backstop,
    // which now picks them up on its next run because retiring the row is what lifts the
    // `hasLiveJoinRequest` veto. Keeping the deletion machinery out of a 5-minute job also
    // keeps this pass bounded.
    const joinRequestSweep = await sweepUnansweredJoinRequests(db, {
      cutoffMillis: unansweredJoinRequestCutoffMillis(now.toMillis()),
    });

    const truncated =
      invitesResult.truncated ||
      tripInvitesResult.truncated ||
      codesResult.truncated ||
      transferCodesResult.truncated ||
      joinRequestSweep.truncated;
    console.log(
      `Expired ${invitesResult.flipped} invites, ${tripInvitesResult.flipped} trip invites, ` +
        `${codesResult.flipped} codes, ${transferCodesResult.flipped} device transfer codes, ` +
        `and ${joinRequestSweep.retired} unanswered join requests` +
        `${truncated ? " (truncated; next run resumes)" : ""}`
    );

    return null;
  });

