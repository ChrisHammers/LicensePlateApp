/**
 * Child-status callables — COPPA F-5a (§8.1).
 *
 * All four are App Check-enforced (`enforcedCallable`) and carry `clientMetadata` as a
 * sibling field (client-metadata-cloud-calls rule). Auth gates:
 *  - `setFamilyMemberChildStatus`   — `assertRegisteredAccount` + creator/captain role (FR-2/3)
 *  - `declareChildRegistration`     — `assertAuthenticated` ONLY: the FR-27 guest
 *    auto-account path declares from an anonymous uid before any profile write exists,
 *    so requiring a registered account would defeat the age gate. Protective-direction
 *    only (can never clear the flag), so the weaker gate is safe.
 *  - `requestChildDataDeletion`     — `assertRegisteredAccount` + creator/captain role (FR-30)
 *  - `getParentalConsentStatus`     — `assertRegisteredAccount` + creator/captain role (FR-29)
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertAuthenticated, assertRegisteredAccount } from "./callableAuth";
import { isValidAgeOutYearMonth } from "./consentRequestsCore";
import { currentRevenueCatApiKey } from "./accountDeletion";
import {
  declareChildRegistrationFlow,
  getParentalConsentStatusFlow,
  requestChildDataDeletionFlow,
  setFamilyMemberChildStatusFlow,
} from "./familyChildStatusFlows";

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", `${name} is required`);
  }
  return value;
}

/**
 * FR-2/FR-4/FR-5: creator/captain sets child status for an existing member, or clears it
 * as a correction. Consent withdrawal is never expressed here — that is removal (FR-6)
 * or parent-initiated deletion (FR-30).
 */
export const setFamilyMemberChildStatus = enforcedCallable(async (data, context) => {
  const actorId = assertRegisteredAccount(context);
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  const familyId = requireString(data?.familyId, "familyId");
  const targetUserId = requireString(data?.memberId, "memberId");

  return setFamilyMemberChildStatusFlow(admin.firestore(), {
    actorId,
    familyId,
    targetUserId,
    isChild: data?.isChild,
    correctionReason: data?.correctionReason,
    consentAcknowledged: data?.consentAcknowledged,
    guardianAffirmed: data?.guardianAffirmed,
    expectedAgeOutYearMonth: data?.expectedAgeOutYearMonth,
    clientMetadata,
  });
});

/**
 * FR-26/FR-27 server half: the neutral age screen's under-13 answer. Sets
 * `users/{uid}.isChildAccount = true` (never false) before any profile or search-index
 * write exists, and records the uid-only DECLARED lifecycle row.
 */
export const declareChildRegistration = enforcedCallable(async (data, context) => {
  const userId = assertAuthenticated(context);
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  // AGEOUT FR-110(c): accept the F-14b marker when the client has one; silently drop a
  // malformed value rather than refusing — this callable is a child-reachable consent
  // exit and FR-24 forbids growing its refusal set. The consent RECORD is where the
  // field is required, and that check has a guardian in front of it, not a child.
  const ageOutYearMonth = isValidAgeOutYearMonth(data?.ageOutYearMonth)
    ? (data.ageOutYearMonth as number)
    : undefined;

  return declareChildRegistrationFlow(admin.firestore(), {
    userId,
    clientMetadata,
    ageOutYearMonth,
  });
});

/**
 * FR-30: manager-gated "remove and delete child's data". Reuses the deleteAccount
 * machinery (including de-identification of shared trip residue) against the child uid,
 * then deletes the child's Firebase Auth user last so a failed cleanup stays retryable.
 */
export const requestChildDataDeletion = enforcedCallable(
  async (data, context) => {
    const actorId = assertRegisteredAccount(context);
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    const familyId = requireString(data?.familyId, "familyId");
    const childUserId = requireString(data?.childUserId, "childUserId");

    const result = await requestChildDataDeletionFlow(admin.firestore(), {
      actorId,
      familyId,
      childUserId,
      clientMetadata,
      revenueCatApiKey: currentRevenueCatApiKey(),
    });

    try {
      await admin.auth().deleteUser(childUserId);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code !== "auth/user-not-found") {
        throw error;
      }
    }

    return result;
  }
);

/**
 * FR-29 (SHOULD): manager-gated consent history for a flagged child. `audit_logs`
 * remains fully client-inaccessible; this returns only curated, uid-free fields.
 */
export const getParentalConsentStatus = enforcedCallable(async (data, context) => {
  const actorId = assertRegisteredAccount(context);

  const familyId = requireString(data?.familyId, "familyId");
  const childUserId = requireString(data?.childUserId, "childUserId");

  return getParentalConsentStatusFlow(admin.firestore(), {
    actorId,
    familyId,
    childUserId,
  });
});
