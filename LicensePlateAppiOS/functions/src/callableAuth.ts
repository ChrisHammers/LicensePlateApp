import * as functions from "firebase-functions";

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
