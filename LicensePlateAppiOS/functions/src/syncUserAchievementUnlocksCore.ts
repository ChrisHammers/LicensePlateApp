import {
  AchievementCatalogEntry,
  isKnownVisibleAchievementId,
} from "./achievementCatalogCore";
import {
  AchievementEvaluationContext,
  AchievementEvaluationResult,
  evaluateAchievement,
} from "./achievementProgressCore";
import { achievementUnlockScopeKey } from "./progressionCore";
import { hasFounderTag } from "./founderEntitlementCore";

export type CandidateWire = {
  achievementId?: unknown;
  lastProgress?: unknown;
};

export type EntitlementHintsWire = {
  isRoyale?: unknown;
};

export type ParseCandidatesResult =
  | { ok: true; deduped: Map<string, number> }
  | { ok: false; error: "too_many" };

export type CandidateEvaluationResult =
  | { kind: "rejected" }
  | {
      kind: "accepted";
      entry: AchievementCatalogEntry;
      progressToStore: number;
      evaluation: AchievementEvaluationResult;
    };

export type SyncTransactionPlan = {
  outcome: "recorded" | "already_synced";
  progressToStore: number;
  achievementWrite: {
    isNew: boolean;
    achievementId: string;
    lastProgress: number;
    xpReward: number;
  };
  progressionWrite: {
    shouldIncrementXp: boolean;
    xpReward: number;
    scopeKey: string;
  };
};

export function cleanAchievementId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function cleanProgress(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.floor(value));
}

export function boolValue(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  return false;
}

export function getMergedStringKeyMap(
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

export function parseAchievementCandidates(
  raw: CandidateWire[],
  maxCandidates: number
): ParseCandidatesResult {
  if (raw.length > maxCandidates) {
    return { ok: false, error: "too_many" };
  }

  const deduped = new Map<string, number>();
  for (const candidate of raw) {
    const achievementId = cleanAchievementId(candidate.achievementId);
    if (!achievementId || !isKnownVisibleAchievementId(achievementId)) continue;
    const lastProgress = cleanProgress(candidate.lastProgress);
    deduped.set(achievementId, Math.max(deduped.get(achievementId) ?? 0, lastProgress));
  }

  return { ok: true, deduped };
}

export function buildEvaluationContextFromFirestore(
  progressionData: Record<string, unknown>,
  lifetimeSnapExists: boolean,
  lifetimeData: Record<string, unknown> | undefined,
  userData: Record<string, unknown>,
  entitlementHints: EntitlementHintsWire | undefined
): AchievementEvaluationContext {
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
    lifetimeStats: lifetimeSnapExists
      ? {
          totalCompletedTrips:
            typeof lifetimeData?.totalCompletedTrips === "number"
              ? (lifetimeData.totalCompletedTrips as number)
              : 0,
          totalDiscoveries:
            typeof lifetimeData?.totalDiscoveries === "number"
              ? (lifetimeData.totalDiscoveries as number)
              : 0,
        }
      : null,
    isFamilyMember: !!activeFamilyId || wasEverInFamily,
    isRoyale: boolValue(entitlementHints?.isRoyale),
    isFounder: hasFounderTag(userData),
  };
}

export function evaluateCandidateForSync(
  achievementId: string,
  lastProgress: number,
  evaluationContext: AchievementEvaluationContext,
  lookupEntry: (id: string) => AchievementCatalogEntry | undefined = (id) => {
    // Lazy import avoided; callers pass lookup in tests or use achievementCatalogEntry in wrapper
    void id;
    return undefined;
  }
): CandidateEvaluationResult {
  const entry = lookupEntry(achievementId);
  if (!entry) {
    return { kind: "rejected" };
  }

  const evaluation = evaluateAchievement(entry, evaluationContext);
  if (!evaluation.unlocked) {
    return { kind: "rejected" };
  }

  return {
    kind: "accepted",
    entry,
    progressToStore: Math.max(lastProgress, evaluation.progress),
    evaluation,
  };
}

export function planAchievementSyncTransaction(params: {
  userId: string;
  achievementId: string;
  entry: AchievementCatalogEntry;
  progressToStore: number;
  existingAchievementExists: boolean;
  existingAchievementData: Record<string, unknown> | undefined;
  progressionData: Record<string, unknown>;
}): SyncTransactionPlan {
  const {
    userId,
    achievementId,
    entry,
    progressToStore,
    existingAchievementExists,
    existingAchievementData,
    progressionData,
  } = params;

  const scopeKey = achievementUnlockScopeKey(userId, achievementId);

  if (existingAchievementExists) {
    const existingProgress =
      typeof existingAchievementData?.lastProgress === "number"
        ? (existingAchievementData.lastProgress as number)
        : 0;
    return {
      outcome: "already_synced",
      progressToStore: Math.max(existingProgress, progressToStore),
      achievementWrite: {
        isNew: false,
        achievementId,
        lastProgress: Math.max(existingProgress, progressToStore),
        xpReward: entry.xpReward,
      },
      progressionWrite: {
        shouldIncrementXp: false,
        xpReward: entry.xpReward,
        scopeKey,
      },
    };
  }

  const scopesMap = getMergedStringKeyMap(progressionData, "appliedProgressionScopes");
  const xpAlreadyGranted = !!(scopesMap && scopesMap[scopeKey] != null);
  const shouldIncrementXp = entry.xpReward > 0 && !xpAlreadyGranted;

  return {
    outcome: "recorded",
    progressToStore,
    achievementWrite: {
      isNew: true,
      achievementId,
      lastProgress: progressToStore,
      xpReward: entry.xpReward,
    },
    progressionWrite: {
      shouldIncrementXp,
      xpReward: entry.xpReward,
      scopeKey,
    },
  };
}
