/**
 * Client reports a qualifying return-streak day; server grants daily XP when streak >= 2.
 * Idempotent per user per calendar dayKey via appliedProgressionScopes.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import { assertNotUnconsentedChild } from "./callableAuth";
import { planReturnStreakDailyClaim } from "./claimReturnStreakDailyXpCore";
import { writeXpGrantIfAbsent, XP_GRANT_REASON } from "./xpGrantLedgerCore";

const db = admin.firestore();

export const claimReturnStreakDailyXp = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = context.auth.uid;
  await assertNotUnconsentedChild(db, userId); // COPPA FR-28
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const progressionRef = db.collection("user_progression").doc(userId);

  const result = await db.runTransaction(async (tx) => {
    const progressionDoc = await tx.get(progressionRef);
    const plan = planReturnStreakDailyClaim({
      userId,
      dayKey: data?.dayKey,
      currentStreak: data?.currentStreak,
      progressionData: (progressionDoc.data() ?? {}) as Record<string, unknown>,
    });

    if (plan.outcome === "rejected") {
      const message =
        plan.reason === "streak_below_minimum"
          ? "Return streak XP requires currentStreak >= 2"
          : plan.reason === "invalid_day_key"
            ? "dayKey must be YYYY-MM-DD"
            : "currentStreak must be a positive integer";
      throw new functions.https.HttpsError("invalid-argument", message);
    }

    if (plan.outcome === "already_claimed") {
      return { granted: false as const, alreadyClaimed: true as const, scopeKey: plan.scopeKey };
    }

    const progressionWrite: Record<string, unknown> = {
      schemaVersion: 1,
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      totalXp: admin.firestore.FieldValue.increment(plan.amount),
      appliedProgressionScopes: {
        [plan.scopeKey]: admin.firestore.FieldValue.serverTimestamp(),
      },
    };

    await writeXpGrantIfAbsent(tx, db, userId, {
      grantId: plan.scopeKey,
      amount: plan.amount,
      reason: XP_GRANT_REASON.RETURN_STREAK_DAILY,
      sourceType: "return_streak",
      sourceId: plan.dayKey,
      idempotencyKey: plan.scopeKey,
      xpRewardAtGrant: plan.amount,
    });

    tx.set(progressionRef, progressionWrite, { merge: true });
    return {
      granted: true as const,
      alreadyClaimed: false as const,
      scopeKey: plan.scopeKey,
      amount: plan.amount,
      dayKey: plan.dayKey,
      currentStreak: plan.currentStreak,
    };
  });

  if (result.granted) {
    await writeAuditLog({
      eventType: "return_streak_daily_xp_claimed",
      actorId: userId,
      subjectType: "user",
      subjectId: userId,
      metadata: {
        dayKey: result.dayKey,
        currentStreak: result.currentStreak,
        amount: result.amount,
        scopeKey: result.scopeKey,
      },
      clientMetadata,
    });
  }

  return {
    granted: result.granted,
    alreadyClaimed: result.alreadyClaimed,
    scopeKey: result.scopeKey,
    amount: result.granted ? result.amount : 0,
  };
});
