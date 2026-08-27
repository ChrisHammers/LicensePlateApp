import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertNotUnconsentedChild } from "./callableAuth";
import {
  achievementGrantBackfillCandidates,
  computeLegacyUnledgeredDelta,
  legacyUnledgeredGrantWrite,
} from "./reconcileXpGrantLedgerCore";
import {
  legacyUnledgeredGrantId,
  sumXpGrantAmounts,
  writeXpGrantIfAbsent,
  xpGrantCollectionRef,
} from "./xpGrantLedgerCore";

const db = admin.firestore();

function getMergedStringKeyMap(
  docData: Record<string, unknown>,
  nestedFieldName: "appliedProgressionScopes"
): Record<string, unknown> | undefined {
  const nested = docData[nestedFieldName];
  if (
    nested !== null &&
    nested !== undefined &&
    !Array.isArray(nested) &&
    typeof nested === "object"
  ) {
    return nested as Record<string, unknown>;
  }
  const prefix = `${nestedFieldName}.`;
  const synthetic: Record<string, unknown> = {};
  for (const k of Object.keys(docData)) {
    if (k.startsWith(prefix) && k.length > prefix.length) {
      synthetic[k.slice(prefix.length)] = docData[k] as unknown;
    }
  }
  return Object.keys(synthetic).length > 0 ? synthetic : undefined;
}

export const reconcileXpGrantLedger = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = context.auth.uid;
  await assertNotUnconsentedChild(db, userId); // COPPA FR-28
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const progressionRef = db.collection("user_progression").doc(userId);
  const grantsRef = xpGrantCollectionRef(db, userId);

  const [progressionSnap, grantsSnap, achievementsSnap] = await Promise.all([
    progressionRef.get(),
    grantsRef.get(),
    db
      .collection("user_achievements")
      .doc(userId)
      .collection("achievements")
      .get(),
  ]);

  const progressionData = (progressionSnap.data() ?? {}) as Record<string, unknown>;
  const totalXp =
    typeof progressionData.totalXp === "number" && Number.isFinite(progressionData.totalXp)
      ? Math.floor(progressionData.totalXp)
      : 0;

  const existingGrantIds = new Set(grantsSnap.docs.map((doc) => doc.id));
  const scopesMap = getMergedStringKeyMap(progressionData, "appliedProgressionScopes");
  const appliedScopeKeys = new Set(Object.keys(scopesMap ?? {}));

  const achievementDocs = achievementsSnap.docs.map((doc) => {
    const row = doc.data();
    const xpReward =
      typeof row.xpReward === "number" && Number.isFinite(row.xpReward)
        ? Math.floor(row.xpReward)
        : 0;
    return {
      id: (typeof row.achievementId === "string" ? row.achievementId : doc.id).trim(),
      xpReward,
    };
  });

  const achievementBackfills = achievementGrantBackfillCandidates({
    userId,
    appliedScopeKeys,
    achievementDocs,
    existingGrantIds,
  });

  let backfilledAchievementGrants = 0;
  for (const grant of achievementBackfills) {
    await db.runTransaction(async (tx) => {
      const wrote = await writeXpGrantIfAbsent(tx, db, userId, grant);
      if (wrote) {
        backfilledAchievementGrants += 1;
        existingGrantIds.add(grant.grantId);
      }
    });
  }

  const refreshedGrantsSnap = await grantsRef.get();
  const legacyDelta = computeLegacyUnledgeredDelta(totalXp, refreshedGrantsSnap.docs.map((doc) => {
    const amount = doc.data().amount;
    return typeof amount === "number" && Number.isFinite(amount) ? Math.floor(amount) : 0;
  }));

  let legacyAmount = 0;
  if (legacyDelta > 0 && !existingGrantIds.has(legacyUnledgeredGrantId())) {
    const legacyGrant = legacyUnledgeredGrantWrite(legacyDelta);
    if (legacyGrant) {
      await db.runTransaction(async (tx) => {
        const wrote = await writeXpGrantIfAbsent(tx, db, userId, legacyGrant);
        if (wrote) {
          legacyAmount = legacyGrant.amount;
        }
      });
    }
  }

  const finalGrantsSnap = await grantsRef.get();
  const verifiedTotalXp = sumXpGrantAmounts(finalGrantsSnap.docs);
  const totalXpMatchesGrants = verifiedTotalXp === totalXp;

  await writeAuditLog({
    eventType: "xp_grant_ledger_reconciled",
    actorId: userId,
    subjectType: "user",
    subjectId: userId,
    metadata: {
      totalXp,
      verifiedTotalXp,
      totalXpMatchesGrants,
      backfilledAchievementGrants,
      legacyAmount,
      grantCount: finalGrantsSnap.size,
    },
    clientMetadata,
  });

  return {
    ok: true,
    totalXp,
    verifiedTotalXp,
    totalXpMatchesGrants,
    backfilledAchievementGrants,
    legacyAmount,
    grantCount: finalGrantsSnap.size,
  };
});
