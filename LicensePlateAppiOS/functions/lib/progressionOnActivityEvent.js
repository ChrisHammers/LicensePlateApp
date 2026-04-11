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
    const [membersSnap, gamesSnap, eventsSnap] = await Promise.all([
        sessionRef.collection("members").get(),
        sessionRef.collection("games").get(),
        sessionRef.collection("activity_events").orderBy("timestamp", "asc").get(),
    ]);
    const memberUserIds = membersSnap.docs.map((d) => d.id).sort();
    const deltasByUser = (0, progressionCore_1.previewProgressionDeltasForActivityEvent)({
        kind,
        actorId: data.actorId,
        payload: data.payload,
        memberUserIds,
        gameDocs: gamesSnap.docs,
        activityEventDocs: eventsSnap.docs,
    });
    const uids = Object.keys(deltasByUser).filter((uid) => memberUserIds.includes(uid));
    if (uids.length === 0) {
        return;
    }
    await Promise.all(uids.map((uid) => db.runTransaction(async (tx) => {
        var _a;
        const ref = db.collection("user_progression").doc(uid);
        const doc = await tx.get(ref);
        const applied = (_a = doc.data()) === null || _a === void 0 ? void 0 : _a.appliedProgressionEvents;
        if (applied && applied[eventId] != null) {
            return;
        }
        const d = deltasByUser[uid];
        if (!d) {
            return;
        }
        const appliedPath = `appliedProgressionEvents.${eventId}`;
        const update = {
            [appliedPath]: admin.firestore.FieldValue.serverTimestamp(),
            schemaVersion: 1,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (d.totalXp !== 0) {
            update.totalXp = admin.firestore.FieldValue.increment(d.totalXp);
        }
        if (d.acceptedRegionFindCount !== 0) {
            update.acceptedRegionFindCount = admin.firestore.FieldValue.increment(d.acceptedRegionFindCount);
        }
        if (d.competitiveFirstPlaceFinishes !== 0) {
            update.competitiveFirstPlaceFinishes = admin.firestore.FieldValue.increment(d.competitiveFirstPlaceFinishes);
        }
        if (d.awardEverCompetitiveFirstPlace) {
            update.everCompetitiveFirstPlace = true;
        }
        tx.set(ref, update, { merge: true });
    })));
});
//# sourceMappingURL=progressionOnActivityEvent.js.map