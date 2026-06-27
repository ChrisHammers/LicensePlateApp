import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { achievementCatalogEntry } from "./achievementCatalogCore";
import {
  buildEvaluationContextFromFirestore,
  CandidateWire,
  EntitlementHintsWire,
  evaluateCandidateForSync,
  parseAchievementCandidates,
  planAchievementSyncTransaction,
} from "./syncUserAchievementUnlocksCore";

const db = admin.firestore();
const MAX_CANDIDATES = 20;

async function loadEvaluationContext(
  userId: string,
  entitlementHints: EntitlementHintsWire | undefined
) {
  const [progressionSnap, lifetimeSnap, userSnap] = await Promise.all([
    db.collection("user_progression").doc(userId).get(),
    db.collection("public_lifetime_stats").doc(userId).get(),
    db.collection("users").doc(userId).get(),
  ]);

  return buildEvaluationContextFromFirestore(
    progressionSnap.data() ?? {},
    lifetimeSnap.exists,
    lifetimeSnap.data(),
    userSnap.data() ?? {},
    entitlementHints
  );
}

export const syncUserAchievementUnlocks = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = context.auth.uid;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const entitlementHints = (data?.entitlementHints ?? undefined) as EntitlementHintsWire | undefined;
  const rawCandidates = Array.isArray(data?.candidates) ? (data.candidates as CandidateWire[]) : [];

  const parsed = parseAchievementCandidates(rawCandidates, MAX_CANDIDATES);
  if (!parsed.ok) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `At most ${MAX_CANDIDATES} achievement candidates are allowed`
    );
  }

  if (parsed.deduped.size === 0) {
    return { recordedIds: [], alreadySyncedIds: [], rejectedIds: [] };
  }

  const evaluationContext = await loadEvaluationContext(userId, entitlementHints);
  const recordedIds: string[] = [];
  const alreadySyncedIds: string[] = [];
  const rejectedIds: string[] = [];

  for (const [achievementId, lastProgress] of parsed.deduped.entries()) {
    const candidate = evaluateCandidateForSync(
      achievementId,
      lastProgress,
      evaluationContext,
      achievementCatalogEntry
    );
    if (candidate.kind === "rejected") {
      rejectedIds.push(achievementId);
      continue;
    }

    const { entry, progressToStore } = candidate;
    const achievementRef = db
      .collection("user_achievements")
      .doc(userId)
      .collection("achievements")
      .doc(achievementId);
    const progressionRef = db.collection("user_progression").doc(userId);

    const outcome = await db.runTransaction(async (tx) => {
      const [existingAchievement, progressionDoc] = await Promise.all([
        tx.get(achievementRef),
        tx.get(progressionRef),
      ]);

      const plan = planAchievementSyncTransaction({
        userId,
        achievementId,
        entry,
        progressToStore,
        existingAchievementExists: existingAchievement.exists,
        existingAchievementData: existingAchievement.data(),
        progressionData: (progressionDoc.data() ?? {}) as Record<string, unknown>,
      });

      if (plan.outcome === "already_synced") {
        tx.set(
          achievementRef,
          { lastProgress: plan.achievementWrite.lastProgress },
          { merge: true }
        );
        return "already_synced" as const;
      }

      const achievementWrite: Record<string, unknown> = {
        schemaVersion: 1,
        achievementId: plan.achievementWrite.achievementId,
        unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastProgress: plan.achievementWrite.lastProgress,
        xpReward: plan.achievementWrite.xpReward,
      };

      const progressionWrite: Record<string, unknown> = {
        schemaVersion: 1,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (plan.progressionWrite.shouldIncrementXp) {
        progressionWrite.totalXp = admin.firestore.FieldValue.increment(
          plan.progressionWrite.xpReward
        );
        progressionWrite.appliedProgressionScopes = {
          [plan.progressionWrite.scopeKey]: admin.firestore.FieldValue.serverTimestamp(),
        };
      }

      tx.set(achievementRef, achievementWrite, { merge: true });
      tx.set(progressionRef, progressionWrite, { merge: true });
      return "recorded" as const;
    });

    if (outcome === "recorded") {
      recordedIds.push(achievementId);
    } else {
      alreadySyncedIds.push(achievementId);
    }
  }

  if (recordedIds.length > 0) {
    await writeAuditLog({
      eventType: "user_achievement_unlocks_synced",
      actorId: userId,
      subjectType: "user",
      subjectId: userId,
      metadata: {
        recordedIds,
        alreadySyncedIds,
        rejectedIds,
      },
      clientMetadata,
    });
  }

  return { recordedIds, alreadySyncedIds, rejectedIds };
});
