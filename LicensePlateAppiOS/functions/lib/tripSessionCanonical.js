"use strict";
/**
 * Trip session canonical sync — server-authoritative writes (Step 12.5).
 * Clients read games/activity_events when trip_sessions member; all writes via these callables.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.markTripCancelledRemote = exports.fetchTripBootstrapForMember = exports.updateFairnessAckWatermark = exports.appendTripActivityEvent = exports.publishTripCanonicalState = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const audit_1 = require("./audit");
const gameplayEventResolver_1 = require("./gameplayEventResolver");
const fairnessWatermarkMerge_1 = require("./fairnessWatermarkMerge");
const db = admin.firestore();
const MAX_BOOTSTRAP_EVENTS = 2500;
function tsToSeconds(value) {
    if (!value) {
        return 0;
    }
    return value.seconds + value.nanoseconds / 1e9;
}
function secondsToTimestamp(sec) {
    if (sec == null || typeof sec !== "number" || Number.isNaN(sec)) {
        return null;
    }
    return admin.firestore.Timestamp.fromMillis(Math.round(sec * 1000));
}
function sessionRef(sessionId) {
    return db.collection("trip_sessions").doc(sessionId);
}
async function assertTripMember(sessionId, userId) {
    const memberRef = sessionRef(sessionId).collection("members").doc(userId);
    const snap = await memberRef.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a member of this trip session");
    }
}
async function assertTripOwner(sessionId, userId) {
    var _a;
    const memberRef = sessionRef(sessionId).collection("members").doc(userId);
    const snap = await memberRef.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("permission-denied", "Not a member of this trip session");
    }
    const role = ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.role) || "member";
    if (role !== "owner") {
        throw new functions.https.HttpsError("permission-denied", "Only the trip owner can publish canonical state");
    }
}
function gameDocToWire(id, d) {
    var _a, _b, _c, _d, _e, _f;
    return {
        id,
        definitionId: d.definitionId,
        sessionId: d.sessionId,
        startedAt: tsToSeconds(d.startedAt),
        endedAt: d.endedAt ? tsToSeconds(d.endedAt) : null,
        ruleSetDataBase64: (_a = d.ruleSetDataBase64) !== null && _a !== void 0 ? _a : null,
        commonConfigDataBase64: (_b = d.commonConfigDataBase64) !== null && _b !== void 0 ? _b : null,
        gameSpecificPayloadType: (_c = d.gameSpecificPayloadType) !== null && _c !== void 0 ? _c : null,
        gameSpecificPayloadVersion: (_d = d.gameSpecificPayloadVersion) !== null && _d !== void 0 ? _d : null,
        gameSpecificPayloadDataBase64: (_e = d.gameSpecificPayloadDataBase64) !== null && _e !== void 0 ? _e : null,
        teamsDataBase64: (_f = d.teamsDataBase64) !== null && _f !== void 0 ? _f : null,
    };
}
function eventDocToWire(id, d) {
    var _a, _b;
    return {
        id,
        sessionId: d.sessionId,
        kind: d.kind,
        timestamp: tsToSeconds(d.timestamp),
        actorId: (_a = d.actorId) !== null && _a !== void 0 ? _a : null,
        payload: (_b = d.payload) !== null && _b !== void 0 ? _b : null,
    };
}
/**
 * Publish full session + games snapshot (owner only).
 */
exports.publishTripCanonicalState = functions.https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const tripSessionId = data === null || data === void 0 ? void 0 : data.tripSessionId;
    const session = data === null || data === void 0 ? void 0 : data.session;
    const games = data === null || data === void 0 ? void 0 : data.games;
    if (!tripSessionId || typeof tripSessionId !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
    }
    if (!session || typeof session !== "object") {
        throw new functions.https.HttpsError("invalid-argument", "session is required");
    }
    if (!Array.isArray(games)) {
        throw new functions.https.HttpsError("invalid-argument", "games array is required");
    }
    const sessionIdFromPayload = session.id;
    if (sessionIdFromPayload !== tripSessionId) {
        throw new functions.https.HttpsError("invalid-argument", "session.id must match tripSessionId");
    }
    await assertTripOwner(tripSessionId, userId);
    const ref = sessionRef(tripSessionId);
    const gamesCol = ref.collection("games");
    const existingGames = await gamesCol.get();
    const incomingIds = new Set(games.map((g) => String(g.id)));
    let batch = db.batch();
    let ops = 0;
    const commitIfNeeded = async () => {
        if (ops >= 400) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
        }
    };
    for (const doc of existingGames.docs) {
        if (!incomingIds.has(doc.id)) {
            batch.delete(doc.ref);
            ops += 1;
            await commitIfNeeded();
        }
    }
    const canonicalCreatedAt = secondsToTimestamp(session.createdAt);
    if (!canonicalCreatedAt) {
        throw new functions.https.HttpsError("invalid-argument", "session.createdAt is required");
    }
    const canonicalStartedAt = secondsToTimestamp(session.startedAt);
    const canonicalEndedAt = secondsToTimestamp(session.endedAt);
    batch.set(ref, {
        name: session.name,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        syncVersion: admin.firestore.FieldValue.increment(1),
        canonicalStatus: session.status,
        canonicalCreatedAt,
        canonicalStartedAt,
        canonicalEndedAt,
        canonicalEndedBy: (_a = session.endedBy) !== null && _a !== void 0 ? _a : null,
        canonicalParticipants: Array.isArray(session.participants) ? session.participants : [],
    }, { merge: true });
    ops += 1;
    await commitIfNeeded();
    for (const g of games) {
        const gid = String(g.id);
        const gameRef = gamesCol.doc(gid);
        const startedAt = secondsToTimestamp(g.startedAt);
        if (!startedAt) {
            throw new functions.https.HttpsError("invalid-argument", "each game.startedAt is required");
        }
        const endedAt = secondsToTimestamp(g.endedAt);
        batch.set(gameRef, {
            definitionId: g.definitionId,
            sessionId: g.sessionId,
            startedAt,
            endedAt,
            ruleSetDataBase64: (_b = g.ruleSetDataBase64) !== null && _b !== void 0 ? _b : null,
            commonConfigDataBase64: (_c = g.commonConfigDataBase64) !== null && _c !== void 0 ? _c : null,
            gameSpecificPayloadType: (_d = g.gameSpecificPayloadType) !== null && _d !== void 0 ? _d : null,
            gameSpecificPayloadVersion: (_e = g.gameSpecificPayloadVersion) !== null && _e !== void 0 ? _e : null,
            gameSpecificPayloadDataBase64: (_f = g.gameSpecificPayloadDataBase64) !== null && _f !== void 0 ? _f : null,
            teamsDataBase64: (_g = g.teamsDataBase64) !== null && _g !== void 0 ? _g : null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        ops += 1;
        await commitIfNeeded();
    }
    if (ops > 0) {
        await batch.commit();
    }
    const parent = await ref.get();
    const syncVersion = (_j = (_h = parent.data()) === null || _h === void 0 ? void 0 : _h.syncVersion) !== null && _j !== void 0 ? _j : 0;
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_TRIP_CANONICAL_PUBLISHED",
        actorId: userId,
        subjectType: "trip_session",
        subjectId: tripSessionId,
        metadata: { gameCount: games.length, syncVersion },
    });
    return { success: true, syncVersion };
});
/**
 * Append one activity event (idempotent set). Any trip member may call.
 */
exports.appendTripActivityEvent = functions.https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const tripSessionId = data === null || data === void 0 ? void 0 : data.tripSessionId;
    const event = data === null || data === void 0 ? void 0 : data.event;
    if (!tripSessionId) {
        throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
    }
    if (!event || typeof event !== "object") {
        throw new functions.https.HttpsError("invalid-argument", "event is required");
    }
    await assertTripMember(tripSessionId, userId);
    const eventId = event.id;
    const sessionIdInEvent = event.sessionId;
    if (!eventId || !sessionIdInEvent) {
        throw new functions.https.HttpsError("invalid-argument", "event.id and event.sessionId required");
    }
    if (sessionIdInEvent !== tripSessionId) {
        throw new functions.https.HttpsError("invalid-argument", "event.sessionId must match tripSessionId");
    }
    const kind = event.kind;
    if (!kind) {
        throw new functions.https.HttpsError("invalid-argument", "event.kind is required");
    }
    const ts = secondsToTimestamp(event.timestamp);
    if (!ts) {
        throw new functions.https.HttpsError("invalid-argument", "event.timestamp is required");
    }
    const wire = {
        id: eventId,
        sessionId: sessionIdInEvent,
        kind,
        timestamp: event.timestamp,
        actorId: (_a = event.actorId) !== null && _a !== void 0 ? _a : null,
        payload: (_b = event.payload) !== null && _b !== void 0 ? _b : null,
    };
    const result = await (0, gameplayEventResolver_1.resolveGameplayAppendTransaction)(db, tripSessionId, userId, wire);
    return {
        success: true,
        resolution: result.resolution,
        appliedEventId: result.appliedEventId,
        rejectionEvent: result.rejectionEvent,
    };
});
/**
 * Per-user fairness UI watermark (Step 13.2): max lastAckAt in Unix seconds.
 * Stored under games/{gameId}/fairness_ack_watermarks/{userId} so publishTripCanonicalState does not clobber it.
 */
exports.updateFairnessAckWatermark = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const tripSessionId = data === null || data === void 0 ? void 0 : data.tripSessionId;
    const gameInstanceId = data === null || data === void 0 ? void 0 : data.gameInstanceId;
    const lastAckAtSeconds = data === null || data === void 0 ? void 0 : data.lastAckAtSeconds;
    if (!tripSessionId || !gameInstanceId) {
        throw new functions.https.HttpsError("invalid-argument", "tripSessionId and gameInstanceId are required");
    }
    if (lastAckAtSeconds == null || typeof lastAckAtSeconds !== "number" || Number.isNaN(lastAckAtSeconds)) {
        throw new functions.https.HttpsError("invalid-argument", "lastAckAtSeconds is required");
    }
    await assertTripMember(tripSessionId, userId);
    const ref = sessionRef(tripSessionId)
        .collection("games")
        .doc(gameInstanceId)
        .collection("fairness_ack_watermarks")
        .doc(userId);
    const mergedSeconds = await db.runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        const existingTs = snap.exists ? (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.lastAckAt : undefined;
        const existingSec = existingTs ? tsToSeconds(existingTs) : 0;
        const next = (0, fairnessWatermarkMerge_1.mergeFairnessAckSeconds)(existingSec, lastAckAtSeconds);
        tx.set(ref, {
            lastAckAt: secondsToTimestamp(next),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return next;
    });
    return { success: true, lastAckAtSeconds: mergedSeconds };
});
/**
 * Full read for a member: session wire + games + events (capped).
 */
exports.fetchTripBootstrapForMember = functions.https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const tripSessionId = data === null || data === void 0 ? void 0 : data.tripSessionId;
    if (!tripSessionId) {
        throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
    }
    await assertTripMember(tripSessionId, userId);
    const ref = sessionRef(tripSessionId);
    const parentSnap = await ref.get();
    if (!parentSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Trip session not found");
    }
    const p = parentSnap.data();
    const sessionWire = {
        id: tripSessionId,
        name: (_a = p.name) !== null && _a !== void 0 ? _a : "",
        status: (_b = p.canonicalStatus) !== null && _b !== void 0 ? _b : "created",
        createdAt: tsToSeconds(p.canonicalCreatedAt),
        createdBy: (_c = p.createdBy) !== null && _c !== void 0 ? _c : null,
        startedAt: p.canonicalStartedAt ? tsToSeconds(p.canonicalStartedAt) : null,
        endedAt: p.canonicalEndedAt ? tsToSeconds(p.canonicalEndedAt) : null,
        endedBy: (_d = p.canonicalEndedBy) !== null && _d !== void 0 ? _d : null,
        participants: Array.isArray(p.canonicalParticipants) ? p.canonicalParticipants : [],
    };
    const gamesSnap = await ref.collection("games").get();
    const games = gamesSnap.docs.map((doc) => gameDocToWire(doc.id, doc.data()));
    const eventsQ = await ref
        .collection("activity_events")
        .orderBy("timestamp", "asc")
        .limit(MAX_BOOTSTRAP_EVENTS + 1)
        .get();
    let nextEventCursor = null;
    const eventDocs = eventsQ.docs;
    const limited = eventDocs.length > MAX_BOOTSTRAP_EVENTS ? eventDocs.slice(0, MAX_BOOTSTRAP_EVENTS) : eventDocs;
    if (eventDocs.length > MAX_BOOTSTRAP_EVENTS) {
        nextEventCursor = limited[limited.length - 1].id;
    }
    const events = limited.map((doc) => eventDocToWire(doc.id, doc.data()));
    const syncVersion = (_e = p.syncVersion) !== null && _e !== void 0 ? _e : 0;
    return {
        session: sessionWire,
        games,
        events,
        syncVersion,
        nextEventCursor,
    };
});
/** Owner: mark remote cancelled and remove games/events for joiner convergence. */
exports.markTripCancelledRemote = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const tripSessionId = data === null || data === void 0 ? void 0 : data.tripSessionId;
    if (!tripSessionId) {
        throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
    }
    await assertTripOwner(tripSessionId, userId);
    const ref = sessionRef(tripSessionId);
    const deleteInBatches = async (coll) => {
        // eslint-disable-next-line no-constant-condition
        while (true) {
            const snap = await coll.limit(400).get();
            if (snap.empty) {
                break;
            }
            let b = db.batch();
            let c = 0;
            for (const doc of snap.docs) {
                b.delete(doc.ref);
                c += 1;
                if (c >= 400) {
                    await b.commit();
                    b = db.batch();
                    c = 0;
                }
            }
            if (c > 0) {
                await b.commit();
            }
        }
    };
    await deleteInBatches(ref.collection("games"));
    await deleteInBatches(ref.collection("activity_events"));
    await ref.set({
        canonicalStatus: "cancelled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        syncVersion: admin.firestore.FieldValue.increment(1),
    }, { merge: true });
    await (0, audit_1.writeAuditLog)({
        eventType: "AUDIT_TRIP_CANCELLED_REMOTE",
        actorId: userId,
        subjectType: "trip_session",
        subjectId: tripSessionId,
        metadata: {},
    });
    return { success: true };
});
//# sourceMappingURL=tripSessionCanonical.js.map