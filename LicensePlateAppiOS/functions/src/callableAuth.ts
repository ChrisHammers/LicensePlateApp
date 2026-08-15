import * as functions from "firebase-functions";
import type * as admin from "firebase-admin";
import { isChildAccountUserData, isUnconsentedChildUserData } from "./childAccountCore";

type CallableContext = functions.https.CallableContext;

/**
 * The single wording behind every "you need a registered account" refusal.
 *
 * FR-24 indistinguishability: `assertRegisteredAccountOrDeclaredChild` refuses a plain
 * anonymous caller with a reply that must be BYTE-IDENTICAL to `assertRegisteredAccount`'s —
 * same code, same message, no `details`. If the carve-out's refusal read differently, an
 * anonymous caller could diff the two replies and learn whether the uid it is holding is a
 * declared child. Sharing the constant makes that identity structural rather than a
 * copy-paste both sides have to keep in step; `callableAuth.test.ts` pins it field by field.
 */
export const REGISTERED_ACCOUNT_REQUIRED_MESSAGE =
  "A registered account is required for this action";

export function assertAuthenticated(context: CallableContext): string {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }
  return context.auth.uid;
}

function registeredAccountRequiredError(): functions.https.HttpsError {
  return new functions.https.HttpsError(
    "failed-precondition",
    REGISTERED_ACCOUNT_REQUIRED_MESSAGE
  );
}

function isAnonymousCaller(context: CallableContext): boolean {
  return context.auth?.token?.firebase?.sign_in_provider === "anonymous";
}

/** Rejects Firebase anonymous accounts; requires email/OAuth-linked sign-in. */
export function assertRegisteredAccount(context: CallableContext): string {
  const userId = assertAuthenticated(context);
  if (isAnonymousCaller(context)) {
    throw registeredAccountRequiredError();
  }
  return userId;
}

/**
 * COPPA FR-60 (F-18) — the registration carve-out for declared children.
 *
 * Under the local-first model an under-13 player has NO backend identity until the moment
 * they seek consent: share-code entry mints the anonymous uid, binds it, declares it, and
 * only then redeems. That declared-but-anonymous caller has to get through the two consent
 * exits — `redeemShareCode` and `respondToFamilyInvite_UserStep` — or the exits it was
 * provisioned for are closed to the only population that needs them. `assertRegisteredAccount`
 * would dead-end every one of those calls.
 *
 * Passes: any registered (non-anonymous) account, exactly as before; and an anonymous caller
 * whose `users/{uid}.isChildAccount` is true. The flag is read SERVER-SIDE from the user doc
 * — never claimed in the payload — and it is server-written-only (`declareChildRegistration`
 * via the Admin SDK, plus the `firestore.rules` diff-guard), so an anonymous caller cannot
 * mint the credential that lets them through. Fails: every other anonymous caller.
 *
 * The sticky post-revocation child (consented once, revoked, flag still true) reaches the
 * same exit through the same clause — they already hold a uid, and re-admission is their
 * route back.
 *
 * FR-3's standing note about `declareChildRegistration` applies here too: these carve-outs
 * MUST NOT be "hardened" back to registered-only without re-opening CB-2. A hardening pass
 * that reads `assertRegisteredAccountOrDeclaredChild` as a weakened `assertRegisteredAccount`
 * would silently lock every unconsented child out of consent itself.
 */
export async function assertRegisteredAccountOrDeclaredChild(
  db: admin.firestore.Firestore,
  context: CallableContext
): Promise<string> {
  const userId = assertAuthenticated(context);
  if (!isAnonymousCaller(context)) {
    return userId;
  }
  const snapshot = await db.collection("users").doc(userId).get();
  if (isChildAccountUserData(snapshot.data())) {
    return userId;
  }
  throw registeredAccountRequiredError();
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
