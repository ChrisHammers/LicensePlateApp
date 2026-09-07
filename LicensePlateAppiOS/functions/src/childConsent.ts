/**
 * Child-consent record writers — COPPA F-5a (§11.1 / §11.2).
 *
 * Thin, db-parameterized wrappers over `writeAuditLogTo` that (a) build the uid-only
 * metadata via `childAccountCore` and (b) enforce the no-PII invariant at runtime:
 * a consent row is retained forever (retention carve-out, G-7) and survives account
 * deletion, so a name or email here would be permanent PII. Writing one is a bug worth
 * failing loudly on, not logging around.
 *
 * All writers take the Firestore handle explicitly so `fakeFirestore.ts` tests can pin
 * the exact rows every lifecycle path produces.
 */

import type * as admin from "firebase-admin";
import { writeAuditLogTo } from "./audit";
import type { ClientMetadata } from "./clientMetadata";
import {
  AUDIT_CHILD_REGISTRATION_DECLARED,
  AUDIT_PARENTAL_CONSENT_CORRECTED,
  AUDIT_PARENTAL_CONSENT_GRANTED,
  AUDIT_PARENTAL_CONSENT_REVOKED,
  buildChildRegistrationDeclaredMetadata,
  buildConsentCorrectedMetadata,
  buildConsentGrantedMetadata,
  buildConsentRevokedMetadata,
  consentMetadataPiiViolations,
  type ChildConsentRevocationReason,
  type ConsentCorrectedMetadataInput,
  type ConsentGrantedMetadataInput,
} from "./childAccountCore";

type Firestore = admin.firestore.Firestore;

function assertUidOnly(metadata: Record<string, unknown>): Record<string, unknown> {
  const violations = consentMetadataPiiViolations(metadata);
  if (violations.length > 0) {
    throw new Error(
      `consent metadata must be uid-only; refused to write: ${violations.join("; ")}`
    );
  }
  return metadata;
}

export async function writeChildConsentGranted(
  db: Firestore,
  input: ConsentGrantedMetadataInput & {
    actorId: string;
    clientMetadata: ClientMetadata | null;
  }
): Promise<void> {
  await writeAuditLogTo(db, {
    eventType: AUDIT_PARENTAL_CONSENT_GRANTED,
    actorId: input.actorId,
    subjectType: "user",
    subjectId: input.childUserId,
    metadata: assertUidOnly(buildConsentGrantedMetadata(input)),
    clientMetadata: input.clientMetadata,
  });
}

export async function writeChildConsentCorrected(
  db: Firestore,
  input: ConsentCorrectedMetadataInput & {
    actorId: string;
    clientMetadata: ClientMetadata | null;
  }
): Promise<void> {
  await writeAuditLogTo(db, {
    eventType: AUDIT_PARENTAL_CONSENT_CORRECTED,
    actorId: input.actorId,
    subjectType: "user",
    subjectId: input.childUserId,
    metadata: assertUidOnly(buildConsentCorrectedMetadata(input)),
    clientMetadata: input.clientMetadata,
  });
}

/**
 * FR-73 / v2.1 FR-53(b): the push token dies with the consent that covered it.
 *
 * An FCM token is a persistent identifier, so it is personal information. A revoked child
 * is an UNCONSENTED child again (the `isChildAccount` flag stays true; the family goes),
 * and no parental consent covers holding an identifier for them — so the routing doc is
 * deleted here, the server-side twin of the client's `clearFCMToken`. The client-side
 * eligibility guard (`PushTokenEligibilityPolicy`) stops the device re-registering, and
 * `firestore.rules` refuses an unconsented child's write if it tries; this is what removes
 * what already exists, on a device that may never come back online.
 *
 * Best-effort by design, for the same reason as the guardianship bookkeeping below: a
 * failure here must not block the REVOKED record, which is the §312.5 evidence.
 */
async function deleteChildPushRoutingDoc(
  db: Firestore,
  childUserId: string
): Promise<void> {
  try {
    await db
      .collection("users")
      .doc(childUserId)
      .collection("private")
      .doc("fcm")
      .delete();
  } catch (error) {
    console.error("FR-73: deleting revoked child's push token failed (non-fatal)", error);
  }
}

/**
 * FR-6: written on every membership-exit path for a flagged child. The caller detects
 * `member.isChild` BEFORE deleting the member doc and reports the path-specific reason
 * (§8.3). The child flag itself is never touched here — it is sticky by design.
 * `clientMetadata` is null on background paths (`onAuthUserDeleted`), which is permitted.
 */
export async function writeChildMembershipRevocation(
  db: Firestore,
  input: {
    familyId: string;
    childUserId: string;
    actorId: string;
    actorRole: string;
    method: string;
    reason: ChildConsentRevocationReason;
    clientMetadata: ClientMetadata | null;
  }
): Promise<void> {
  // FR-62: the guardianship record is ENDED here — never deleted — because this writer
  // is the one chokepoint every membership-end path already calls (FR-6). An ended
  // record still authorizes the recorded guardian's §312.6 review/deletion rights; a
  // later re-grant supersedes it wholesale (the grant transaction overwrites the doc).
  // First end wins: a second exit path racing this one must not restamp the timestamp.
  // Best-effort by design — a guardianship bookkeeping failure must not block the
  // revocation record itself.
  try {
    const guardianshipRef = db
      .collection("users")
      .doc(input.childUserId)
      .collection("private")
      .doc("guardianship");
    const guardianship = await guardianshipRef.get();
    const data = guardianship.data();
    if (
      guardianship.exists &&
      data?.familyId === input.familyId &&
      data?.endedAtMillis === undefined
    ) {
      await guardianshipRef.update({
        endedAtMillis: Date.now(),
        endedReason: input.reason,
      });
    }
  } catch (error) {
    console.error("FR-62: ending guardianship record failed (non-fatal)", error);
  }

  // FR-73 / FR-53(b): same chokepoint reasoning as the guardianship end above — every
  // membership-exit path already calls this writer, so the token cannot survive any of them.
  await deleteChildPushRoutingDoc(db, input.childUserId);

  await writeAuditLogTo(db, {
    eventType: AUDIT_PARENTAL_CONSENT_REVOKED,
    actorId: input.actorId,
    subjectType: "user",
    subjectId: input.childUserId,
    metadata: assertUidOnly(
      buildConsentRevokedMetadata({
        familyId: input.familyId,
        childUserId: input.childUserId,
        actorRole: input.actorRole,
        method: input.method,
        reason: input.reason,
      })
    ),
    clientMetadata: input.clientMetadata,
  });
}

export async function writeChildRegistrationDeclared(
  db: Firestore,
  input: {
    childUserId: string;
    ageOutYearMonth?: number;
    clientMetadata: ClientMetadata | null;
  }
): Promise<void> {
  await writeAuditLogTo(db, {
    eventType: AUDIT_CHILD_REGISTRATION_DECLARED,
    actorId: input.childUserId,
    subjectType: "user",
    subjectId: input.childUserId,
    metadata: assertUidOnly(
      buildChildRegistrationDeclaredMetadata({
        childUserId: input.childUserId,
        ageOutYearMonth: input.ageOutYearMonth,
      })
    ),
    clientMetadata: input.clientMetadata,
  });
}
