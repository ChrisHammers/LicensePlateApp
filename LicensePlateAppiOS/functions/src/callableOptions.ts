import * as functions from "firebase-functions/v1";

type CallableHandler = Parameters<typeof functions.https.onCall>[0];
type RunWithOptions = Parameters<typeof functions.runWith>[0];

/**
 * `options.secrets` lets a callable declare Firebase Functions secrets it needs resolved
 * at runtime (e.g. `deleteAccount`'s RevenueCat key, FR-78) without every other callable
 * having to know about them — omit it and behavior is unchanged.
 */
export function enforcedCallable(
  handler: CallableHandler,
  options?: Pick<RunWithOptions, "secrets">
) {
  return functions
    .runWith({ enforceAppCheck: true, ...options })
    .https.onCall(handler);
}
