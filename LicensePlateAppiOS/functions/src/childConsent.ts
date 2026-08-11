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
  input: { childUserId: string; clientMetadata: ClientMetadata | null }
): Promise<void> {
  await writeAuditLogTo(db, {
    eventType: AUDIT_CHILD_REGISTRATION_DECLARED,
    actorId: input.childUserId,
    subjectType: "user",
    subjectId: input.childUserId,
    metadata: assertUidOnly(
      buildChildRegistrationDeclaredMetadata({ childUserId: input.childUserId })
    ),
    clientMetadata: input.clientMetadata,
  });
}
