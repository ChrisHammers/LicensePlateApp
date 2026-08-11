import * as functions from "firebase-functions";
import type * as admin from "firebase-admin";
import { isUnconsentedChildUserData } from "./childAccountCore";

type CallableContext = functions.https.CallableContext;

export function assertAuthenticated(context: CallableContext): string {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }
  return context.auth.uid;
}

/** Rejects Firebase anonymous accounts; requires email/OAuth-linked sign-in. */
export function assertRegisteredAccount(context: CallableContext): string {
  const userId = assertAuthenticated(context);
  const provider = context.auth?.token?.firebase?.sign_in_provider;
  if (provider === "anonymous") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "A registered account is required for this action"
    );
  }
  return userId;
}

/**
 * COPPA FR-28: rejects callers who are UNCONSENTED children — `isChildAccount == true`
 * with no active family (provisional after `declareChildRegistration`, or sticky after a
 * consent revocation). Applied to every state-mutating gameplay callable so cloud
 * collection stops the moment consent is absent; local/offline play is unaffected and
 * the queued events upload once a manager admits the child (deterministic, idempotent).
 *
 * Deliberately NOT applied to `redeemShareCode`, `respondToFamilyInvite_UserStep`, or
 * `deleteAccount` — those are the child's paths back into consented play and out of the
 * system. One `users/{uid}` get per call; a missing doc or missing flag means adult.
 *
 * `details.reason` lets the client distinguish this from other failed-preconditions and
 * show the non-punitive "Ask a parent to add you to their family" state (F-6).
 */
export async function assertNotUnconsentedChild(
  db: admin.firestore.Firestore,
  userId: string
): Promise<void> {
  const snapshot = await db.collection("users").doc(userId).get();
  if (isUnconsentedChildUserData(snapshot.data())) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "A parent-managed family is required before this account can sync",
      { reason: "unconsented_child" }
    );
  }
}
