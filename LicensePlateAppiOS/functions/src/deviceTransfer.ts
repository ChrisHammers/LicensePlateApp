/**
 * Parent-initiated device transfer for a consented child — COPPA v3 FR-84 (F-41).
 *
 * Two callables:
 *   `createDeviceTransferCode` — a family manager (or the recorded guardian, FR-62 ladder)
 *      mints a single-use, 15-minute code for ONE named consented child in their family.
 *   `redeemDeviceTransferCode` — the child's NEW device presents the code and receives a
 *      Firebase custom token for the child's EXISTING uid. The account, its XP, achievements
 *      and trip history come with it because the uid never changed.
 *
 * WHY A CUSTOM TOKEN, AND WHAT IT COSTS
 * -------------------------------------
 * A consented child's account is anonymous and credential-less by construction (FR-60(c)).
 * `admin.auth().createCustomToken(uid)` is the only mechanism Firebase Auth offers for
 * assuming an existing uid on a device that never held it — there is no credential to link.
 * The cost is that the resulting session reports `firebase.sign_in_provider == "custom"`,
 * NOT `"anonymous"`, and both `firestore.rules`' `isRegisteredAccount()` and
 * `callableAuth.ts`'s registration check were written as "provider != anonymous". Left alone,
 * a transfer would have silently PROMOTED every transferred child to a registered account —
 * handing them the capability set FR-85(a) went out of its way NOT to grant a consented
 * child, and doing it invisibly. Both predicates therefore now treat `custom` as
 * uncredentialed alongside `anonymous`. That is a hardening, not a widening: nothing in the
 * product minted a custom token before this file existed, so no existing session changes
 * class. See `callableAuth.ts` `isUncredentialedCaller` and the rules helper.
 *
 * WHAT A TRANSFER IS NOT
 * ----------------------
 * FR-84 future-item (iv): a transferred account keeps its guardianship record (FR-62) and its
 * post-revocation retention window (FR-77). Transfer is NOT a consent event. Nothing here
 * writes a consent row, touches `users/{childUid}/private/guardianship`, or restamps
 * `childDeclaredAt` / `ageOutYearMonth`. `deviceTransfer.test.ts` pins that as an invariant
 * rather than an omission.
 *
 * THE OLD DEVICE
 * --------------
 * FR-84's acceptance line requires that "the old device cannot continue acting as that
 * account". `revokeRefreshTokens` is the authoritative lever: the old device's next token
 * refresh fails against the Auth server and the SDK force-signs-out, which is the same
 * terminal verdict §3.1.1 item 7's `IdentityRefreshVerdict` work already teaches the client
 * to honour. Its residual — a cached ID token stays cryptographically valid for up to an hour,
 * and Firestore rules do not consult revocation — is real and documented in the FR-84 STATUS
 * block; `deviceTransferEpochMillis` is stamped on the user doc so a rules-level or
 * client-level epoch check can be added later without a data migration.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { writeAuditLogTo } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import {
  assertRegisteredAccount,
  assertRegisteredAccountOrDeclaredChild,
} from "./callableAuth";
import { assertCallerIsNotChild } from "./childAccessGuards";
import { consentMetadataPiiViolations } from "./childAccountCore";
import { authorizeParentalRights } from "./familyChildStatusFlows";
import { consumeInviteRateLimit } from "./inviteRateLimit";
import {
  AUDIT_CHILD_DEVICE_TRANSFER_ISSUED,
  AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED,
  DEVICE_TRANSFER_CODE_ALPHABET,
  DEVICE_TRANSFER_CODE_COLLECTION,
  DEVICE_TRANSFER_CODE_LENGTH,
  DEVICE_TRANSFER_CODE_TTL_MS,
  DEVICE_TRANSFER_SIGNING_FAILED_MESSAGE,
  DEVICE_TRANSFER_UNAVAILABLE_MESSAGE,
  buildDeviceTransferIssuedMetadata,
  buildDeviceTransferRedeemedMetadata,
  evaluateDeviceTransferRedemption,
  isTransferEligibleChildUserData,
  mayDiscardRedeemingProvisionalAccount,
  normalizeDeviceTransferCode,
} from "./deviceTransferCore";

const db = admin.firestore();

/**
 * Same uid-only invariant `childConsent.ts` enforces, for the same reason: these rows name a
 * child, are read by humans reconstructing what happened to an account, and outlive the
 * account itself. A name or email here would be permanent PII. Failing loudly beats logging.
 */
function assertUidOnly(metadata: Record<string, unknown>): Record<string, unknown> {
  const violations = consentMetadataPiiViolations(metadata);
  if (violations.length > 0) {
    throw new Error(
      `device-transfer metadata must be uid-only; refused to write: ${violations.join("; ")}`
    );
  }
  return metadata;
}

function generateTransferCode(): string {
  let code = "";
  for (let i = 0; i < DEVICE_TRANSFER_CODE_LENGTH; i += 1) {
    code += DEVICE_TRANSFER_CODE_ALPHABET.charAt(
      Math.floor(Math.random() * DEVICE_TRANSFER_CODE_ALPHABET.length)
    );
  }
  return code;
}

function transferUnavailable(): functions.https.HttpsError {
  return new functions.https.HttpsError(
    "not-found",
    DEVICE_TRANSFER_UNAVAILABLE_MESSAGE
  );
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new functions.https.HttpsError("invalid-argument", `${field} is required`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// Mint
// ---------------------------------------------------------------------------

/**
 * Issue a transfer code for one consented child.
 *
 * Authorization is layered, in this order, and the order is load-bearing:
 *   1. `assertRegisteredAccount` — a credential-less session may not mint an account
 *      credential for somebody else. With `custom` now counted as uncredentialed, a
 *      transferred child cannot chain one transfer into the next.
 *   2. `assertCallerIsNotChild` (FR-24) — belt for the CB-7 shape FR-66 closes, where the
 *      "captain" authorizing a child action is the child's own second account. Role alone
 *      is not proof of adulthood anywhere else in this codebase and is not here either.
 *   3. `authorizeParentalRights` (FR-62) — the durable-guardianship ladder: live
 *      creator/captain first, else the recorded guardian. Reused verbatim so device transfer
 *      cannot drift away from the one place parental authority is decided.
 *   4. the TARGET must be currently consented IN THAT FAMILY (FR-84's own words) — flag,
 *      `activeFamilyId`, and a server-written member doc.
 */
export const createDeviceTransferCode = enforcedCallable(async (data, context) => {
  const actorId = assertRegisteredAccount(context);
  const childUserId = requireNonEmptyString(data?.childUserId, "childUserId");
  const familyId = requireNonEmptyString(data?.familyId, "familyId");
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (childUserId === actorId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Cannot issue a transfer code for yourself"
    );
  }

  await assertCallerIsNotChild(db, actorId);

  const { actorRole } = await authorizeParentalRights(db, {
    actorId,
    familyId,
    childUserId,
  });

  // FR-84: "for a child currently consented in that family". Both facts are checked because
  // `activeFamilyId` is client-writable on one's own user doc while the member doc is
  // server-written only (FR-8) — the member doc is the authority, the field is the index.
  const childUserDoc = await db.collection("users").doc(childUserId).get();
  const childMemberDoc = await db
    .collection(`families/${familyId}/members`)
    .doc(childUserId)
    .get();
  if (
    !isTransferEligibleChildUserData(childUserDoc.data(), familyId) ||
    !childMemberDoc.exists
  ) {
    // The actor is already authorized over this child by step 3, so an actionable message
    // discloses nothing they cannot see on their own roster — the same reasoning that lets
    // `authorizeParentalRights` give a live non-manager member the actionable answer.
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Device transfer is only available for a child currently in this family"
    );
  }

  // At most ONE live transfer code per child at any time. Two taps on the button must not
  // leave two bearer credentials alive; superseding is also how a guardian who lost the
  // first code recovers, without a separate revoke surface to build and audit.
  // Single equality filter on purpose. Two would work, but only via Firestore's zigzag merge
  // join, and a later `orderBy`/range added here would silently start needing a composite
  // index that nothing in this repo declares. The per-child result set is a handful of rows,
  // so the `isRevoked` filter is cheaper to apply in memory than to depend on.
  const existingCodes = await db
    .collection(DEVICE_TRANSFER_CODE_COLLECTION)
    .where("childUserId", "==", childUserId)
    .get();
  let supersededCodeCount = 0;
  for (const doc of existingCodes.docs) {
    const data = doc.data() ?? {};
    if (data.isRevoked === true) continue;
    if (data.redeemedAtMillis !== undefined && data.redeemedAtMillis !== null) continue;
    await doc.ref.update({ isRevoked: true, supersededAtMillis: Date.now() });
    supersededCodeCount += 1;
  }

  const nowMs = Date.now();
  const expiresAtMillis = nowMs + DEVICE_TRANSFER_CODE_TTL_MS;
  const code = generateTransferCode();
  const codeRef = await db.collection(DEVICE_TRANSFER_CODE_COLLECTION).add({
    code,
    childUserId,
    familyId,
    createdBy: actorId,
    createdAtMillis: nowMs,
    // Millis is what every read here decides on — `evaluateDeviceTransferRedemption` is pure
    // and takes a number. The Timestamp twin exists solely so `expireInvitesAndCodes` can flip
    // this collection with the same bounded `flipExpiredDocuments` pass as `share_codes`; it is
    // never the authority for a redemption.
    expiresAtMillis,
    expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMillis),
    isRevoked: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    await writeAuditLogTo(db, {
      eventType: AUDIT_CHILD_DEVICE_TRANSFER_ISSUED,
      actorId,
      subjectType: "user",
      subjectId: childUserId,
      metadata: assertUidOnly(
        buildDeviceTransferIssuedMetadata({
          childUserId,
          familyId,
          actorRole,
          codeId: codeRef.id,
          supersededCodeCount,
        })
      ),
      clientMetadata,
    });
  } catch (error) {
    // Mirrors `createShareCode`: the code is already live and the guardian is looking at it;
    // a logging failure must not present as "that didn't work" and provoke a second mint.
    functions.logger.error("device_transfer_issued audit log failed", error);
  }

  return {
    codeId: codeRef.id,
    code,
    childUserId,
    expiresAtMillis: nowMs + DEVICE_TRANSFER_CODE_TTL_MS,
  };
});

// ---------------------------------------------------------------------------
// Redeem
// ---------------------------------------------------------------------------

/**
 * Redeem a transfer code on the child's new device and return a custom token for the child.
 *
 * ORDER IS LOAD-BEARING, same discipline as `redeemShareCode`:
 *   1. resolve the code first, spending no budget;
 *   2. consume the `share_redeem` budget INCLUDING on the not-found path — "not found" is the
 *      reply a brute-force search lives on and is the one that must be throttled (FR-67/FR-84
 *      both name this scope);
 *   3. re-check the TARGET's eligibility at redemption time, so a revocation between mint and
 *      redemption voids a live code;
 *   4. claim the code transactionally — single-use has to survive two devices racing;
 *   5. only then mint the credential.
 *
 * Every refusal in steps 1/3/4 is the identical `DEVICE_TRANSFER_UNAVAILABLE_MESSAGE`.
 *
 * OPEN TO DECLARED CHILDREN, like the other two exits. Under FR-60 the new device is a
 * local-first child with no backend identity, so it arrives here holding a freshly minted,
 * declared, anonymous uid — exactly the population `assertRegisteredAccountOrDeclaredChild`
 * exists for. That provisional uid is discarded below once the real account is handed over.
 */
export const redeemDeviceTransferCode = enforcedCallable(async (data, context) => {
  const redeemerUserId = await assertRegisteredAccountOrDeclaredChild(db, context);
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  const normalizedCode = normalizeDeviceTransferCode(data?.code);
  if (normalizedCode === null) {
    throw new functions.https.HttpsError("invalid-argument", "Code is required");
  }

  const snapshot = await db
    .collection(DEVICE_TRANSFER_CODE_COLLECTION)
    .where("code", "==", normalizedCode)
    .limit(1)
    .get();
  const foundDoc = snapshot.empty ? null : snapshot.docs[0];

  await consumeInviteRateLimit(db, { scope: "share_redeem", userId: redeemerUserId });

  const decision = evaluateDeviceTransferRedemption(
    foundDoc?.data() as Record<string, unknown> | undefined,
    Date.now()
  );
  if (!decision.claimable) {
    functions.logger.info("device transfer refused", { refusal: decision.refusal });
    throw transferUnavailable();
  }

  const { childUserId, familyId } = decision;

  // A session that already IS the target has nothing to move. Proceeding would spend the code
  // and revoke the CALLER's own refresh tokens (owner device test 2026-09-10: a second code
  // entered on the device that had just adopted the child). Same indistinguishable refusal as
  // every other negative outcome (FR-24), taken before any state changes.
  if (redeemerUserId === childUserId) {
    functions.logger.info("device transfer refused", { refusal: "redeemer_is_target" });
    throw transferUnavailable();
  }

  // Step 3 — eligibility re-check. A child revoked, removed, or deleted since the code was
  // minted must not be re-homed onto a new device on the strength of a stale credential.
  const childUserRef = db.collection("users").doc(childUserId);
  const childUserSnap = await childUserRef.get();
  const childMemberSnap = await db
    .collection(`families/${familyId}/members`)
    .doc(childUserId)
    .get();
  if (
    !isTransferEligibleChildUserData(childUserSnap.data(), familyId) ||
    !childMemberSnap.exists
  ) {
    functions.logger.info("device transfer refused", { refusal: "target_ineligible" });
    throw transferUnavailable();
  }

  // Step 4 — single-use claim. The re-read inside the transaction is the whole point: two
  // devices entering the same code concurrently both passed step 1, and exactly one may win.
  // PROBE the signer before anything is spent or revoked. Signing needs the runtime service
  // account to hold `roles/iam.serviceAccountTokenCreator`; when it does not (owner device test
  // 2026-09-10) the mint used to crash AFTER the claim — the code was burnt, the child's old
  // device was logged out, and nothing was delivered. The probe token is discarded: the token
  // the device receives is minted BELOW, after `revokeRefreshTokens`, so the session it opens
  // post-dates the revocation by construction (§3.1.1 item 13 hardening, 2026-09-11).
  try {
    await admin.auth().createCustomToken(childUserId);
  } catch (error) {
    functions.logger.error("device transfer: custom token signing failed", error);
    throw new functions.https.HttpsError("internal", DEVICE_TRANSFER_SIGNING_FAILED_MESSAGE);
  }

  const codeRef = foundDoc!.ref;
  const nowMs = Date.now();
  const claimed = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(codeRef);
    const current = evaluateDeviceTransferRedemption(
      fresh.data() as Record<string, unknown> | undefined,
      nowMs
    );
    if (!current.claimable) return false;
    tx.update(codeRef, {
      isRevoked: true,
      redeemedAtMillis: nowMs,
      redeemedByUserId: redeemerUserId,
    });
    return true;
  });
  if (!claimed) {
    functions.logger.info("device transfer refused", { refusal: "lost_claim_race" });
    throw transferUnavailable();
  }

  // The old device. Authoritative for token REFRESH; see the header note on the residual.
  await admin.auth().revokeRefreshTokens(childUserId);

  // Server-written epoch, so the swap is visible in the data and a later rules- or
  // client-level staleness check has something to compare against without a migration.
  await childUserRef.update({
    deviceTransferEpochMillis: nowMs,
    lastDeviceTransferAtMillis: nowMs,
  });

  // The real credential — minted only now, after the revocation above.
  const customToken = await admin.auth().createCustomToken(childUserId);

  // The provisional uid the new device minted purely to make this call. Best-effort by the
  // same reasoning as `childConsent.ts`'s guardianship/push cleanups: the transfer has
  // already happened and a residue-cleanup failure must not fail it. FR-77's 7-day
  // redemption-window sweep is the backstop.
  let discardedProvisionalAccount = false;
  const redeemerSnap =
    redeemerUserId === childUserId ? childUserSnap : await db.collection("users").doc(redeemerUserId).get();
  if (
    mayDiscardRedeemingProvisionalAccount({
      redeemerUserId,
      targetChildUserId: childUserId,
      redeemerUserData: redeemerSnap.data() as Record<string, unknown> | undefined,
    })
  ) {
    try {
      await db.collection("users").doc(redeemerUserId).delete();
      await admin.auth().deleteUser(redeemerUserId);
      discardedProvisionalAccount = true;
    } catch (error) {
      console.error("FR-84: discarding the provisional redeeming account failed (non-fatal)", error);
    }
  }

  await writeAuditLogTo(db, {
    eventType: AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED,
    actorId: redeemerUserId,
    subjectType: "user",
    subjectId: childUserId,
    metadata: assertUidOnly(
      buildDeviceTransferRedeemedMetadata({
        childUserId,
        familyId,
        codeId: codeRef.id,
        redeemedByUserId: redeemerUserId,
        discardedProvisionalAccount,
      })
    ),
    clientMetadata,
  });

  return { customToken, childUserId, familyId };
});
