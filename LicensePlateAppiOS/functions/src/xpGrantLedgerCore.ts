/**
 * Append-only XP grant ledger under `user_progression/{uid}/xp_grants/{grantId}`.
 * Every server-side `totalXp` increment must write exactly one grant row in the same transaction.
 */

import * as admin from "firebase-admin";

export const XP_GRANT_SCHEMA_VERSION = 1;

export const XP_GRANT_REASON = {
  REGION_FOUND: "region_found_base_discovery",
  COMPETITIVE_FIRST_FINDER: "competitive_first_finder",
  LIFETIME_UNIQUE_REGION: "lifetime_unique_region",
  FIRST_FIND_OF_DAY: "first_find_of_day",
  COMPETITIVE_FIRST_PLACE: "competitive_first_place_finish",
  COMPETITIVE_SECOND_PLACE: "competitive_second_place_finish",
  COMPETITIVE_THIRD_PLACE: "competitive_third_place_finish",
  GAME_ENDED: "game_ended",
  GAME_FULL_CLEAR: "game_full_clear",
  TRIP_ENDED: "trip_ended",
  TRIP_PARTICIPATION: "trip_participation",
  TRIP_COMPETITIVE_FIRST: "trip_competitive_first_place",
  ACHIEVEMENT: "achievement_unlock",
  RETURN_STREAK_DAILY: "return_streak_daily",
  LEGACY: "legacy_unledgered_balance",
  /** @deprecated alias — prefer COMPETITIVE_FIRST_PLACE */
  COMPETITIVE_WIN: "competitive_first_place_finish",
} as const;

export type XpGrantReason = (typeof XP_GRANT_REASON)[keyof typeof XP_GRANT_REASON];

export type XpGrantSourceType = "activity_event" | "achievement" | "return_streak" | "migration";

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

export function activityEventComponentXpGrantId(
  userId: string,
  eventId: string,
  scopeKey: string
): string {
  // Scope keys are unique per component; hash-safe by embedding (Firestore doc id max 1500).
  const safe = scopeKey.replace(/[/\\]/g, "_");
  const id = `activity|${eventId}|${userId}|${safe}`;
  if (id.length <= 700) return id;
  // Fallback: stable truncation with length suffix
  return `activity|${eventId}|${userId}|${safe.slice(0, 200)}|${safe.length}`;
}

export function legacyUnledgeredGrantId(): string {
  return "legacy_unledgered_balance|v1";
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
 * Must be the only read/write pair if used alone — for multiple grants in one transaction,
 * use `stageXpGrantsIfAbsent` so all reads happen before any writes.
 */
export async function writeXpGrantIfAbsent(
  tx: admin.firestore.Transaction,
  db: admin.firestore.Firestore,
  userId: string,
  input: XpGrantWriteInput
): Promise<boolean> {
  const staged = await stageXpGrantsIfAbsent(tx, db, userId, [input]);
  return staged === 1;
}

/**
 * Stages zero or more grant docs after reading all grant refs first (Firestore txn rule).
 * Returns how many new grant rows were staged.
 */
export async function stageXpGrantsIfAbsent(
  tx: admin.firestore.Transaction,
  db: admin.firestore.Firestore,
  userId: string,
  inputs: XpGrantWriteInput[]
): Promise<number> {
  const valid = inputs.filter((input) => Number.isFinite(input.amount) && input.amount > 0);
  if (valid.length === 0) {
    return 0;
  }

  const refs = valid.map((input) => xpGrantDocRef(db, userId, input.grantId));
  const snaps = await Promise.all(refs.map((ref) => tx.get(ref)));

  let staged = 0;
  for (let i = 0; i < valid.length; i++) {
    if (snaps[i].exists) {
      continue;
    }
    tx.set(refs[i], buildXpGrantDocument(valid[i]));
    staged += 1;
  }
  return staged;
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
