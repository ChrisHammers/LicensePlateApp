import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import {
  achievementCatalogEntry,
  isKnownVisibleAchievementId,
} from "./achievementCatalogCore";
import {
  AchievementEvaluationContext,
  evaluateAchievement,
} from "./achievementProgressCore";
import { achievementUnlockScopeKey } from "./progressionCore";

const db = admin.firestore();
const MAX_CANDIDATES = 20;

type CandidateWire = {
  achievementId?: unknown;
  lastProgress?: unknown;
};

type EntitlementHintsWire = {
  isRoyale?: unknown;
  isFounder?: unknown;
};

function cleanAchievementId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function cleanProgress(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.floor(value));
}

function boolValue(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  return false;
}

function getMergedStringKeyMap(
  docData: Record<string, unknown>,
  nestedFieldName: "appliedProgressionScopes"
): Record<string, unknown> | undefined {
  const nested = docData[nestedFieldName];
  if (nested !== null && nested !== undefined && !Array.isArray(nested) && typeof nested === "object") {
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

async function loadEvaluationContext(
  userId: string,
  entitlementHints: EntitlementHintsWire | undefined
): Promise<AchievementEvaluationContext> {
  const [progressionSnap, lifetimeSnap, userSnap] = await Promise.all([
    db.collection("user_progression").doc(userId).get(),
    db.collection("public_lifetime_stats").doc(userId).get(),
    db.collection("users").doc(userId).get(),
  ]);

  const progressionData = progressionSnap.data() ?? {};
  const userData = userSnap.data() ?? {};
  const activeFamilyId = userData.activeFamilyId as string | undefined;
  const wasEverInFamily = boolValue(userData.wasEverInFamily);

  return {
    progression: {
      totalXp: typeof progressionData.totalXp === "number" ? progressionData.totalXp : 0,
      acceptedRegionFindCount:
        typeof progressionData.acceptedRegionFindCount === "number"
          ? progressionData.acceptedRegionFindCount
          : 0,
      competitiveFirstPlaceFinishes:
        typeof progressionData.competitiveFirstPlaceFinishes === "number"
          ? progressionData.competitiveFirstPlaceFinishes
          : 0,
      everCompetitiveFirstPlace: boolValue(progressionData.everCompetitiveFirstPlace),
    },
    lifetimeStats: lifetimeSnap.exists
      ? {
          totalCompletedTrips:
            typeof lifetimeSnap.data()?.totalCompletedTrips === "number"
              ? (lifetimeSnap.data()?.totalCompletedTrips as number)
              : 0,
          totalDiscoveries:
            typeof lifetimeSnap.data()?.totalDiscoveries === "number"
              ? (lifetimeSnap.data()?.totalDiscoveries as number)
              : 0,
        }
      : null,
    isFamilyMember: !!activeFamilyId || wasEverInFamily,
    isRoyale: boolValue(entitlementHints?.isRoyale),
    isFounder: boolValue(entitlementHints?.isFounder),
  };
}

export const syncUserAchievementUnlocks = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = context.auth.uid;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const entitlementHints = (data?.entitlementHints ?? undefined) as EntitlementHintsWire | undefined;
  const rawCandidates = Array.isArray(data?.candidates) ? (data.candidates as CandidateWire[]) : [];

  if (rawCandidates.length > MAX_CANDIDATES) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `At most ${MAX_CANDIDATES} achievement candidates are allowed`
    );
  }

  const deduped = new Map<string, number>();
  for (const candidate of rawCandidates) {
    const achievementId = cleanAchievementId(candidate.achievementId);
    if (!achievementId || !isKnownVisibleAchievementId(achievementId)) continue;
    const lastProgress = cleanProgress(candidate.lastProgress);
    deduped.set(achievementId, Math.max(deduped.get(achievementId) ?? 0, lastProgress));
  }

  if (deduped.size === 0) {
    return { recordedIds: [], alreadySyncedIds: [], rejectedIds: [] };
  }

  const evaluationContext = await loadEvaluationContext(userId, entitlementHints);
  const recordedIds: string[] = [];
  const alreadySyncedIds: string[] = [];
  const rejectedIds: string[] = [];

  for (const [achievementId, lastProgress] of deduped.entries()) {
    const entry = achievementCatalogEntry(achievementId);
    if (!entry) {
      rejectedIds.push(achievementId);
      continue;
    }

    const evaluation = evaluateAchievement(entry, evaluationContext);
    if (!evaluation.unlocked) {
      rejectedIds.push(achievementId);
      continue;
    }

    const achievementRef = db
      .collection("user_achievements")
      .doc(userId)
      .collection("achievements")
      .doc(achievementId);
    const progressionRef = db.collection("user_progression").doc(userId);
    const scopeKey = achievementUnlockScopeKey(userId, achievementId);
    const progressToStore = Math.max(lastProgress, evaluation.progress);

    const outcome = await db.runTransaction(async (tx) => {
      const [existingAchievement, progressionDoc] = await Promise.all([
        tx.get(achievementRef),
        tx.get(progressionRef),
      ]);

      if (existingAchievement.exists) {
        tx.set(
          achievementRef,
          {
            lastProgress: Math.max(
              typeof existingAchievement.data()?.lastProgress === "number"
                ? (existingAchievement.data()?.lastProgress as number)
                : 0,
              progressToStore
            ),
          },
          { merge: true }
        );
        return "already_synced" as const;
      }

      const progressionData = (progressionDoc.data() ?? {}) as Record<string, unknown>;
      const scopesMap = getMergedStringKeyMap(progressionData, "appliedProgressionScopes");
      const xpAlreadyGranted = !!(scopesMap && scopesMap[scopeKey] != null);

      const achievementWrite: Record<string, unknown> = {
        schemaVersion: 1,
        achievementId,
        unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastProgress: progressToStore,
        xpReward: entry.xpReward,
      };

      const progressionWrite: Record<string, unknown> = {
        schemaVersion: 1,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (entry.xpReward > 0 && !xpAlreadyGranted) {
        progressionWrite.totalXp = admin.firestore.FieldValue.increment(entry.xpReward);
        progressionWrite.appliedProgressionScopes = {
          [scopeKey]: admin.firestore.FieldValue.serverTimestamp(),
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
