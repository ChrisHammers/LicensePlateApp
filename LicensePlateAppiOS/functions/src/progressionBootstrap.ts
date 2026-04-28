import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { buildProgressionBootstrapDefaults } from "./progressionBootstrapCore";
import { enforcedCallable } from "./callableOptions";

const db = admin.firestore();

export const ensureUserProgressionDocument = enforcedCallable(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const userId = context.auth.uid;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
    const ref = db.collection("user_progression").doc(userId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const defaults = buildProgressionBootstrapDefaults(snap.data());
      tx.set(
        ref,
        {
          ...defaults,
          lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    await writeAuditLog({
      eventType: "user_progression_bootstrapped",
      actorId: userId,
      subjectType: "user",
      subjectId: userId,
      clientMetadata,
    });

    return { ok: true };
  }
);
