import * as functions from "firebase-functions";

type CallableHandler = Parameters<typeof functions.https.onCall>[0];

export function enforcedCallable(handler: CallableHandler) {
  return functions
    .runWith({ enforceAppCheck: true })
    .https.onCall(handler);
}
