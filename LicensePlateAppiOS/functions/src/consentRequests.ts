/**
 * FR-59/FR-59.1 email_plus — the consent-request lifecycle's Firestore/HTTP half
 * (§3.1.2 steps 1–4).
 *
 * Flow: `approveFamilyJoinRequest_CaptainStep` (family.ts) validates everything it
 * always validated, then — for a CHILD grant only — calls `createConsentRequestForApproval`
 * instead of admitting. The onCreate trigger emails the guardian the NP-1 direct notice
 * with a single-use link. `confirmParentalConsent` (this codebase's first `onRequest`)
 * commits the FR-64 single transaction: consent record + guardianship + membership +
 * `activeFamilyId` together, or nothing. ≥24h later, `deliverConsentPlusNotices` sends
 * the method's second notice (the "plus") with the revocation path.
 *
 * AUTHORITY: the server-only `consent_requests` document. Row status is display —
 * clients can write row status strings (rules `hasOnly(["status","resolvedAt"])`), so
 * nothing here ever trusts it.
 *
 * §312.5(c)(1) LIFECYCLE OF THE GUARDIAN'S ADDRESS (decided 2026-08-27): the email is
 * retained THROUGH confirmation and purged when the plus notice sends (or the request
 * expires / is superseded / notice delivery is abandoned). Rationale: the plus notice
 * is part of the email_plus method itself, so the address is still serving its
 * consent purpose until that notice goes out — and it must reach the SAME address
 * that confirmed; re-resolving at send time could deliver the revocation notice to a
 * different inbox than the one that clicked the link.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { defineSecret, defineString } from "firebase-functions/params";
import { sendTransactionalEmail } from "./utils/email";
import { redactEmailAddresses } from "./welcomeEmailCore";
import { loadFamilyName } from "./familyInviteDisplay";
import { AUDIT_LOG_COLLECTION } from "./retentionCore";
import {
  CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS,
  CONSENT_PLUS_NOTICE_OVERDUE_MS,
  CONSENT_REQUESTS_COLLECTION,
  CONSENT_REQUEST_STATUS,
  CONSENT_REQUEST_TTL_MS,
  ConsentAssurancePolicy,
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
  buildConsentPlusNoticeEmailContent,
  buildConsentRequestEmailContent,
  decideConsentConfirmation,
  formatConsentToken,
  hashConsentNonce,
  isPlusNoticeDue,
  isValidAgeOutYearMonth,
  mintConsentNonce,
  parseConsentToken,
  resolvePlusNoticeDelayMillis,
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
// Dev knob only (set in the dev project's .env file); unset/invalid keeps the 24h
// floor — see `resolvePlusNoticeDelayMillis`. Production must never set this.
const plusNoticeDelayMinutesOverride = defineString("CONSENT_PLUS_NOTICE_DELAY_MINUTES", {
  default: "",
});

type Firestore = admin.firestore.Firestore;

/**
 * The guardian's reachable address: Auth email, else `users/{uid}/private/contact`.
 * Used at approve time (family.ts, to stamp the request) and by the plus-notice job
 * as the FALLBACK for requests confirmed before the retained-email lifecycle landed
 * (their address was purged at confirm). One implementation on purpose — two
 * resolvers would drift the moment one learns a new contact source.
 */
export async function resolveGuardianEmailByUid(
  db: Firestore,
  guardianUid: string
): Promise<string | null> {
  try {
    const authUser = await admin.auth().getUser(guardianUid);
    if (authUser.email && authUser.email.length > 0) return authUser.email;
  } catch {
    // Fall through to the contact doc — an Auth lookup failure must not block consent.
  }
  const contact = await db
    .collection("users")
    .doc(guardianUid)
    .collection("private")
    .doc("contact")
    .get();
  const email = contact.data()?.email;
  return typeof email === "string" && email.length > 0 ? email : null;
}

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
  expectedAgeOutYearMonth?: number;
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
    // Lapsed but not yet swept: retire it so exactly one live request exists. The
    // superseded request will never send another notice, so its copy of the
    // guardian's address has no remaining §312.5(c)(1) purpose — purge it here.
    await doc.ref.update({
      status: CONSENT_REQUEST_STATUS.superseded,
      resolvedAtMillis: now,
      guardianEmail: admin.firestore.FieldValue.delete(),
    });
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
    expectedAgeOutYearMonth: input.expectedAgeOutYearMonth ?? null,
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
  expectedAgeOutYearMonth: number | null;
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
      expectedAgeOutYearMonth: request.expectedAgeOutYearMonth ?? undefined,
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
      // The guardian's email is deliberately RETAINED here: the method's ≥24h plus
      // notice must reach the same address that confirmed, so the §312.5(c)(1)
      // purpose is not served until that notice sends. `sendDueConsentPlusNotices`
      // purges it with the send (or on abandonment). See the file header.
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
      expectedAgeOutYearMonth:
        typeof data.expectedAgeOutYearMonth === "number" ? data.expectedAgeOutYearMonth : null,
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
// Step 4 — the "plus": delayed second notice with the revocation path
// ---------------------------------------------------------------------------

export type SendPlusNoticeEmail = (params: {
  to: string;
  subject: string;
  html: string;
  text: string;
}) => Promise<{ providerMessageId: string | null }>;

export interface PlusNoticePassResult {
  sent: number;
  failed: number;
  abandoned: number;
}

/**
 * One pass over confirmed requests: send every due plus notice, stamp the evidence
 * (`plusNoticeSentAtMillis` + provider message id), and purge the guardian's address
 * in the same update — the §312.5(c)(1) purpose ends with this send. Failures retry
 * on later passes (the address is kept for exactly that reason) up to
 * CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS, then the request is marked abandoned and
 * purged anyway, loudly — an unsent plus notice is a lawfulness gap, not a hiccup.
 *
 * Query shape follows the expiry sweep: one equality filter, due-ness decided in
 * code (`isPlusNoticeDue`) — no composite index, and the harness stays faithful.
 */
export async function sendDueConsentPlusNotices(
  db: Firestore,
  input: {
    nowMillis: number;
    delayMillis: number;
    envLabel: string;
    sendEmail: SendPlusNoticeEmail;
  }
): Promise<PlusNoticePassResult> {
  const confirmed = await db
    .collection(CONSENT_REQUESTS_COLLECTION)
    .where("status", "==", CONSENT_REQUEST_STATUS.confirmed)
    .get();

  const result: PlusNoticePassResult = { sent: 0, failed: 0, abandoned: 0 };
  for (const doc of confirmed.docs) {
    const data = doc.data();
    if (!isPlusNoticeDue(data, input.nowMillis, input.delayMillis)) continue;

    try {
      const storedEmail = data.guardianEmail;
      const to =
        typeof storedEmail === "string" && storedEmail.length > 0
          ? storedEmail
          : typeof data.guardianUid === "string"
            ? await resolveGuardianEmailByUid(db, data.guardianUid)
            : null;
      if (!to) throw new Error("no deliverable guardian address");

      const content = buildConsentPlusNoticeEmailContent({
        familyDisplayName:
          typeof data.noticeFamilyName === "string" ? data.noticeFamilyName : "your family",
        childUserName:
          typeof data.childUserName === "string" && data.childUserName.length > 0
            ? data.childUserName
            : "your family's player",
        envLabel: input.envLabel,
      });
      const delivery = await input.sendEmail({
        to,
        subject: content.subject,
        html: content.html,
        text: content.text,
      });
      await doc.ref.update({
        plusNoticeSentAtMillis: input.nowMillis,
        plusNoticeProviderMessageId: delivery.providerMessageId ?? null,
        guardianEmail: admin.firestore.FieldValue.delete(),
      });
      result.sent += 1;
    } catch (error) {
      const attempts =
        (typeof data.plusNoticeAttempts === "number" ? data.plusNoticeAttempts : 0) + 1;
      // FR-35(a): no plaintext addresses in Cloud Logging.
      functions.logger.error(
        `consent plus notice send failed for ${doc.id} (attempt ${attempts}/${CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS}): ${redactEmailAddresses(String(error))}`
      );
      if (attempts >= CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS) {
        await doc.ref.update({
          plusNoticeAttempts: attempts,
          plusNoticeAbandonedAtMillis: input.nowMillis,
          guardianEmail: admin.firestore.FieldValue.delete(),
        });
        functions.logger.error(
          "consent plus notice ABANDONED — the email_plus record for this grant is missing its second notice; the FR-64 reconcile must surface it",
          { requestId: doc.id, childUserId: data.childUserId, familyId: data.familyId }
        );
        result.abandoned += 1;
      } else {
        await doc.ref.update({
          plusNoticeAttempts: attempts,
          plusNoticeLastFailedAtMillis: input.nowMillis,
        });
        result.failed += 1;
      }
    }
  }
  return result;
}

/**
 * Every 15 minutes rather than daily: the notice should land as soon after the ≥24h
 * floor as it can (24h–24h15m), and the cadence is what makes the dev knob usable
 * same-day (delay 1 minute ⇒ notice on the next tick). Each pass is one equality
 * query; the cost is noise.
 */
export const deliverConsentPlusNotices = functions
  .runWith({ secrets: [resendApiKey, welcomeEmailFrom], timeoutSeconds: 300 })
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    const result = await sendDueConsentPlusNotices(admin.firestore(), {
      nowMillis: Date.now(),
      delayMillis: resolvePlusNoticeDelayMillis(plusNoticeDelayMinutesOverride.value()),
      envLabel: consentEmailEnvLabel.value(),
      sendEmail: (params) =>
        sendTransactionalEmail({
          apiKey: resendApiKey.value(),
          from: welcomeEmailFrom.value(),
          ...params,
        }),
    });
    if (result.sent > 0 || result.failed > 0 || result.abandoned > 0) {
      functions.logger.info("consent plus notice pass", { result });
    }
    return null;
  });

// ---------------------------------------------------------------------------
// Step 8 — the nightly FR-64 reconcile (detection, not enforcement)
// ---------------------------------------------------------------------------

export interface ConsentReconcileResult {
  /** How many currently-consented children (isChildAccount + activeFamilyId) were checked. */
  consentedChildren: number;
  /** Child uids with NO AUDIT_PARENTAL_CONSENT_GRANTED row at all. */
  missingRecord: string[];
  /** Child uids whose best grant row is below the required assurance level. */
  belowRequiredLevel: string[];
  /** Consent-request ids whose plus notice was abandoned after the attempt cap. */
  plusNoticeAbandoned: string[];
  /** Consent-request ids confirmed long ago with no plus notice sent — the delivery job is broken. */
  plusNoticeOverdue: string[];
}

/**
 * FR-64's guarantee is transactional at grant time; this pass re-derives it nightly
 * from stored state, so a bug anywhere upstream becomes a loud finding instead of
 * silent unlawful collection. Three checks:
 *
 *  1. Every consented child has a GRANTED consent row (the rows are retained forever,
 *     so absence is a defect, never retention).
 *  2. The child's BEST grant row meets the required assurance level (FR-108(b), max
 *     across rows so a sticky FR-28 readmission keeps its original email_plus level).
 *     Grants from paths that never verified (`manager_set`, `family_admission` legacy
 *     shapes) carry no level and flag as 0 — that is the tripwire, not noise. Temporal
 *     revoke→readmit sequencing is FR-104's problem; this pass reads grant rows only.
 *  3. Every confirmed email_plus request got its plus notice: abandoned deliveries and
 *     overdue-unsent ones (CONSENT_PLUS_NOTICE_OVERDUE_MS) both flag.
 *
 * Detection only — nothing is halted or deleted here (FR-104 owns enforcement).
 * Findings are uid/request-id only, safe for Cloud Logging.
 */
export async function reconcileConsentRecords(
  db: Firestore,
  input: { nowMillis: number }
): Promise<ConsentReconcileResult> {
  const result: ConsentReconcileResult = {
    consentedChildren: 0,
    missingRecord: [],
    belowRequiredLevel: [],
    plusNoticeAbandoned: [],
    plusNoticeOverdue: [],
  };

  // One pass over the permanently-retained grant rows → best level per child.
  const grantedRows = await db
    .collection(AUDIT_LOG_COLLECTION)
    .where("eventType", "==", AUDIT_PARENTAL_CONSENT_GRANTED)
    .get();
  const bestLevelByChild = new Map<string, number>();
  for (const doc of grantedRows.docs) {
    const data = doc.data();
    if (typeof data.subjectId !== "string" || data.subjectId.length === 0) continue;
    const level = data.metadata?.assuranceLevel;
    const numeric = typeof level === "number" ? level : 0;
    const previous = bestLevelByChild.get(data.subjectId);
    if (previous === undefined || numeric > previous) {
      bestLevelByChild.set(data.subjectId, numeric);
    }
  }

  const children = await db
    .collection("users")
    .where("isChildAccount", "==", true)
    .get();
  for (const doc of children.docs) {
    const activeFamilyId = doc.data().activeFamilyId;
    if (typeof activeFamilyId !== "string" || activeFamilyId.length === 0) continue;
    result.consentedChildren += 1;
    const best = bestLevelByChild.get(doc.id);
    if (best === undefined) {
      result.missingRecord.push(doc.id);
    } else if (!ConsentAssurancePolicy.isRecordSufficient(best)) {
      result.belowRequiredLevel.push(doc.id);
    }
  }

  const confirmed = await db
    .collection(CONSENT_REQUESTS_COLLECTION)
    .where("status", "==", CONSENT_REQUEST_STATUS.confirmed)
    .get();
  for (const doc of confirmed.docs) {
    const data = doc.data();
    if (data.plusNoticeAbandonedAtMillis !== undefined) {
      result.plusNoticeAbandoned.push(doc.id);
      continue;
    }
    if (data.plusNoticeSentAtMillis !== undefined) continue;
    if (
      typeof data.confirmedAtMillis === "number" &&
      data.confirmedAtMillis + CONSENT_PLUS_NOTICE_OVERDUE_MS <= input.nowMillis
    ) {
      result.plusNoticeOverdue.push(doc.id);
    }
  }

  return result;
}

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
