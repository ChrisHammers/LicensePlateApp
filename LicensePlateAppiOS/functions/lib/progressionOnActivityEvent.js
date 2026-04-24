"use strict";
/**
 * Firestore trigger: merge per-user progression into `user_progression/{uid}` when canonical
 * `region_found` or `game_ended` activity events are created. Idempotent via `appliedProgressionEvents.{eventId}`.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.onActivityEventUpdateUserProgression = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const gameplayEventResolver_1 = require("./gameplayEventResolver");
const progressionCore_1 = require("./progressionCore");
const db = admin.firestore();
/**
 * Reads `appliedProgressionEvents` / `appliedProgressionScopes` as a string-keyed map.
 * Supports nested maps (preferred) and legacy top-level keys `fieldName.<id>` from older set() encoding.
 */
function getMergedStringKeyMap(docData, nestedFieldName) {
    const nested = docData[nestedFieldName];
    if (nested !== null && nested !== undefined && !Array.isArray(nested) && typeof nested === "object") {
        return nested;
    }
    const prefix = `${nestedFieldName}.`;
    const synthetic = {};
    for (const k of Object.keys(docData)) {
        if (k.startsWith(prefix) && k.length > prefix.length) {
            synthetic[k.slice(prefix.length)] = docData[k];
        }
    }
    return Object.keys(synthetic).length > 0 ? synthetic : undefined;
}
exports.onActivityEventUpdateUserProgression = functions.firestore
    .document("trip_sessions/{sessionId}/activity_events/{eventId}")
    .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) {
        return;
    }
    const kind = data.kind;
    if (kind !== gameplayEventResolver_1.KIND_REGION_FOUND && kind !== progressionCore_1.KIND_GAME_ENDED) {
        return;
    }
    const sessionId = context.params.sessionId;
    const eventId = context.params.eventId;
    const sessionRef = db.collection("trip_sessions").doc(sessionId);
    const payload = data.payload;
    const [membersSnap, gamesSnap, eventsSnap] = await Promise.all([
        sessionRef.collection("members").get(),
        sessionRef.collection("games").get(),
        sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);
    const memberUserIds = membersSnap.docs.map((d) => d.id).sort();
    const deltasByUser = (0, progressionCore_1.previewProgressionDeltasForActivityEvent)({
        kind,
        actorId: data.actorId,
        payload,
        memberUserIds,
        gameDocs: gamesSnap.docs,
        activityEventDocs: eventsSnap.docs,
    });
    const deltaKeys = Object.keys(deltasByUser).sort();
    const uids = deltaKeys.filter((uid) => memberUserIds.includes(uid));
    if (uids.length === 0) {
        return;
    }
    await Promise.all(uids.map((uid) => db.runTransaction(async (tx) => {
        const ref = db.collection("user_progression").doc(uid);
        const doc = await tx.get(ref);
        const docData = doc.data() || {};
        const applied = getMergedStringKeyMap(docData, "appliedProgressionEvents");
        if (applied && applied[eventId] != null) {
            return;
        }
        const scopeKey = kind === gameplayEventResolver_1.KIND_REGION_FOUND
            ? (0, progressionCore_1.baseRegionDiscoveryScopeKey)({ userId: uid, sessionId, payload })
            : null;
        const scopesMap = getMergedStringKeyMap(docData, "appliedProgressionScopes");
        const isScopedAlreadyApplied = !!(scopeKey && scopesMap && scopesMap[scopeKey] != null);
        const d = deltasByUser[uid];
        if (!d && !isScopedAlreadyApplied) {
            return;
        }
        const update = {
            schemaVersion: 1,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            appliedProgressionEvents: {
                [eventId]: admin.firestore.FieldValue.serverTimestamp(),
            },
        };
        if (scopeKey) {
            update.appliedProgressionScopes = {
                [scopeKey]: admin.firestore.FieldValue.serverTimestamp(),
            };
        }
        if (isScopedAlreadyApplied) {
            tx.set(ref, update, { merge: true });
            return;
        }
        if (d && d.totalXp !== 0) {
            update.totalXp = admin.firestore.FieldValue.increment(d.totalXp);
        }
        if (d && d.acceptedRegionFindCount !== 0) {
            update.acceptedRegionFindCount = admin.firestore.FieldValue.increment(d.acceptedRegionFindCount);
        }
        if (d && d.competitiveFirstPlaceFinishes !== 0) {
            update.competitiveFirstPlaceFinishes = admin.firestore.FieldValue.increment(d.competitiveFirstPlaceFinishes);
        }
        if (d && d.awardEverCompetitiveFirstPlace) {
            update.everCompetitiveFirstPlace = true;
        }
        tx.set(ref, update, { merge: true });
    })));
});
//# sourceMappingURL=progressionOnActivityEvent.js.map