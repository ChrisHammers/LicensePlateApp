/**
 * Invite rate limiting, Firestore side — COPPA remediation FR-47 (F-10).
 *
 * One transactional read-modify-write against a single counter doc per (scope, sender).
 * The transaction matters: two invites sent concurrently by the same user would otherwise
 * both read the same count and both write `count + 1`, letting a determined sender exceed
 * the limit by fanning out parallel calls.
 *
 * Db-parameterized like `childAccessGuards.ts` / `tripChildParticipation.ts`, so the
 * callables can be exercised end to end against `testSupport/fakeFirestore.ts`.
 *
 * The counter doc carries no `clientMetadata`. That rule (CLAUDE.md) governs the cloud
 * WRITES a client's call produces — audit rows and gameplay payloads, which keep carrying it
 * as a sibling field, unchanged. This doc is server-internal bookkeeping keyed only by uid;
 * stamping device/app metadata on it would attach identifying data to a row that exists
 * purely to hold an integer, and would need its own retention story for no benefit.
 *
 * A rejection deliberately writes NOTHING — no counter bump, no audit row. Auditing every
 * refused attempt would hand an attacker an unbounded write amplifier (one cheap rejected
 * call producing one billed document write), which is the opposite of what a rate limit is
 * for. This mirrors the existing friend-cap rejection, which is also silent.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  INVITE_RATE_LIMIT_COLLECTION,
  INVITE_RATE_LIMIT_MAX_PER_WINDOW,
  INVITE_RATE_LIMITED_MESSAGE,
  INVITE_RATE_LIMITED_REASON,
  InviteRateLimitScope,
  evaluateInviteRateLimit,
  inviteRateLimitDocId,
  readInviteRateLimitWindow,
} from "./inviteRateLimitCore";

type Firestore = admin.firestore.Firestore;

/**
 * Consume one unit of the sender's budget for `scope`, or throw `resource-exhausted`.
 *
 * Call this only once an invite is known to be genuinely NEW. Every caller runs it after its
 * idempotency short-circuit (an existing pending invite / existing friendship returns or
 * throws first), so an offline client replaying a queued invite re-hits the same
 * short-circuit and never burns budget for the same invite twice — offline-first behavior
 * stays deterministic and idempotent (CLAUDE.md).
 */
export async function consumeInviteRateLimit(
  db: Firestore,
  input: {
    scope: InviteRateLimitScope;
    userId: string;
    /** Injectable for tests; defaults to wall clock. */
    nowMs?: number;
  }
): Promise<void> {
  const nowMs = input.nowMs ?? Date.now();
  const maxPerWindow = INVITE_RATE_LIMIT_MAX_PER_WINDOW[input.scope];
  const ref = db
    .collection(INVITE_RATE_LIMIT_COLLECTION)
    .doc(inviteRateLimitDocId(input.scope, input.userId));

  const decision = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const current = readInviteRateLimitWindow(
      snapshot.data() as Record<string, unknown> | undefined
    );
    const outcome = evaluateInviteRateLimit(current, nowMs, maxPerWindow);

    if (outcome.allowed) {
      tx.set(ref, {
        userId: input.userId,
        scope: input.scope,
        windowStartAtMs: outcome.next.windowStartAtMs,
        count: outcome.next.count,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return outcome;
  });

  if (!decision.allowed) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      INVITE_RATE_LIMITED_MESSAGE,
      { reason: INVITE_RATE_LIMITED_REASON, retryAfterMs: decision.retryAfterMs }
    );
  }
}
