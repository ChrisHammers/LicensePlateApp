import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { writeAuditLogTo } from "./audit";
import { auditValueHash } from "./auditRedaction";
import { deidentifyUserResidue } from "./accountDeletionDeidentify";
import {
  INVITE_RATE_LIMIT_COLLECTION,
  inviteRateLimitDocIdsForUser,
} from "./inviteRateLimitCore";
import { normalizeClientMetadata, type ClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertRegisteredAccount } from "./callableAuth";
import { familyMembershipLeaveUserUpdate } from "./wasEverInFamilyUserUpdates";
import { clearAllSearchIndexesForUser } from "./userSearchIndex";
import {
  removeAllFriendEdgesForUser,
  searchIndexHintsForUser,
} from "./userResidueCleanup";
import { writeChildMembershipRevocation } from "./childConsent";
import {
  RECENT_LOGIN_MAX_AGE_SECONDS,
  isRecentLogin,
  familyCleanupAction,
} from "./accountDeletionCore";
import {
  deleteRevenueCatCustomer,
  type RevenueCatDeletionOutcome,
} from "./utils/revenueCat";

type Firestore = admin.firestore.Firestore;

const DELETE_BATCH_LIMIT = 450; // stay under Firestore's 500-op batch cap

/**
 * FR-78(a): RevenueCat's server-only *secret* API key (RevenueCat dashboard -> API keys ->
 * "Secret"), distinct from the public SDK key already embedded in the client. The owner has
 * not provisioned this yet (SRS v3.1 changelog, "RevenueCat API-key provisioning"), so
 * `currentRevenueCatApiKey()` resolves to null today and the deletion cascade below treats
 * that as a logged no-op, never a failure.
 *
 * Read from `process.env` rather than a `defineSecret()` param ON PURPOSE. A declared secret
 * with no value in Secret Manager is a HARD DEPLOY FAILURE ("In non-interactive mode but have
 * no value for the secret: REVENUECAT_SECRET_API_KEY"), which would block every functions
 * deploy until a RevenueCat account exists — the opposite of the ship-working-but-inert
 * requirement. `process.env` reads correctly in both worlds: undefined today, and injected
 * automatically once the secret is provisioned and declared.
 *
 * TO ENABLE (both steps, same change):
 *   1. firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
 *   2. re-add `const revenueCatSecretApiKey = defineSecret("REVENUECAT_SECRET_API_KEY");`
 *      and pass `{ secrets: [revenueCatSecretApiKey] }` to BOTH `deleteAccount` (below) and
 *      `requestChildDataDeletion` (familyChildStatus.ts) — otherwise the value is not injected.
 */
export function currentRevenueCatApiKey(): string | null {
  const value = (process.env.REVENUECAT_SECRET_API_KEY ?? "").trim();
  return value.length > 0 ? value : null;
}

async function deleteSubcollectionDocs(
  db: Firestore,
  parentRef: admin.firestore.DocumentReference,
  subcollectionId: string
): Promise<number> {
  const docRefs = await parentRef.collection(subcollectionId).listDocuments();
  for (let start = 0; start < docRefs.length; start += DELETE_BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of docRefs.slice(start, start + DELETE_BATCH_LIMIT)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
  return docRefs.length;
}

/**
 * FR-78(a) cascade result: the two vendor outcomes plus "skipped_no_key" for the
 * secret-not-provisioned no-op (see `currentRevenueCatApiKey`).
 */
export type RevenueCatCascadeOutcome = RevenueCatDeletionOutcome | "skipped_no_key";

/**
 * Deletes the RevenueCat customer record for `userId`, or logs a no-op when no secret key
 * is configured. Never throws for "nothing to do" cases (missing key, 404/never-purchased);
 * a genuine vendor error (5xx, network failure, bad key) propagates so the caller treats the
 * whole deletion as retryable rather than silently losing the vendor-deletion obligation.
 */
async function deleteRevenueCatCustomerForUid(
  userId: string,
  apiKey: string | null,
  deleteFn: AccountDeletionDeps["deleteRevenueCatCustomer"]
): Promise<RevenueCatCascadeOutcome> {
  if (!apiKey) {
    console.log(
      `FR-78 RevenueCat deletion skipped for ${userId}: no secret API key configured`
    );
    return "skipped_no_key";
  }
  const result = await deleteFn({ apiKey, appUserId: userId });
  console.log(`FR-78 RevenueCat customer ${result.outcome} for ${userId}`);
  return result.outcome;
}

export interface AccountDeletionDeps {
  clearSearchIndexes: typeof clearAllSearchIndexesForUser;
  deleteRevenueCatCustomer: typeof deleteRevenueCatCustomer;
}

const defaultDeps: AccountDeletionDeps = {
  clearSearchIndexes: clearAllSearchIndexesForUser,
  deleteRevenueCatCustomer,
};

export interface AccountDeletionResult {
  removedFriendEdgeCount: number;
  familyAction: string;
  revenueCatDeletionOutcome: RevenueCatCascadeOutcome;
}

/**
 * Deletes `userId`'s personal cloud data (everything except the Firebase Auth user —
 * the caller deletes that last so a failed cleanup stays retryable).
 *
 * Extracted from the `deleteAccount` callable so `requestChildDataDeletion` (FR-30) can
 * run the identical machinery against a child uid with the parent as `actorId`. The
 * `AUDIT_ACCOUNT_DELETED` row therefore carries `actorId` (parent or self) while
 * `subjectId` is always the deleted uid.
 *
 * COPPA F-5a additions:
 *  - the `remove_member` branch writes its previously missing `AUDIT_FAMILY_MEMBER_REMOVED`
 *    row, and — when the member doc carries `isChild: true` — the FR-6/FR-40
 *    `AUDIT_PARENTAL_CONSENT_REVOKED` (`member_account_deleted`) record;
 *  - the `inactivate_family` branch writes REVOKED (`creator_account_deleted`) for every
 *    other flagged child whose membership the inactivation ends.
 *
 * FR-78 (§312.6 — operators are responsible for vendors' handling of children's data):
 * every local phase above completes before the RevenueCat vendor-deletion phase runs, so a
 * vendor failure throws *after* local data is already gone — the caller (below) then leaves
 * the Firebase Auth user in place, exactly as it already does for a local-phase failure, so
 * the whole request stays retryable. See the RevenueCat cascade near the bottom of this
 * function for the resumability argument in full, and for the FR-78(b) GA4 decision.
 */
export async function executeAccountDeletionForUser(
  db: Firestore,
  input: {
    userId: string;
    actorId: string;
    clientMetadata: ClientMetadata | null;
    /** FR-78(a): resolved RevenueCat secret key, or null/omitted when unconfigured — a
     *  logged no-op, never a cascade failure. See `currentRevenueCatApiKey`. */
    revenueCatApiKey?: string | null;
  },
  deps: AccountDeletionDeps = defaultDeps
): Promise<AccountDeletionResult> {
  const { userId, actorId, clientMetadata } = input;

  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  const userData = userDoc.data() ?? {};

  // ---- Friend edges (both directions) + friendCount on the surviving side
  const removedFriendEdgeCount = await removeAllFriendEdgesForUser(db, userId);

  // ---- Family membership (creator takes the active family down; others just leave)
  const activeFamilyId =
    typeof userData.activeFamilyId === "string" && userData.activeFamilyId.length > 0
      ? userData.activeFamilyId
      : null;
  let familyAction = "none";

  if (activeFamilyId) {
    const familyRef = db.collection("families").doc(activeFamilyId);
    const familyDoc = await familyRef.get();
    const memberRef = familyRef.collection("members").doc(userId);
    const memberDoc = await memberRef.get();

    const familyData = familyDoc.exists ? familyDoc.data()! : null;
    familyAction = familyCleanupAction({
      isMember: memberDoc.exists,
      isCreator: familyData?.creatorId === userId,
      familyStatus: typeof familyData?.status === "string" ? familyData.status : null,
    });

    if (familyAction === "inactivate_family" && familyDoc.exists) {
      // Mirrors inactivateFamily / onAuthUserDeleted: mark inactive, remove all
      // members, and clear activeFamilyId (sticky wasEverInFamily) for the others.
      const batch = db.batch();
      batch.update(familyRef, {
        status: "inactive",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // FR-6: capture flagged children BEFORE their member docs are deleted.
      const childExits: Array<{ childUserId: string; reason: string }> = [];

      const membersSnapshot = await familyRef.collection("members").get();
      for (const member of membersSnapshot.docs) {
        batch.delete(member.ref);

        if (member.data()?.isChild === true) {
          childExits.push({
            childUserId: member.id,
            reason:
              member.id === userId ? "member_account_deleted" : "creator_account_deleted",
          });
        }

        if (member.id === userId) continue; // own user doc is deleted below
        const memberUserDoc = await db.collection("users").doc(member.id).get();
        const memberUserData = memberUserDoc.data();
        if (memberUserData) {
          batch.update(
            db.collection("users").doc(member.id),
            familyMembershipLeaveUserUpdate({
              isRetiredGeneral: !!memberUserData.isRetiredGeneral,
            })
          );
        }
      }

      await batch.commit();

      for (const exit of childExits) {
        await writeChildMembershipRevocation(db, {
          familyId: activeFamilyId,
          childUserId: exit.childUserId,
          actorId,
          actorRole: "creator",
          method: "delete_account",
          reason: exit.reason,
          clientMetadata,
        });
      }

      await writeAuditLogTo(db, {
        eventType: "AUDIT_FAMILY_INACTIVATED",
        actorId,
        subjectType: "family",
        subjectId: activeFamilyId,
        metadata: {
          reason: "creator_account_deleted",
          familyNameHash: auditValueHash(familyData?.name),
        },
        clientMetadata,
      });
    } else if (familyAction === "remove_member") {
      const memberData = memberDoc.data() ?? {};
      const memberRole = typeof memberData.role === "string" ? memberData.role : "unknown";
      const memberWasChild = memberData.isChild === true;

      await memberRef.delete();

      // Previously this branch deleted the member doc with no audit at all (FR-6).
      await writeAuditLogTo(db, {
        eventType: "AUDIT_FAMILY_MEMBER_REMOVED",
        actorId,
        subjectType: "family",
        subjectId: activeFamilyId,
        metadata: { removedMemberId: userId, role: memberRole, reason: "account_deleted" },
        clientMetadata,
      });

      if (memberWasChild) {
        // FR-40: child self-deletion is permitted and evidenced; the account is being
        // deleted, so the sticky flag question is moot but the REVOKED lineage is not.
        await writeChildMembershipRevocation(db, {
          familyId: activeFamilyId,
          childUserId: userId,
          actorId,
          actorRole: memberRole,
          method: "delete_account",
          reason: "member_account_deleted",
          clientMetadata,
        });
      }
    }
  }

  // ---- Search lookup indexes (usernames / user_lookup_email / user_lookup_phone)
  const hints = await searchIndexHintsForUser(db, userId, userData);
  await deps.clearSearchIndexes(userId, hints);

  // ---- users/{uid}/private/* (contact email/phoneNumber, fcm push token, ...)
  await deleteSubcollectionDocs(db, userRef, "private");

  // ---- Progression / achievements / public stats keyed by uid
  const progressionRef = db.collection("user_progression").doc(userId);
  await deleteSubcollectionDocs(db, progressionRef, "xp_grants");
  await progressionRef.delete();

  const achievementsRef = db.collection("user_achievements").doc(userId);
  await deleteSubcollectionDocs(db, achievementsRef, "achievements");
  await achievementsRef.delete();

  await db.collection("public_lifetime_stats").doc(userId).delete();

  // ---- Invite rate-limit counters (FR-47). Uid-keyed by doc id, so they would otherwise be
  // residue that names a deleted user and violate FR-50's "no doc anywhere carries the uid".
  await Promise.all(
    inviteRateLimitDocIdsForUser(userId).map((docId) =>
      db.collection(INVITE_RATE_LIMIT_COLLECTION).doc(docId).delete()
    )
  );

  // ---- Shared gameplay residue: de-identified in place, never left uid-keyed.
  // Idempotent and re-runnable; keyed only on uid so requestChildDataDeletion reuses it.
  const deidentified = await deidentifyUserResidue(db, userId);

  // ---- users/{uid} itself (includes any legacy fcmToken / fcmTokenUpdatedAt fields)
  await userRef.delete();

  // ---- FR-78(a): RevenueCat customer deletion (§312.6 — operators answer for vendors'
  // handling of children's data too). Placed last among the pipeline's own work, after every
  // Firestore phase above is durably committed: those phases are all independently idempotent
  // (proven by deidentifyUserResidue's own "no-op on a second run" tests, and by every delete
  // above being a delete-if-exists), so if this call throws — a genuine vendor error, not a
  // 404 or a missing key, both handled as success below — the caller (deleteAccount /
  // requestChildDataDeletion) never reaches `admin.auth().deleteUser`, the Firebase Auth user
  // survives, and a retry re-enters this function from the top: every phase above simply finds
  // nothing left to do, and RevenueCat's DELETE is itself idempotent (a second call 404s), so
  // nothing is "re-run" in any sense that duplicates work or risk — only the still-incomplete
  // vendor call and this audit row are retried.
  const revenueCatDeletionOutcome = await deleteRevenueCatCustomerForUid(
    userId,
    input.revenueCatApiKey ?? null,
    deps.deleteRevenueCatCustomer
  );

  // ---- FR-78(b): Google Analytics (GA4) user deletion — a documented decision, not a call.
  // GA4's User Deletion API is keyed on the app-instance id, which lives client-side only
  // (deliberately: FR-72(c) removed uids from the analytics catalog), and invoking it needs
  // Google Analytics Admin/OAuth credentials — a service account explicitly granted Editor on
  // the GA4 property — which is a materially different, heavier credential than RevenueCat's
  // bearer secret above. This project has provisioned neither the property id nor that service
  // account (nor a Google API client dependency), so a call here would be unverifiable against
  // any real endpoint: dead code wearing a compliance costume, not an FR-78 discharge. The
  // accepted mechanism instead is client-side `Analytics.resetAnalyticsData()` at deletion
  // finalize (`FirebaseAuthService.finalizeDeletedAccountLocally`, FR-72(d)) combined with
  // Google's own configured GA4 data-retention window; the published policy text is NP-3's.

  await writeAuditLogTo(db, {
    eventType: "AUDIT_ACCOUNT_DELETED",
    actorId,
    subjectType: "user",
    subjectId: userId,
    metadata: {
      removedFriendEdgeCount,
      familyAction,
      ...deidentified,
      revenueCatDeletionOutcome,
    },
    clientMetadata,
  });

  return { removedFriendEdgeCount, familyAction, revenueCatDeletionOutcome };
}

/**
 * In-app account deletion (App Review Guideline 5.1.1(v); Privacy Policy §11, ToS §15).
 * Deletes the caller's Firebase Auth user and their personal cloud data:
 * users/{uid} (incl. any legacy fcmToken fields), users/{uid}/private/* (incl. the contact
 * doc holding email/phoneNumber and the fcm doc holding the push token, both swept by
 * listDocuments()), search lookup indexes, friend edges (+friendCount on the
 * surviving side), family membership, user_progression, user_achievements, and
 * public_lifetime_stats.
 *
 * Shared trip data belongs to every participant, so it is de-identified rather than deleted
 * (Privacy Policy §9) — see `deidentifyUserResidue`.
 *
 * A flagged child may self-delete (FR-40): deletion is child-protective, so there is no
 * child gate here, and the child's family exit is evidenced by the REVOKED record above.
 *
 * Requires a recent sign-in (auth_time within RECENT_LOGIN_MAX_AGE_SECONDS); otherwise
 * throws failed-precondition with details.reason = "recent-login-required" so the client
 * can prompt re-authentication and retry.
 */
export const deleteAccount = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    const authTimeSeconds = Number(context.auth?.token?.auth_time ?? 0);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (!isRecentLogin(authTimeSeconds, nowSeconds, RECENT_LOGIN_MAX_AGE_SECONDS)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Recent sign-in is required to delete your account",
        { reason: "recent-login-required" }
      );
    }

    await executeAccountDeletionForUser(admin.firestore(), {
      userId,
      actorId: userId,
      clientMetadata,
      revenueCatApiKey: currentRevenueCatApiKey(),
    });

    // ---- Firebase Auth user last so a failed cleanup above — including the FR-78
    // RevenueCat phase — stays retryable.
    // onAuthUserDeleted then sweeps any other active families this user created.
    await admin.auth().deleteUser(userId);

    return { success: true };
  }
);
