/**
 * Pure helpers for backfilling missing XP grant rows and sealing legacy orphan balances.
 */

import { achievementUnlockScopeKey } from "./progressionCore";
import {
  legacyUnledgeredGrantId,
  XpGrantWriteInput,
  XP_GRANT_REASON,
} from "./xpGrantLedgerCore";

export type AchievementGrantBackfillCandidate = {
  achievementId: string;
  xpReward: number;
  scopeKey: string;
};

export function achievementGrantBackfillCandidates(input: {
  userId: string;
  appliedScopeKeys: Set<string>;
  achievementDocs: Array<{ id: string; xpReward: number }>;
  existingGrantIds: Set<string>;
}): XpGrantWriteInput[] {
  const out: XpGrantWriteInput[] = [];
  for (const row of input.achievementDocs) {
    if (row.xpReward <= 0) continue;
    const scopeKey = achievementUnlockScopeKey(input.userId, row.id);
    if (!input.appliedScopeKeys.has(scopeKey)) continue;
    if (input.existingGrantIds.has(scopeKey)) continue;
    out.push({
      grantId: scopeKey,
      amount: row.xpReward,
      reason: XP_GRANT_REASON.ACHIEVEMENT,
      sourceType: "achievement",
      sourceId: row.id,
      idempotencyKey: scopeKey,
      achievementId: row.id,
      xpRewardAtGrant: row.xpReward,
    });
  }
  return out;
}

export function legacyUnledgeredGrantWrite(
  amount: number
): XpGrantWriteInput | null {
  if (!Number.isFinite(amount) || amount <= 0) {
    return null;
  }
  const grantId = legacyUnledgeredGrantId();
  return {
    grantId,
    amount,
    reason: XP_GRANT_REASON.LEGACY,
    sourceType: "migration",
    sourceId: grantId,
    idempotencyKey: grantId,
  };
}

export function computeLegacyUnledgeredDelta(
  totalXp: number,
  grantAmounts: number[]
): number {
  const grantSum = grantAmounts.reduce((sum, amount) => sum + amount, 0);
  return Math.max(0, totalXp - grantSum);
}
