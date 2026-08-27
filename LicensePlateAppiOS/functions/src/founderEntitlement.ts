import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import {
  FOUNDER_TAG,
  decideFounderGrant,
  parseFounderProgramConfig,
} from "./founderEntitlementCore";

const db = admin.firestore();

export const ensureFounderEntitlementIfEligible = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  if (context.auth.token.firebase?.sign_in_provider === "anonymous") {
    return { outcome: "ineligible", reason: "anonymous" };
  }

  const userId = context.auth.uid;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const userRef = db.collection("users").doc(userId);
  const configRef = db.collection("app_config").doc("founder_program");

  const outcome = await db.runTransaction(async (tx) => {
    const [userSnap, configSnap] = await Promise.all([tx.get(userRef), tx.get(configRef)]);
    const programConfig = parseFounderProgramConfig(configSnap.data());
    const decision = decideFounderGrant({
      userData: userSnap.data(),
      programConfig,
    });

    if (decision.outcome === "alreadyGranted") {
      return { outcome: "alreadyGranted" as const, reason: "already_granted" };
    }

    if (decision.outcome === "programDisabled") {
      return { outcome: "skipped" as const, reason: "program_disabled" };
    }

    if (decision.outcome === "programEnded") {
      return { outcome: "skipped" as const, reason: "program_ended" };
    }

    tx.set(
      userRef,
      {
        entitlementTags: admin.firestore.FieldValue.arrayUnion(FOUNDER_TAG),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { outcome: "granted" as const, reason: "granted" };
  });

  if (outcome.outcome === "granted") {
    await writeAuditLog({
      eventType: "founder_entitlement_granted",
      actorId: userId,
      subjectType: "user",
      subjectId: userId,
      clientMetadata,
    });
  }

  return outcome;
});
