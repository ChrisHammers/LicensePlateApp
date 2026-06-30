/**
 * Append-only XP grant ledger under `user_progression/{uid}/xp_grants/{grantId}`.
 * Every server-side `totalXp` increment must write exactly one grant row in the same transaction.
 */

import * as admin from "firebase-admin";
import { KIND_REGION_FOUND } from "./gameplayEventResolver";
import { KIND_GAME_ENDED } from "./progressionCore";

export const XP_GRANT_SCHEMA_VERSION = 1;

export const XP_GRANT_REASON = {
  REGION_FOUND: "region_found_base_discovery",
  COMPETITIVE_WIN: "competitive_first_place_finish",
  ACHIEVEMENT: "achievement_unlock",
  LEGACY: "legacy_unledgered_balance",
} as const;

export type XpGrantReason = (typeof XP_GRANT_REASON)[keyof typeof XP_GRANT_REASON];

export type XpGrantSourceType = "activity_event" | "achievement" | "migration";

export type XpGrantWriteInput = {
  grantId: string;
  amount: number;
  reason: XpGrantReason;
  sourceType: XpGrantSourceType;
  sourceId: string;
  idempotencyKey: string;
  sessionId?: string;
  achievementId?: string;
  xpRewardAtGrant?: number;
};

export function activityEventXpGrantId(userId: string, eventId: string): string {
  return `activity|${eventId}|${userId}`;
}

export function legacyUnledgeredGrantId(): string {
  return "legacy_unledgered_balance|v1";
}

export function activityEventGrantReason(kind: string): XpGrantReason {
  if (kind === KIND_REGION_FOUND) {
    return XP_GRANT_REASON.REGION_FOUND;
  }
  if (kind === KIND_GAME_ENDED) {
    return XP_GRANT_REASON.COMPETITIVE_WIN;
  }
  throw new Error(`unsupported activity kind for xp grant: ${kind}`);
}

export function xpGrantCollectionRef(db: admin.firestore.Firestore, userId: string) {
  return db.collection("user_progression").doc(userId).collection("xp_grants");
}

export function xpGrantDocRef(db: admin.firestore.Firestore, userId: string, grantId: string) {
  return xpGrantCollectionRef(db, userId).doc(grantId);
}

export function buildXpGrantDocument(input: XpGrantWriteInput): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    schemaVersion: XP_GRANT_SCHEMA_VERSION,
    grantId: input.grantId,
    amount: input.amount,
    reason: input.reason,
    sourceType: input.sourceType,
    sourceId: input.sourceId,
    idempotencyKey: input.idempotencyKey,
    grantedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (input.sessionId) {
    doc.sessionId = input.sessionId;
  }
  if (input.achievementId) {
    doc.achievementId = input.achievementId;
  }
  if (typeof input.xpRewardAtGrant === "number") {
    doc.xpRewardAtGrant = input.xpRewardAtGrant;
  }
  return doc;
}

/**
 * Writes a grant document when absent. Returns true when a new grant row was staged.
 */
export async function writeXpGrantIfAbsent(
  tx: admin.firestore.Transaction,
  db: admin.firestore.Firestore,
  userId: string,
  input: XpGrantWriteInput
): Promise<boolean> {
  if (!Number.isFinite(input.amount) || input.amount <= 0) {
    return false;
  }
  const ref = xpGrantDocRef(db, userId, input.grantId);
  const snap = await tx.get(ref);
  if (snap.exists) {
    return false;
  }
  tx.set(ref, buildXpGrantDocument(input));
  return true;
}

export function sumXpGrantAmounts(
  grantDocs: admin.firestore.QueryDocumentSnapshot[]
): number {
  let total = 0;
  for (const doc of grantDocs) {
    const amount = doc.data().amount;
    if (typeof amount === "number" && Number.isFinite(amount)) {
      total += Math.floor(amount);
    }
  }
  return total;
}
