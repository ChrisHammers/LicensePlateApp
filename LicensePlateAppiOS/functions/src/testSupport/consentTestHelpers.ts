/**
 * FR-59.1 test support: drive a guardian's email confirmation the way the endpoint
 * would, against the FakeFirestore. Finds the live consent request for (family, child),
 * then runs the REAL `commitGuardianConfirmation` + `runPostConfirmationFollowUps` —
 * the same functions `confirmParentalConsent` wraps — so suites that used to assert
 * "approve admits" now assert "approve awaits; confirmation admits" against production
 * code, not a test re-implementation.
 */

import {
  commitGuardianConfirmation,
  runPostConfirmationFollowUps,
  type ConfirmableRequest,
} from "../consentRequests";
import {
  CONSENT_REQUESTS_COLLECTION,
  ConsentAssurancePolicy,
} from "../consentRequestsCore";
import type { FakeFirestore } from "./fakeFirestore";

export function findLiveConsentRequest(
  db: FakeFirestore,
  input: { familyId: string; childUserId: string }
): { requestId: string; data: Record<string, unknown> } | null {
  for (const [path, data] of db.store.entries()) {
    if (!path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)) continue;
    if (
      data.familyId === input.familyId &&
      data.childUserId === input.childUserId &&
      data.status === "pending"
    ) {
      return { requestId: path.slice(CONSENT_REQUESTS_COLLECTION.length + 1), data };
    }
  }
  return null;
}

export async function confirmGuardianConsent(
  db: FakeFirestore,
  input: { familyId: string; childUserId: string }
): Promise<{ committed: boolean; reason?: string }> {
  const found = findLiveConsentRequest(db, input);
  if (!found) {
    return { committed: false, reason: "no_live_request" };
  }
  const data = found.data;
  const request: ConfirmableRequest = {
    familyId: data.familyId as string,
    childUserId: data.childUserId as string,
    joinRequestId: data.joinRequestId as string,
    guardianUid: data.guardianUid as string,
    guardianRole: (data.guardianRole as string) ?? "captain",
    newRole: (data.newRole as string) ?? "scout",
    expectedAgeOutYear:
      typeof data.expectedAgeOutYear === "number" ? data.expectedAgeOutYear : null,
    assuranceLevel:
      typeof data.assuranceLevel === "number"
        ? data.assuranceLevel
        : ConsentAssurancePolicy.level("email_plus"),
  };
  const requestRef = db
    .collection(CONSENT_REQUESTS_COLLECTION)
    .doc(found.requestId) as never;
  const outcome = await commitGuardianConfirmation(
    db as never,
    requestRef,
    request,
    Date.now()
  );
  if (outcome.committed) {
    await runPostConfirmationFollowUps(db as never, request);
  }
  return outcome;
}
