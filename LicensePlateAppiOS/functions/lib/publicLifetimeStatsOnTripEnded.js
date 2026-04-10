"use strict";
/**
 * Firestore trigger: when a canonical `trip_ended` activity event is created, merge per-user aggregates into
 * `public_lifetime_stats/{uid}` with idempotency via `appliedTrips.{sessionId}`.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.onTripEndedUpdatePublicLifetimeStats = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const publicLifetimeStatsCore_1 = require("./publicLifetimeStatsCore");
const db = admin.firestore();
async function familyMemberIdsForUser(userId) {
    var _a;
    const userSnap = await db.collection("users").doc(userId).get();
    const famId = (_a = userSnap.data()) === null || _a === void 0 ? void 0 : _a.activeFamilyId;
    if (!famId) {
        return new Set();
    }
    const memSnap = await db.collection("families").doc(famId).collection("members").get();
    return new Set(memSnap.docs.map((d) => d.id));
}
exports.onTripEndedUpdatePublicLifetimeStats = functions.firestore
    .document("trip_sessions/{sessionId}/activity_events/{eventId}")
    .onCreate(async (snap, context) => {
    var _a;
    const data = snap.data();
    if (!data || data.kind !== publicLifetimeStatsCore_1.KIND_TRIP_ENDED) {
        return;
    }
    const sessionId = context.params.sessionId;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);
    const [sessionSnap, membersSnap, gamesSnap, eventsSnap] = await Promise.all([
        sessionRef.get(),
        sessionRef.collection("members").get(),
        sessionRef.collection("games").get(),
        sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);
    if (!sessionSnap.exists) {
        return;
    }
    const canonicalStatus = (_a = sessionSnap.data()) === null || _a === void 0 ? void 0 : _a.canonicalStatus;
    const memberUserIds = membersSnap.docs.map((d) => d.id);
    const familyMemberIdsByUser = {};
    await Promise.all(memberUserIds.map(async (uid) => {
        familyMemberIdsByUser[uid] = await familyMemberIdsForUser(uid);
    }));
    const preview = (0, publicLifetimeStatsCore_1.previewTripEndedAggregates)({
        canonicalStatus,
        memberUserIds,
        gameDocs: gamesSnap.docs,
        activityEventDocs: eventsSnap.docs,
        familyMemberIdsByUser,
    });
    if (!preview) {
        return;
    }
    for (const uid of preview.memberUserIds) {
        const deltas = preview.perUser[uid];
        if (!deltas) {
            continue;
        }
        await db.runTransaction(async (tx) => {
            var _a;
            const ref = db.collection("public_lifetime_stats").doc(uid);
            const doc = await tx.get(ref);
            const applied = (_a = doc.data()) === null || _a === void 0 ? void 0 : _a.appliedTrips;
            if (applied && applied[sessionId] != null) {
                return;
            }
            const appliedPath = `appliedTrips.${sessionId}`;
            tx.set(ref, {
                [appliedPath]: admin.firestore.FieldValue.serverTimestamp(),
                totalCompletedTrips: admin.firestore.FieldValue.increment(deltas.totalCompletedTrips),
                totalGamesPlayed: admin.firestore.FieldValue.increment(deltas.totalGamesPlayed),
                totalDiscoveries: admin.firestore.FieldValue.increment(deltas.totalDiscoveries),
                totalWeightedScore: admin.firestore.FieldValue.increment(deltas.totalWeightedScore),
                familyOnlyTripsCount: admin.firestore.FieldValue.increment(deltas.familyOnlyTripsCount),
                lastComputedAt: admin.firestore.FieldValue.serverTimestamp(),
                schemaVersion: 1,
                source: "server_v1",
            }, { merge: true });
        });
    }
});
//# sourceMappingURL=publicLifetimeStatsOnTripEnded.js.map