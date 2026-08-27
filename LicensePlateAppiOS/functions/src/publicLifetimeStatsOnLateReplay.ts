/**
 * Firestore trigger: FR-28h — a `region_found` accepted into an already-ended game
 * (offline / consent replay) still has to reach `public_lifetime_stats`.
 *
 * `onTripEndedUpdatePublicLifetimeStats` is a one-shot per session, guarded by the trip's
 * applied marker: it fires on `trip_ended` and never runs again. A find that lands after
 * it has already run would therefore never be counted — the data loss FR-28h exists to
 * stop.
 *
 * The two triggers share ONE exactly-once contract, because either can see a late find
 * first:
 *
 * - `trip_ended` fires AFTER the late finds drained (the common consent ordering): the
 *   baseline recompute already counts them, and records that portion in the ledger.
 * - A late find lands AFTER the baseline ran: this trigger applies the difference between
 *   the total late contribution and whatever the ledger says is already inside the totals.
 *
 * Either way the ledger is the single record of "late contribution already counted", so
 * neither trigger can double-apply and repeated firings converge.
 *
 * The whole read → diff → apply → record sequence runs in ONE transaction, INCLUDING the
 * recompute. Computing the total outside and applying it inside would let two
 * near-simultaneous firings each apply a stale total — which, because a late find can
 * legitimately REDUCE a peer's collaborative credit, can bake in a permanent negative.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  hasAppliedTripBaseline,
  isLateReplayFindDoc,
  lateReplayLedgerRef,
  previewLateReplayContribution,
  readLateReplayLedger,
  sessionHasTripEndedEvent,
  decideBaselineWait,
  BASELINE_MARKER_POLL_INTERVAL_MS,
  BASELINE_MARKER_MAX_WAIT_MS,
  type LateReplayStatsContribution,
} from "./publicLifetimeStatsCore";

const db = admin.firestore();

/** Floating-point weighted scores: treat sub-epsilon movement as nothing to do. */
function isNegligible(delta: LateReplayStatsContribution): boolean {
  return delta.totalDiscoveries === 0 && Math.abs(delta.totalWeightedScore) < 1e-9;
}

async function anyBaselineMarkerPresent(
  memberUserIds: string[],
  sessionId: string
): Promise<boolean> {
  const docs = await Promise.all(
    memberUserIds.map((uid) => db.collection("public_lifetime_stats").doc(uid).get())
  );
  return docs.some((d) => hasAppliedTripBaseline(d.data(), sessionId));
}

/**
 * When the baseline is in flight, wait (bounded) for its marker so the diff below can see
 * what it actually applied. Returns regardless — the transaction re-checks the marker and
 * aborts to a no-op if it still has not landed, so we never apply before the baseline.
 */
async function waitForBaselineMarkerIfImminent(
  sessionRef: admin.firestore.DocumentReference,
  sessionId: string,
  memberUserIds: string[]
): Promise<void> {
  if (await anyBaselineMarkerPresent(memberUserIds, sessionId)) {
    return;
  }
  const eventsSnap = await sessionRef.collection("activity_events").get();
  const decision = decideBaselineWait({
    hasTripEnded: sessionHasTripEndedEvent(eventsSnap.docs),
    markerPresent: false,
  });
  if (decision !== "wait") {
    return;
  }
  const deadline = Date.now() + BASELINE_MARKER_MAX_WAIT_MS;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, BASELINE_MARKER_POLL_INTERVAL_MS));
    if (await anyBaselineMarkerPresent(memberUserIds, sessionId)) {
      return;
    }
  }
  functions.logger.warn("late-replay stats: baseline marker never appeared within bound", {
    sessionId,
    waitedMs: BASELINE_MARKER_MAX_WAIT_MS,
  });
}

export const onLateReplayUpdatePublicLifetimeStats = functions.firestore
  .document("trip_sessions/{sessionId}/activity_events/{eventId}")
  .onCreate(async (snap, context) => {
    if (!isLateReplayFindDoc(snap as admin.firestore.QueryDocumentSnapshot)) {
      return;
    }

    const sessionId = context.params.sessionId as string;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);

    // Members are read outside: the roster is not what concurrent late finds race over,
    // and keeping it out bounds the transaction's read set.
    const membersSnap = await sessionRef.collection("members").get();
    const memberUserIds = membersSnap.docs.map((d) => d.id);
    if (memberUserIds.length === 0) {
      return;
    }

    // G5 — the baseline's lost-update window. The trip-end trigger reads the event log
    // ONCE and then commits per-user transactions sequentially; a find created inside that
    // window is missed by the baseline's totals AND skipped here (no marker yet), so it
    // would be counted nowhere.
    //
    // Distinguish the two cases before deciding:
    //   no `trip_ended`  → genuinely pre-baseline. Doing nothing is correct: finds drain
    //                      before `trip_ended`, so the baseline's read will include this.
    //   `trip_ended` yes → the baseline is imminent or in flight. Wait for its marker, then
    //                      let the ordinary cumulative-minus-ledger diff pick up whatever
    //                      it missed — the diff is exact by construction either way.
    //
    // Waiting in-function rather than throwing is deliberate: v1 `onCreate` retries are
    // disabled by default, so a throw would DISCARD the event and lose the find for good.
    await waitForBaselineMarkerIfImminent(sessionRef, sessionId, memberUserIds);

    await db.runTransaction(async (tx) => {
      // Recompute INSIDE the transaction so a concurrent firing cannot commit a total that
      // was computed against an older set of events.
      const [sessionSnap, gamesSnap, eventsSnap] = await Promise.all([
        tx.get(sessionRef),
        tx.get(sessionRef.collection("games")),
        tx.get(sessionRef.collection("activity_events").orderBy("timestamp", "asc")),
      ]);
      if (!sessionSnap.exists) {
        return;
      }

      const cumulativeByUser = previewLateReplayContribution({
        canonicalStatus: sessionSnap.data()?.canonicalStatus as string | undefined,
        memberUserIds,
        gameDocs: gamesSnap.docs,
        activityEventDocs: eventsSnap.docs,
      });
      if (!cumulativeByUser) {
        return;
      }

      const statsRefs = memberUserIds.map((uid) => db.collection("public_lifetime_stats").doc(uid));
      const ledgerRefs = memberUserIds.map((uid) => lateReplayLedgerRef(db, uid, sessionId));
      const [statsDocs, ledgerDocs] = await Promise.all([
        Promise.all(statsRefs.map((ref) => tx.get(ref))),
        Promise.all(ledgerRefs.map((ref) => tx.get(ref))),
      ]);

      memberUserIds.forEach((uid, index) => {
        const cumulative = cumulativeByUser[uid];
        if (!cumulative) {
          return;
        }

        // Baseline has not run yet — it recomputes from the whole log and will count this
        // find itself. Applying anything here would double it.
        if (!hasAppliedTripBaseline(statsDocs[index].data(), sessionId)) {
          return;
        }

        const already = readLateReplayLedger(ledgerDocs[index].data());
        const remainder: LateReplayStatsContribution = {
          totalDiscoveries: cumulative.totalDiscoveries - already.totalDiscoveries,
          totalWeightedScore: cumulative.totalWeightedScore - already.totalWeightedScore,
        };
        if (isNegligible(remainder)) {
          return;
        }

        tx.set(
          statsRefs[index],
          {
            totalDiscoveries: admin.firestore.FieldValue.increment(remainder.totalDiscoveries),
            totalWeightedScore: admin.firestore.FieldValue.increment(remainder.totalWeightedScore),
            lastComputedAt: admin.firestore.FieldValue.serverTimestamp(),
            schemaVersion: 1,
            source: "server_v1",
          },
          { merge: true }
        );
        tx.set(
          ledgerRefs[index],
          {
            totalDiscoveries: cumulative.totalDiscoveries,
            totalWeightedScore: cumulative.totalWeightedScore,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "late_replay_trigger",
          },
          { merge: true }
        );
      });
    });
  });
