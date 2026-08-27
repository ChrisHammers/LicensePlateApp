/**
 * Child-status flows — COPPA F-5a (FR-2/FR-4/FR-5, FR-27, FR-29, FR-30).
 *
 * Db-parameterized so `fakeFirestore.ts` tests can pin the batch shapes, follow-ons and
 * consent rows exactly. The callable wiring (App Check, auth guards, clientMetadata
 * normalization) lives in `familyChildStatus.ts`; `approveFamilyJoinRequest_CaptainStep`'s
 * FR-25 extension lives in `family.ts` and shares `applyChildProtectionsAfterFlagSet`.
 *
 * FR-4 write discipline: the flag set itself is ONE batched write
 * (`users/{uid}.isChildAccount` + `members/{uid}.isChild` + linkedPlatforms strip).
 * The follow-ons — search-index purge, out-of-family invite expiry, friend-edge removal,
 * GRANTED record — are deliberately NOT atomic with it; each is idempotent and the
 * F-5b `onUserProfileSearchIndexSync` exclusion is the purge backstop.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { ClientMetadata } from "./clientMetadata";
import { clearAllSearchIndexesForUser } from "./userSearchIndex";
import {
  expireOutOfFamilyPendingInvitesForChild,
  removeAllFriendEdgesForUser,
  searchIndexHintsForUser,
} from "./userResidueCleanup";
import {
  CHILD_CONSENT_EVENT_TYPES,
  CHILD_STATUS_MANAGER_ROLES,
  isChildAccountUserData,
  sanitizedChildLinkedPlatforms,
  validateSetChildStatusInput,
  type ChildStatusRejection,
} from "./childAccountCore";
import {
  writeChildConsentCorrected,
  writeChildConsentGranted,
  writeChildMembershipRevocation,
  writeChildRegistrationDeclared,
} from "./childConsent";
import { familyMembershipLeaveUserUpdate } from "./wasEverInFamilyUserUpdates";
import {
  executeAccountDeletionForUser,
  type AccountDeletionDeps,
} from "./accountDeletion";
import { CHILD_DECLARED_AT_FIELD } from "./provisionalChildAccounts";

type Firestore = admin.firestore.Firestore;

export interface ChildStatusFlowDeps {
  clearSearchIndexes: typeof clearAllSearchIndexesForUser;
}

const defaultDeps: ChildStatusFlowDeps = {
  clearSearchIndexes: clearAllSearchIndexesForUser,
};

function throwRejection(rejection: ChildStatusRejection): never {
  throw new functions.https.HttpsError(rejection.code, rejection.message);
}

async function loadManagerRole(
  db: Firestore,
  familyId: string,
  actorId: string
): Promise<string> {
  const actorMemberDoc = await db
    .collection(`families/${familyId}/members`)
    .doc(actorId)
    .get();
  if (!actorMemberDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Not a family member");
  }
  const role = actorMemberDoc.data()?.role;
  return typeof role === "string" ? role : "unknown";
}

/**
 * FR-4 follow-ons, shared by `setFamilyMemberChildStatus` and the approval path in
 * `family.ts`. Runs AFTER the flag-set batch has committed. Idempotent and retry-safe:
 * the purge deletes only entries it owns, the invite expiry skips already-expired rows,
 * and the edge removal finds nothing on a re-run.
 */
export async function applyChildProtectionsAfterFlagSet(
  db: Firestore,
  input: {
    childUserId: string;
    familyMemberIds: readonly string[];
    childUserData: Record<string, unknown>;
  },
  deps: ChildStatusFlowDeps = defaultDeps
): Promise<{ removedFriendEdgeCount: number; expiredInviteCount: number }> {
  const hints = await searchIndexHintsForUser(db, input.childUserId, input.childUserData);
  await deps.clearSearchIndexes(input.childUserId, hints);

  const expiredInviteCount = await expireOutOfFamilyPendingInvitesForChild(db, {
    childUserId: input.childUserId,
    familyMemberIds: input.familyMemberIds,
  });

  const removedFriendEdgeCount = await removeAllFriendEdgesForUser(db, input.childUserId);

  return { removedFriendEdgeCount, expiredInviteCount };
}

export interface SetChildStatusResult {
  success: true;
  isChildAccount: boolean;
  removedFriendEdgeCount?: number;
}

/**
 * FR-2 / FR-4 / FR-5: manager sets or corrects an existing member's child status.
 */
export async function setFamilyMemberChildStatusFlow(
  db: Firestore,
  input: {
    actorId: string;
    familyId: string;
    targetUserId: string;
    isChild: unknown;
    correctionReason?: unknown;
    consentAcknowledged?: unknown;
    guardianAffirmed?: unknown;
    expectedAgeOutYearMonth?: unknown;
    clientMetadata: ClientMetadata | null;
  },
  deps: ChildStatusFlowDeps = defaultDeps
): Promise<SetChildStatusResult> {
  const { actorId, familyId, targetUserId, clientMetadata } = input;

  const actorRole = await loadManagerRole(db, familyId, actorId);

  const targetMemberRef = db.collection(`families/${familyId}/members`).doc(targetUserId);
  const targetMemberDoc = await targetMemberRef.get();
  if (!targetMemberDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Member not found");
  }
  const targetRole = targetMemberDoc.data()?.role;

  const decision = validateSetChildStatusInput({
    actorRole,
    actorUserId: actorId,
    targetUserId,
    targetRole: typeof targetRole === "string" ? targetRole : undefined,
    isChild: input.isChild,
    correctionReason: input.correctionReason,
    consentAcknowledged: input.consentAcknowledged,
    guardianAffirmed: input.guardianAffirmed,
    expectedAgeOutYearMonth: input.expectedAgeOutYearMonth,
    nowYear: new Date().getUTCFullYear(),
  });
  if (decision.kind === "reject") {
    throwRejection(decision);
  }

  const targetUserRef = db.collection("users").doc(targetUserId);
  const targetUserDoc = await targetUserRef.get();
  if (!targetUserDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User not found");
  }
  const targetUserData = targetUserDoc.data() ?? {};

  if (decision.kind === "set") {
    // FR-4: one batched write — authoritative flag + member projection + FR-35(b) strip.
    const userUpdate: Record<string, unknown> = { isChildAccount: true };
    const linkedPlatforms = sanitizedChildLinkedPlatforms(targetUserData.linkedPlatforms);
    if (linkedPlatforms && linkedPlatforms.changed) {
      userUpdate.linkedPlatforms = linkedPlatforms.sanitized;
    }

    const batch = db.batch();
    batch.update(targetUserRef, userUpdate);
    batch.update(targetMemberRef, {
      isChild: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // Non-atomic follow-ons (idempotent; syncer exclusion is the backstop — FR-4).
    const membersSnapshot = await db.collection(`families/${familyId}/members`).get();
    const familyMemberIds = membersSnapshot.docs.map((doc) => doc.id);
    const cleanup = await applyChildProtectionsAfterFlagSet(
      db,
      { childUserId: targetUserId, familyMemberIds, childUserData: targetUserData },
      deps
    );

    await writeChildConsentGranted(db, {
      familyId,
      childUserId: targetUserId,
      actorId,
      actorRole,
      method: "manager_set",
      expectedAgeOutYearMonth: decision.expectedAgeOutYearMonth,
      removedFriendEdgeCount: cleanup.removedFriendEdgeCount,
      clientMetadata,
    });

    return {
      success: true,
      isChildAccount: true,
      removedFriendEdgeCount: cleanup.removedFriendEdgeCount,
    };
  }

  // Correction (FR-5): clear both fields; search indexes rebuild via the normal
  // profile-sync triggers reacting to the users/{uid} write.
  const batch = db.batch();
  batch.update(targetUserRef, { isChildAccount: false });
  batch.update(targetMemberRef, {
    isChild: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  await writeChildConsentCorrected(db, {
    familyId,
    childUserId: targetUserId,
    actorId,
    actorRole,
    method: "manager_correction",
    reason: decision.correctionReason,
    clientMetadata,
  });

  return { success: true, isChildAccount: false };
}

export interface DeclareChildRegistrationResult {
  success: true;
  isChildAccount: true;
  alreadyDeclared: boolean;
}

/**
 * FR-27 server half: self-declaration in the protective direction ONLY. Sets
 * `isChildAccount = true`; there is no payload that can clear it (clearing requires a
 * parent — FR-26). Uses set-merge so it is safe to call BEFORE any profile write exists,
 * which is exactly how the age gate sequences registration. Idempotent: a repeat call
 * returns without writing a duplicate DECLARED record.
 *
 * FR-60(c): the same write stamps `childDeclaredAt` — a SERVER timestamp that opens the
 * redemption window. Under the local-first model this call happens at share-code entry, so
 * the stamp is the moment consent-seeking began, and it is what the FR-77 backstop sweep
 * ages out. It is deliberately not `createdAt`: that field is client-supplied from the
 * local `AppUser`, which can predate the code entry by months.
 */
export async function declareChildRegistrationFlow(
  db: Firestore,
  input: {
    userId: string;
    clientMetadata: ClientMetadata | null;
    /**
     * AGEOUT FR-110(c): the F-14b device marker, transmitted at declaration so a
     * later-approved child carries it without re-asking. Server-validated shape;
     * stamped onto `users/{uid}` (server-controlled key, rules guard) and onto the
     * DECLARED audit row. Optional at this seam — a pre-F-14b install has none and
     * FR-24 forbids stranding them here — but the FR-59 consent record REQUIRES it,
     * so a marker-less declaration surfaces at the confirmation step (pre-release:
     * dev testers reinstall, which re-runs the gate and recaptures it).
     */
    ageOutYearMonth?: number;
  }
): Promise<DeclareChildRegistrationResult> {
  const userRef = db.collection("users").doc(input.userId);
  const userDoc = await userRef.get();

  if (isChildAccountUserData(userDoc.data())) {
    // Idempotent re-declare: adopt a marker the first declaration lacked, never
    // overwrite one it had (protective: first capture wins).
    if (
      typeof input.ageOutYearMonth === "number" &&
      typeof userDoc.data()?.ageOutYearMonth !== "number"
    ) {
      await userRef.set({ ageOutYearMonth: input.ageOutYearMonth }, { merge: true });
    }
    return { success: true, isChildAccount: true, alreadyDeclared: true };
  }

  const declaration: Record<string, unknown> = {
    isChildAccount: true,
    [CHILD_DECLARED_AT_FIELD]: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (typeof input.ageOutYearMonth === "number") {
    declaration.ageOutYearMonth = input.ageOutYearMonth;
  }
  await userRef.set(declaration, { merge: true });

  await writeChildRegistrationDeclared(db, {
    childUserId: input.userId,
    ageOutYearMonth: input.ageOutYearMonth,
    clientMetadata: input.clientMetadata,
  });

  return { success: true, isChildAccount: true, alreadyDeclared: false };
}

export interface RequestChildDataDeletionResult {
  success: true;
  removedFriendEdgeCount: number;
}

/**
 * FR-30: manager-gated remove-and-delete for a flagged child. Removes the membership
 * first (REVOKED `parent_requested_deletion`), then runs the shared account-deletion
 * machinery — which now includes de-identification of shared gameplay residue and
 * active-trip ending via `deidentifyUserResidue` — against the child uid with the
 * parent as audit actor. The caller (wiring layer) deletes the Firebase Auth user last.
 */
export async function requestChildDataDeletionFlow(
  db: Firestore,
  input: {
    actorId: string;
    familyId: string;
    childUserId: string;
    clientMetadata: ClientMetadata | null;
    /** FR-78(a): resolved RevenueCat secret key, or null/omitted when unconfigured. */
    revenueCatApiKey?: string | null;
  },
  deps?: AccountDeletionDeps
): Promise<RequestChildDataDeletionResult> {
  const { actorId, familyId, childUserId, clientMetadata } = input;

  const actorRole = await loadManagerRole(db, familyId, actorId);
  if (!CHILD_STATUS_MANAGER_ROLES.includes(actorRole)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only Captains can request child data deletion"
    );
  }
  if (actorId === childUserId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Use account deletion to delete your own account"
    );
  }

  const childMemberRef = db.collection(`families/${familyId}/members`).doc(childUserId);
  const childMemberDoc = await childMemberRef.get();
  if (!childMemberDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Member not found");
  }
  if (childMemberDoc.data()?.role === "creator") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "The family creator cannot be deleted this way"
    );
  }

  const childUserRef = db.collection("users").doc(childUserId);
  const childUserDoc = await childUserRef.get();
  if (!isChildAccountUserData(childUserDoc.data())) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This member is not marked as a child"
    );
  }

  // Membership exit first, with the FR-30 reason. The deletion machinery below then
  // sees no remaining membership and cannot double-write a generic exit record.
  const batch = db.batch();
  batch.delete(childMemberRef);
  batch.update(
    childUserRef,
    familyMembershipLeaveUserUpdate({
      isRetiredGeneral: childUserDoc.data()?.isRetiredGeneral === true,
    })
  );
  await batch.commit();

  await writeChildMembershipRevocation(db, {
    familyId,
    childUserId,
    actorId,
    actorRole,
    method: "request_child_data_deletion",
    reason: "parent_requested_deletion",
    clientMetadata,
  });

  const deletion = await executeAccountDeletionForUser(
    db,
    {
      userId: childUserId,
      actorId,
      clientMetadata,
      revenueCatApiKey: input.revenueCatApiKey ?? null,
    },
    deps
  );

  return { success: true, removedFriendEdgeCount: deletion.removedFriendEdgeCount };
}

export interface ParentalConsentStatusRecord {
  eventType: string;
  createdAtMillis: number | null;
  familyId?: string;
  actorRole?: string;
  method?: string;
  reason?: string;
  consentTextVersion?: string;
  affirmationVersion?: string;
  guardianAffirmed?: boolean;
  expectedAgeOutYearMonth?: number;
}

export interface ParentalConsentStatusResult {
  isChildAccount: true;
  records: ParentalConsentStatusRecord[];
}

function millisFromTimestampLike(value: unknown): number | null {
  if (
    value &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}

/**
 * FR-29 (SHOULD): manager-gated read of the child's consent history. `audit_logs`
 * stays fully client-inaccessible; this server-side read returns only the curated,
 * uid-free consent fields. Query is equality-only (subjectType + subjectId — served by
 * merged single-field indexes, no composite needed); event-type filtering and ordering
 * happen in memory because a single child has a handful of lifecycle rows.
 */
export async function getParentalConsentStatusFlow(
  db: Firestore,
  input: { actorId: string; familyId: string; childUserId: string }
): Promise<ParentalConsentStatusResult> {
  const { actorId, familyId, childUserId } = input;

  const actorRole = await loadManagerRole(db, familyId, actorId);
  if (!CHILD_STATUS_MANAGER_ROLES.includes(actorRole)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only Captains can view consent status"
    );
  }

  const childMemberDoc = await db
    .collection(`families/${familyId}/members`)
    .doc(childUserId)
    .get();
  if (!childMemberDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Member not found");
  }

  const childUserDoc = await db.collection("users").doc(childUserId).get();
  if (!isChildAccountUserData(childUserDoc.data())) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This member is not marked as a child"
    );
  }

  const auditSnap = await db
    .collection("audit_logs")
    .where("subjectType", "==", "user")
    .where("subjectId", "==", childUserId)
    .get();

  const records: ParentalConsentStatusRecord[] = auditSnap.docs
    .map((doc) => doc.data())
    .filter((data) => CHILD_CONSENT_EVENT_TYPES.includes(String(data.eventType)))
    .map((data) => {
      const metadata = (data.metadata ?? {}) as Record<string, unknown>;
      const record: ParentalConsentStatusRecord = {
        eventType: String(data.eventType),
        createdAtMillis: millisFromTimestampLike(data.createdAt),
      };
      if (typeof metadata.familyId === "string") record.familyId = metadata.familyId;
      if (typeof metadata.actorRole === "string") record.actorRole = metadata.actorRole;
      if (typeof metadata.method === "string") record.method = metadata.method;
      if (typeof metadata.reason === "string") record.reason = metadata.reason;
      if (typeof metadata.consentTextVersion === "string") {
        record.consentTextVersion = metadata.consentTextVersion;
      }
      if (typeof metadata.affirmationVersion === "string") {
        record.affirmationVersion = metadata.affirmationVersion;
      }
      if (typeof metadata.guardianAffirmed === "boolean") {
        record.guardianAffirmed = metadata.guardianAffirmed;
      }
      if (typeof metadata.expectedAgeOutYearMonth === "number") {
        record.expectedAgeOutYearMonth = metadata.expectedAgeOutYearMonth;
      }
      return record;
    })
    .sort((a, b) => (a.createdAtMillis ?? 0) - (b.createdAtMillis ?? 0));

  return { isChildAccount: true, records };
}
