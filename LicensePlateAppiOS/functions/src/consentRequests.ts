/**
 * FR-59/FR-59.1 email_plus — the consent-request lifecycle's Firestore/HTTP half
 * (§3.1.2 steps 1–3; step 4's delayed "plus" notice rides the next slice).
 *
 * Flow: `approveFamilyJoinRequest_CaptainStep` (family.ts) validates everything it
 * always validated, then — for a CHILD grant only — calls `createConsentRequestForApproval`
 * instead of admitting. The onCreate trigger emails the guardian the NP-1 direct notice
 * with a single-use link. `confirmParentalConsent` (this codebase's first `onRequest`)
 * commits the FR-64 single transaction: consent record + guardianship + membership +
 * `activeFamilyId` together, or nothing.
 *
 * AUTHORITY: the server-only `consent_requests` document. Row status is display —
 * clients can write row status strings (rules `hasOnly(["status","resolvedAt"])`), so
 * nothing here ever trusts it.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { defineSecret, defineString } from "firebase-functions/params";
import { sendTransactionalEmail } from "./utils/email";
import { redactEmailAddresses } from "./welcomeEmailCore";
import { loadFamilyName } from "./familyInviteDisplay";
import {
  CONSENT_REQUESTS_COLLECTION,
  CONSENT_REQUEST_STATUS,
  CONSENT_REQUEST_TTL_MS,
  ConsentAssurancePolicy,
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
  buildConsentRequestEmailContent,
  decideConsentConfirmation,
  formatConsentToken,
  hashConsentNonce,
  isValidAgeOutYearMonth,
  mintConsentNonce,
  parseConsentToken,
} from "./consentRequestsCore";
import {
  AUDIT_PARENTAL_CONSENT_GRANTED,
  buildConsentGrantedMetadata,
  consentMetadataPiiViolations,
  sanitizedChildLinkedPlatforms,
} from "./childAccountCore";
import { familyMembershipGrantUserUpdate } from "./wasEverInFamilyUserUpdates";
import { CHILD_DECLARED_AT_FIELD, deleteProvisionalChildAccountIfNeverConsented } from "./provisionalChildAccounts";
import { PENDING_FAMILY_REQUEST_FIELD, findLivePendingJoinRequestsInOtherFamilies } from "./familyJoinRequestIntegrity";
import { stageJoinRequestRetirement } from "./pendingJoinRequestExpiry";
import { applyChildProtectionsAfterFlagSet } from "./familyChildStatusFlows";
import { getFCMTokenForSocialPush, sendPushNotification } from "./utils/notifications";
import { currentRevenueCatApiKey } from "./accountDeletion";

const resendApiKey = defineSecret("RESEND_API_KEY");
const welcomeEmailFrom = defineSecret("WELCOME_EMAIL_FROM");
const consentEmailEnvLabel = defineString("WELCOME_EMAIL_ENV_LABEL", { default: "" });

type Firestore = admin.firestore.Firestore;

// ---------------------------------------------------------------------------
// Step 1 — creation (called from the approve callable)
// ---------------------------------------------------------------------------

export interface CreateConsentRequestInput {
  familyId: string;
  childUserId: string;
  joinRequestId: string;
  guardianUid: string;
  guardianRole: string;
  guardianEmail: string;
  newRole: string;
  childUserName: string;
  expectedAgeOutYear?: number;
  nowMillis?: number;
}

export interface CreateConsentRequestResult {
  requestId: string;
  reusedExisting: boolean;
}

/**
 * Creates (or, idempotently, reuses) the live consent request for (family, child).
 *
 * Re-approve while a request is live returns the existing request untouched — old
 * clients fail open on the awaiting row status and captains WILL tap approve again;
 * every tap after the first must be a no-op, not a fresh email (spam is its own
 * consent-flow failure). Only an EXPIRED request mints a fresh nonce.
 */
export async function createConsentRequestForApproval(
  db: Firestore,
  input: CreateConsentRequestInput
): Promise<CreateConsentRequestResult> {
  const now = input.nowMillis ?? Date.now();

  const live = await db
    .collection(CONSENT_REQUESTS_COLLECTION)
    .where("familyId", "==", input.familyId)
    .where("childUserId", "==", input.childUserId)
    .where("status", "==", CONSENT_REQUEST_STATUS.pending)
    .limit(5)
    .get();

  for (const doc of live.docs) {
    const expiresAtMillis = doc.data().expiresAtMillis;
    if (typeof expiresAtMillis === "number" && expiresAtMillis > now) {
      return { requestId: doc.id, reusedExisting: true };
    }
    // Lapsed but not yet swept: retire it so exactly one live request exists.
    await doc.ref.update({ status: CONSENT_REQUEST_STATUS.superseded, resolvedAtMillis: now });
  }

  const nonce = mintConsentNonce();
  const noticeFamilyName = (await loadFamilyName(input.familyId)) ?? "your family";

  const requestRef = db.collection(CONSENT_REQUESTS_COLLECTION).doc();
  await requestRef.set({
    familyId: input.familyId,
    childUserId: input.childUserId,
    joinRequestId: input.joinRequestId,
    guardianUid: input.guardianUid,
    guardianRole: input.guardianRole,
    // §312.5(c)(1): the parent's own contact information, collected to obtain consent.
    // Server-only document (rules deny all client access); never copied into audit rows.
    guardianEmail: input.guardianEmail,
    newRole: input.newRole,
    childUserName: input.childUserName,
    // `noticeFamilyName`, not `familyName`: the auditRedaction lint bans that key
    // source-wide (audit-row protection); this copy exists solely for the NP-1 email.
    noticeFamilyName,
    expectedAgeOutYear: input.expectedAgeOutYear ?? null,
    nonceHash: hashConsentNonce(nonce),
    status: CONSENT_REQUEST_STATUS.pending,
    attempts: 0,
    requestedAtMillis: now,
    expiresAtMillis: now + CONSENT_REQUEST_TTL_MS,
    emailDelivery: { state: "queued" },
    method: "email_plus",
    assuranceLevel: ConsentAssurancePolicy.level("email_plus"),
    // The raw nonce is stored TRANSIENTLY for the email trigger only; the trigger
    // deletes it the moment the send is claimed. It never outlives delivery, so no
    // durable copy of the credential exists server-side.
    pendingLinkNonce: nonce,
  });

  return { requestId: requestRef.id, reusedExisting: false };
}

// ---------------------------------------------------------------------------
// Step 2 — the consent-request email (onCreate trigger, welcomeEmail's claim pattern)
// ---------------------------------------------------------------------------

/** Base URL for the confirmation endpoint; project-derived, no Hosting required. */
function confirmEndpointBaseUrl(): string {
  const projectId =
    process.env.GCLOUD_PROJECT ?? admin.app().options.projectId ?? "unknown-project";
  return `https://us-central1-${projectId}.cloudfunctions.net/confirmParentalConsent`;
}

export const onConsentRequestCreatedSendEmail = functions
  .runWith({ secrets: [resendApiKey, welcomeEmailFrom] })
  .firestore.document(`${CONSENT_REQUESTS_COLLECTION}/{requestId}`)
  .onCreate(async (snapshot) => {
    const db = admin.firestore();
    const data = snapshot.data();
    const requestId = snapshot.id;

    // Claim transactionally (trigger retries must not double-send), and strip the raw
    // nonce in the same commit — after this, the emailed link is the only copy.
    const claim = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(snapshot.ref);
      if (!fresh.exists) return null;
      const state = fresh.data()?.emailDelivery?.state;
      if (state !== "queued") return null;
      const nonce = fresh.data()?.pendingLinkNonce;
      if (typeof nonce !== "string" || nonce.length === 0) return null;
      tx.update(snapshot.ref, {
        "emailDelivery.state": "sending",
        pendingLinkNonce: admin.firestore.FieldValue.delete(),
      });
      return nonce;
    });
    if (claim === null) {
      functions.logger.info(`consent email already claimed for ${requestId}`);
      return;
    }

    const content = buildConsentRequestEmailContent({
      familyDisplayName:
        typeof data.noticeFamilyName === "string" ? data.noticeFamilyName : "your family",
      childUserName:
        typeof data.childUserName === "string" && data.childUserName.length > 0
          ? data.childUserName
          : "your family's player",
      confirmUrl: `${confirmEndpointBaseUrl()}?t=${encodeURIComponent(
        formatConsentToken(requestId, claim)
      )}`,
      envLabel: consentEmailEnvLabel.value(),
      ttlHours: Math.round(CONSENT_REQUEST_TTL_MS / 3_600_000),
    });

    try {
      const result = await sendTransactionalEmail({
        apiKey: resendApiKey.value(),
        from: welcomeEmailFrom.value(),
        to: data.guardianEmail,
        subject: content.subject,
        html: content.html,
        text: content.text,
      });
      await snapshot.ref.update({
        "emailDelivery.state": "sent",
        "emailDelivery.sentAtMillis": Date.now(),
        "emailDelivery.providerMessageId": result.providerMessageId ?? null,
      });
    } catch (error) {
      // FR-35(a): no plaintext addresses in Cloud Logging.
      functions.logger.error(
        `consent email send failed for ${requestId}: ${redactEmailAddresses(String(error))}`
      );
      await snapshot.ref.update({
        "emailDelivery.state": "failed",
        "emailDelivery.failedAtMillis": Date.now(),
      });
    }
  });

// ---------------------------------------------------------------------------
// Step 3 — confirmation endpoint + the FR-64 single transaction
// ---------------------------------------------------------------------------

function htmlPage(title: string, body: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:48px auto;padding:0 24px;color:#1c1c1e;"><h2 style="color:#1d4ed8;">${title}</h2><p>${body}</p></body></html>`;
}

const PAGES = {
  confirmed: htmlPage(
    "Consent confirmed",
    "Thank you. The player's account is now active in your family. You can manage or withdraw consent at any time from Family settings in the RoadTrip Royale app."
  ),
  alreadyConfirmed: htmlPage(
    "Already confirmed",
    "This consent was already confirmed — nothing more to do. You can manage it from Family settings in the app."
  ),
  expired: htmlPage(
    "Link expired",
    "This confirmation link has expired and the pending request has been closed. If you still want to add this player, approve their request again in the app and a fresh email will be sent."
  ),
  refused: htmlPage(
    "Link not valid",
    "This link is not valid. If you meant to confirm consent, use the most recent email, or approve the request again in the app to receive a fresh one."
  ),
  error: htmlPage(
    "Something went wrong",
    "We could not process this confirmation. Please try the link again in a moment."
  ),
} as const;

export interface ConfirmableRequest {
  familyId: string;
  childUserId: string;
  joinRequestId: string;
  guardianUid: string;
  guardianRole: string;
  newRole: string;
  expectedAgeOutYear: number | null;
  assuranceLevel: number;
}

/**
 * The FR-64 single transaction. Everything admission means happens here or not at all:
 * consent audit row + guardianship record + member doc + `activeFamilyId` + row
 * approved + request confirmed. AGEOUT FR-110(b): the consent record REQUIRES
 * `ageOutYearMonth` (stamped on `users/{uid}` at declaration); a child doc without one
 * refuses to confirm rather than minting an incomplete record.
 */
export async function commitGuardianConfirmation(
  db: Firestore,
  requestRef: admin.firestore.DocumentReference,
  request: ConfirmableRequest,
  nowMillis: number
): Promise<{ committed: boolean; reason?: string }> {
  const childRef = db.collection("users").doc(request.childUserId);
  const rowRef = db
    .collection(`families/${request.familyId}/pending`)
    .doc(request.joinRequestId);
  const memberRef = db
    .collection(`families/${request.familyId}/members`)
    .doc(request.childUserId);
  const guardianshipRef = childRef.collection("private").doc("guardianship");
  const auditRef = db.collection("audit_logs").doc();

  return db.runTransaction(async (tx) => {
    const [childDoc, rowDoc, freshRequest] = await Promise.all([
      tx.get(childRef),
      tx.get(rowRef),
      tx.get(requestRef),
    ]);

    if (freshRequest.data()?.status !== CONSENT_REQUEST_STATUS.pending) {
      return { committed: false, reason: "request_not_pending" };
    }
    if (!childDoc.exists) {
      return { committed: false, reason: "child_gone" };
    }
    const childData = childDoc.data()!;
    const existingFamily = childData.activeFamilyId;
    if (typeof existingFamily === "string" && existingFamily.length > 0) {
      return {
        committed: false,
        reason: existingFamily === request.familyId ? "already_member" : "other_family",
      };
    }
    const rowStatus = rowDoc.data()?.status;
    if (
      !rowDoc.exists ||
      (rowStatus !== JOIN_REQUEST_AWAITING_GUARDIAN_STATUS && rowStatus !== "pending")
    ) {
      return { committed: false, reason: "row_gone" };
    }
    // AGEOUT FR-110(b): required, not optional. Pre-F-14b installs have no marker;
    // pre-release, the fix is reinstalling (the gate re-runs and recaptures it).
    const ageOutYearMonth = childData.ageOutYearMonth;
    if (!isValidAgeOutYearMonth(ageOutYearMonth)) {
      return { committed: false, reason: "missing_age_out_marker" };
    }

    const memberData: Record<string, unknown> = {
      role: request.newRole,
      permissions: { canInvite: false, canEditSettings: false },
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isChild: true,
    };

    const grantUpdate = familyMembershipGrantUserUpdate({
      familyId: request.familyId,
      isRetiredGeneral: false,
      isChild: true,
    });
    const linkedPlatforms = sanitizedChildLinkedPlatforms(childData.linkedPlatforms);
    if (linkedPlatforms && linkedPlatforms.changed) {
      grantUpdate.linkedPlatforms = linkedPlatforms.sanitized;
    }
    grantUpdate[CHILD_DECLARED_AT_FIELD] = admin.firestore.FieldValue.delete();
    grantUpdate[PENDING_FAMILY_REQUEST_FIELD] = admin.firestore.FieldValue.delete();

    const consentMetadata = buildConsentGrantedMetadata({
      familyId: request.familyId,
      childUserId: request.childUserId,
      actorRole: request.guardianRole,
      method: "email_plus",
      expectedAgeOutYear: request.expectedAgeOutYear ?? undefined,
      assuranceLevel: request.assuranceLevel,
      ageOutYearMonth: ageOutYearMonth as number,
    });
    const piiViolations = consentMetadataPiiViolations(consentMetadata);
    if (piiViolations.length > 0) {
      // The interlock is a bug tripwire, not a flow state — fail the whole commit.
      throw new Error(`consent metadata must be uid-only: ${piiViolations.join("; ")}`);
    }

    tx.set(memberRef, memberData);
    tx.update(childRef, grantUpdate);
    tx.update(rowRef, {
      status: "approved",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(requestRef, {
      status: CONSENT_REQUEST_STATUS.confirmed,
      confirmedAtMillis: nowMillis,
      // The request served its §312.5(c)(1) purpose; the address does not persist
      // past the grant. The evidence that an email was sent (timestamps, provider
      // message id) remains.
      guardianEmail: admin.firestore.FieldValue.delete(),
    });
    // FR-62 groundwork: the durable guardianship record (uid-only), owner-invisible to
    // clients via the private/{docId} whitelist.
    tx.set(guardianshipRef, {
      guardianUid: request.guardianUid,
      familyId: request.familyId,
      method: "email_plus",
      assuranceLevel: request.assuranceLevel,
      grantedAtMillis: nowMillis,
    });
    tx.set(auditRef, {
      eventType: AUDIT_PARENTAL_CONSENT_GRANTED,
      actorId: request.guardianUid,
      subjectType: "user",
      subjectId: request.childUserId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      metadata: consentMetadata,
    });

    return { committed: true };
  });
}

/** Post-commit, non-fatal follow-ups — the admission is already true. */
export async function runPostConfirmationFollowUps(
  db: Firestore,
  request: ConfirmableRequest
): Promise<void> {
  try {
    const batch = db.batch();
    const skip = new Set<string>([db.collection("users").doc(request.childUserId).path]);

    const acceptedInvites = await db
      .collection("invites")
      .where("familyId", "==", request.familyId)
      .where("toUserId", "==", request.childUserId)
      .where("type", "==", "family")
      .where("status", "==", "accepted")
      .limit(5)
      .get();
    for (const inviteDoc of acceptedInvites.docs) {
      skip.add(inviteDoc.ref.path);
      batch.update(inviteDoc.ref, {
        status: "expired",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Cross-family retirement moved from approve-time to HERE (2026-08-27 design):
    // approve no longer admits, and an expired link must not have already destroyed
    // other captains' answerable rows. Confirmation is the admission moment, so the
    // one-family boundary applies now.
    const stranded = await findLivePendingJoinRequestsInOtherFamilies(db, {
      userId: request.childUserId,
      excludeFamilyId: request.familyId,
    });
    if (stranded.truncated) {
      functions.logger.warn(
        "cross-family retirement at confirmation hit its bound; the sweep retires the rest",
        { familyId: request.familyId, childUserId: request.childUserId }
      );
    }
    await stageJoinRequestRetirement(db, batch, stranded.rows, {
      skipDocumentPaths: skip,
    });
    await batch.commit();
  } catch (error) {
    functions.logger.error("post-confirmation retirement failed (non-fatal)", { error });
  }

  try {
    const membersSnapshot = await db
      .collection(`families/${request.familyId}/members`)
      .get();
    const childDoc = await db.collection("users").doc(request.childUserId).get();
    await applyChildProtectionsAfterFlagSet(db, {
      childUserId: request.childUserId,
      familyMemberIds: membersSnapshot.docs.map((doc) => doc.id),
      childUserData: childDoc.data() ?? {},
    });
  } catch (error) {
    functions.logger.error("post-confirmation child protections failed (non-fatal)", { error });
  }

  try {
    const fcmToken = await getFCMTokenForSocialPush(request.childUserId, "family");
    if (fcmToken) {
      await sendPushNotification(
        fcmToken,
        "Family Request Approved",
        "You've been approved to join the family",
        {
          type: "family_join_approved",
          familyId: request.familyId,
          deepLink: `roadtrip-royale://family/${request.familyId}`,
        }
      );
    }
  } catch (error) {
    functions.logger.error("post-confirmation push failed (non-fatal)", { error });
  }
}

/**
 * The confirmation endpoint. No App Check by nature (it serves a mail client's browser);
 * the hashed nonce is the entire credential — see `consentRequestsCore` for the
 * uniform-refusal and attempt-bound rationale.
 */
export const confirmParentalConsent = functions.https.onRequest(async (req, res) => {
  try {
    const parsed = parseConsentToken(req.query.t ?? req.query.token);
    if (!parsed) {
      res.status(400).send(PAGES.refused);
      return;
    }
    const db = admin.firestore();
    const requestRef = db.collection(CONSENT_REQUESTS_COLLECTION).doc(parsed.requestId);

    // Attempt accounting + decision in one transaction so brute force cannot race the
    // counter. The admission commit is a SECOND transaction; the request's `pending`
    // status is re-read there, so a double-confirm race resolves to one winner.
    const decision = await db.runTransaction(async (tx) => {
      const doc = await tx.get(requestRef);
      if (!doc.exists) return { kind: "refused" as const };
      const data = doc.data()!;
      const verdict = decideConsentConfirmation({
        status: data.status,
        expiresAtMillis: data.expiresAtMillis ?? 0,
        attempts: data.attempts ?? 0,
        nowMillis: Date.now(),
        presentedNonce: parsed.nonce,
        storedNonceHash: data.nonceHash ?? "",
      });
      if (verdict.kind === "refused") {
        tx.update(requestRef, { attempts: admin.firestore.FieldValue.increment(1) });
      }
      return verdict;
    });

    if (decision.kind === "already_confirmed") {
      res.status(200).send(PAGES.alreadyConfirmed);
      return;
    }
    if (decision.kind === "expired") {
      res.status(410).send(PAGES.expired);
      return;
    }
    if (decision.kind !== "confirm") {
      res.status(400).send(PAGES.refused);
      return;
    }

    const requestDoc = await requestRef.get();
    const data = requestDoc.data()!;
    const request: ConfirmableRequest = {
      familyId: data.familyId,
      childUserId: data.childUserId,
      joinRequestId: data.joinRequestId,
      guardianUid: data.guardianUid,
      guardianRole: data.guardianRole ?? "captain",
      newRole: data.newRole ?? "scout",
      expectedAgeOutYear:
        typeof data.expectedAgeOutYear === "number" ? data.expectedAgeOutYear : null,
      assuranceLevel:
        typeof data.assuranceLevel === "number"
          ? data.assuranceLevel
          : ConsentAssurancePolicy.level("email_plus"),
    };

    const outcome = await commitGuardianConfirmation(db, requestRef, request, Date.now());
    if (!outcome.committed) {
      if (outcome.reason === "already_member") {
        res.status(200).send(PAGES.alreadyConfirmed);
        return;
      }
      functions.logger.warn("consent confirmation could not commit", {
        requestId: parsed.requestId,
        reason: outcome.reason,
      });
      res.status(409).send(PAGES.error);
      return;
    }

    await runPostConfirmationFollowUps(db, request);
    res.status(200).send(PAGES.confirmed);
  } catch (error) {
    functions.logger.error("confirmParentalConsent failed", {
      error: redactEmailAddresses(String(error)),
    });
    res.status(500).send(PAGES.error);
  }
});

// ---------------------------------------------------------------------------
// Expiry — "consent not obtained within a reasonable time" (§312.5(c)(1))
// ---------------------------------------------------------------------------

/**
 * Sweeps lapsed consent requests: request → expired, row (+ FR-88 stamp + origin
 * invite) retired via the shared helper, then FR-60(c) provisional cleanup — same
 * inline-deletion semantics as a decline, because a guardian who let the link lapse
 * has refused by silence and the child's pending footprint has no basis to persist.
 * Called from `expiration.ts`'s existing pass.
 */
export async function sweepExpiredConsentRequests(
  db: Firestore,
  nowMillis: number
): Promise<{ expired: number }> {
  const lapsed = await db
    .collection(CONSENT_REQUESTS_COLLECTION)
    .where("status", "==", CONSENT_REQUEST_STATUS.pending)
    .get();

  let expired = 0;
  for (const doc of lapsed.docs) {
    const data = doc.data();
    if (typeof data.expiresAtMillis !== "number" || data.expiresAtMillis > nowMillis) {
      continue;
    }
    expired += 1;

    const batch = db.batch();
    batch.update(doc.ref, {
      status: CONSENT_REQUEST_STATUS.expired,
      resolvedAtMillis: nowMillis,
      guardianEmail: admin.firestore.FieldValue.delete(),
    });
    const rowRef = db
      .collection(`families/${data.familyId}/pending`)
      .doc(data.joinRequestId);
    const rowDoc = await rowRef.get();
    if (rowDoc.exists) {
      await stageJoinRequestRetirement(
        db,
        batch,
        [rowDoc as admin.firestore.QueryDocumentSnapshot],
        {}
      );
    }
    await batch.commit();

    try {
      await deleteProvisionalChildAccountIfNeverConsented(db, {
        userId: data.childUserId,
        actorId: "system_consent_expiry",
        clientMetadata: null,
        revenueCatApiKey: currentRevenueCatApiKey(),
      });
    } catch (error) {
      functions.logger.error(
        "FR-60(c): provisional cleanup after consent expiry failed; backstop sweep will retry",
        { childUserId: data.childUserId, error }
      );
    }
  }
  return { expired };
}
