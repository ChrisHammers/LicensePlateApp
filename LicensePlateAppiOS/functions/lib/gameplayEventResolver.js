"use strict";
/**
 * Step 13 — Server-side validation for score-sensitive TripActivityEvents.
 * Parity with DiscoveryRulesEngine + TripActivityEventDiscoveryReplay (Swift).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.KIND_REGION_REMOVED = exports.KIND_REGION_FOUND = exports.PK = void 0;
exports.replayDiscoveriesFromDocs = replayDiscoveriesFromDocs;
exports.evaluateDiscoverySubmission = evaluateDiscoverySubmission;
exports.resolveGameplayAppendTransaction = resolveGameplayAppendTransaction;
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const MAX_EVENTS_POLICY = 2500;
exports.PK = {
    regionId: "regionId",
    gameInstanceId: "gameInstanceId",
    participantId: "participantId",
    inputMethod: "inputMethod",
    rejectionReason: "rejectionReason",
    removedDiscoveryEventId: "removedDiscoveryEventId",
    clientAttemptEventId: "clientAttemptEventId",
    firstFinderParticipantId: "firstFinderParticipantId",
    firstFinderDiscoveredAt: "firstFinderDiscoveredAt",
    firstFinderEventId: "firstFinderEventId",
    serverResolvedAt: "serverResolvedAt",
    clientClaimedAt: "clientClaimedAt",
    gameMode: "gameMode",
    participantCount: "participantCount",
};
exports.KIND_REGION_FOUND = "region_found";
exports.KIND_REGION_REMOVED = "region_removed";
const KIND_DISCOVERY_REJECTED = "discovery_rejected";
const REJECTION_SERVER_LATE_COMPETITIVE = "server_rejected_late_competitive";
const REJECTION_INVALID_PARTICIPANT = "rejected_invalid_participant";
function sessionRef(db, sessionId) {
    return db.collection("trip_sessions").doc(sessionId);
}
function tsToSeconds(value) {
    if (!value)
        return 0;
    return value.seconds + value.nanoseconds / 1e9;
}
function secondsToTimestamp(sec) {
    return admin.firestore.Timestamp.fromMillis(Math.round(sec * 1000));
}
function stringifyPayload(p) {
    const out = {};
    if (!p || typeof p !== "object")
        return out;
    for (const [k, v] of Object.entries(p)) {
        if (v === null || v === undefined)
            continue;
        out[k] = typeof v === "string" ? v : String(v);
    }
    return out;
}
function bucketKey(gameInstanceId, regionId) {
    return `${gameInstanceId}|${regionId}`;
}
function compareDiscovery(a, b) {
    const as = a.discoveredAt.seconds + a.discoveredAt.nanoseconds / 1e9;
    const bs = b.discoveredAt.seconds + b.discoveredAt.nanoseconds / 1e9;
    if (as !== bs)
        return as - bs;
    if (a.targetId !== b.targetId)
        return a.targetId < b.targetId ? -1 : 1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}
/**
 * Replay region_found / region_removed into active discoveries (Swift parity).
 */
function replayDiscoveriesFromDocs(docs, gameInstanceFilter) {
    const buckets = new Map();
    const rows = docs
        .map((d) => {
        const data = d.data();
        const kind = data.kind;
        if (kind !== exports.KIND_REGION_FOUND && kind !== exports.KIND_REGION_REMOVED)
            return null;
        const ts = data.timestamp;
        if (!ts)
            return null;
        const payload = stringifyPayload(data.payload);
        const regionId = payload[exports.PK.regionId];
        if (!regionId)
            return null;
        let gid = payload[exports.PK.gameInstanceId];
        if (!gid && gameInstanceFilter)
            gid = gameInstanceFilter;
        if (!gid)
            return null;
        if (gameInstanceFilter && gid !== gameInstanceFilter)
            return null;
        return {
            docId: d.id,
            kind,
            timestamp: ts,
            actorId: data.actorId || undefined,
            payload,
            gameInstanceId: gid,
            regionId,
        };
    })
        .filter((x) => x !== null)
        .sort((a, b) => {
        const as = a.timestamp.seconds + a.timestamp.nanoseconds / 1e9;
        const bs = b.timestamp.seconds + b.timestamp.nanoseconds / 1e9;
        return as - bs;
    });
    for (const row of rows) {
        const key = bucketKey(row.gameInstanceId, row.regionId);
        if (row.kind === exports.KIND_REGION_FOUND) {
            const participantId = row.payload[exports.PK.participantId] || row.actorId || "";
            const inputMethod = row.payload[exports.PK.inputMethod] || "list";
            const list = buckets.get(key) || [];
            list.push({
                id: row.docId,
                gameInstanceId: row.gameInstanceId,
                participantId,
                targetId: row.regionId,
                discoveredAt: row.timestamp,
                inputMethod,
            });
            buckets.set(key, list);
        }
        else {
            const removedId = row.payload[exports.PK.removedDiscoveryEventId];
            if (removedId) {
                const list = buckets.get(key);
                if (list) {
                    const idx = list.findIndex((x) => x.id === removedId);
                    if (idx >= 0) {
                        list.splice(idx, 1);
                        if (list.length === 0)
                            buckets.delete(key);
                        else
                            buckets.set(key, list);
                    }
                }
            }
            else {
                buckets.delete(key);
            }
        }
    }
    return buckets;
}
function tripModeFromRoster(participants) {
    const ids = new Set();
    for (const p of participants) {
        if (p && typeof p === "object" && "userId" in p) {
            const uid = String(p.userId);
            if (uid)
                ids.add(uid);
        }
    }
    return ids.size > 1 ? "multiplayer" : "solo";
}
function rosterHasUser(participants, userId) {
    for (const p of participants) {
        if (p && typeof p === "object" && "userId" in p && String(p.userId) === userId) {
            return true;
        }
    }
    return false;
}
/** Exported for unit tests (parity with Swift DiscoveryRulesEngine). */
function evaluateDiscoverySubmission(gameMode, tripMode, existingForTarget, candidateParticipantId) {
    if (existingForTarget.length === 0)
        return "new_credit";
    const same = existingForTarget.some((d) => d.participantId === candidateParticipantId);
    if (same)
        return "personal_duplicate";
    if (tripMode === "solo")
        return "rejected_invalid_participant";
    if (gameMode === "competitive")
        return "rejected_duplicate";
    return "shared_duplicate";
}
function canParticipantUnfind(mode, userId, discovery, allForTarget) {
    if (mode === "collaborative") {
        return allForTarget.some((d) => d.participantId === userId);
    }
    return discovery.participantId === userId;
}
function parseCommonConfig(commonConfigDataBase64) {
    if (!commonConfigDataBase64) {
        throw new Error("missing_common_config");
    }
    const json = Buffer.from(commonConfigDataBase64, "base64").toString("utf8");
    const o = JSON.parse(json);
    return {
        gameMode: o.gameMode === "competitive" ? "competitive" : "collaborative",
        lifecycleState: o.lifecycleState || "created",
    };
}
function eventWireFromDoc(id, sessionId, data) {
    var _a, _b;
    return {
        id,
        sessionId: data.sessionId,
        kind: data.kind,
        timestamp: tsToSeconds(data.timestamp),
        actorId: (_a = data.actorId) !== null && _a !== void 0 ? _a : null,
        payload: (_b = data.payload) !== null && _b !== void 0 ? _b : null,
    };
}
function payloadsEqualStringMap(a, b) {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
        if ((a[k] || "") !== (b[k] || ""))
            return false;
    }
    return true;
}
function serverRejectionDocId(clientEventId) {
    return `srvrej_${clientEventId}`;
}
/**
 * Runs resolver inside a Firestore transaction; performs writes and returns callable result.
 */
async function resolveGameplayAppendTransaction(db, tripSessionId, userId, event) {
    const ref = sessionRef(db, tripSessionId);
    const eventRef = ref.collection("activity_events").doc(event.id);
    const kind = event.kind;
    return db.runTransaction(async (tx) => {
        const sessionSnap = await tx.get(ref);
        if (!sessionSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Trip session not found");
        }
        const sessionData = sessionSnap.data();
        const participants = Array.isArray(sessionData.canonicalParticipants) ? sessionData.canonicalParticipants : [];
        if (!rosterHasUser(participants, userId)) {
            throw new functions.https.HttpsError("permission-denied", "Not a member of this trip session");
        }
        const tripMode = tripModeFromRoster(participants);
        const existingEventSnap = await tx.get(eventRef);
        const incomingTs = secondsToTimestamp(event.timestamp);
        const incomingPayload = stringifyPayload(event.payload || undefined);
        const normalizedActor = userId;
        if (existingEventSnap.exists) {
            const ed = existingEventSnap.data();
            const sameKind = ed.kind === kind;
            const sameSession = ed.sessionId === tripSessionId;
            const existingPayload = stringifyPayload(ed.payload);
            const exSec = ed.timestamp ? tsToSeconds(ed.timestamp) : -1;
            const tsEq = Math.abs(exSec - event.timestamp) < 0.001;
            if (sameKind && sameSession && tsEq && payloadsEqualStringMap(incomingPayload, existingPayload)) {
                return { success: true, resolution: "accepted", appliedEventId: event.id };
            }
            if (sameKind && sameSession) {
                throw new functions.https.HttpsError("already-exists", "event id collision");
            }
        }
        const eventsQuery = ref.collection("activity_events").orderBy("timestamp", "asc").limit(MAX_EVENTS_POLICY);
        const eventsSnap = await tx.get(eventsQuery);
        const eventDocs = eventsSnap.docs;
        const normalizeAndWrite = (payload) => {
            tx.set(eventRef, {
                sessionId: tripSessionId,
                kind,
                timestamp: incomingTs,
                actorId: normalizedActor,
                payload,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            tx.update(ref, { updatedAt: admin.firestore.FieldValue.serverTimestamp() });
        };
        if (kind === exports.KIND_REGION_FOUND) {
            const gameInstanceId = incomingPayload[exports.PK.gameInstanceId];
            const regionId = incomingPayload[exports.PK.regionId];
            const participantId = incomingPayload[exports.PK.participantId] || "";
            if (!gameInstanceId || !regionId) {
                throw new functions.https.HttpsError("invalid-argument", "gameInstanceId and regionId required");
            }
            if (participantId !== userId) {
                throw new functions.https.HttpsError("permission-denied", "participantId must match caller");
            }
            const gameRef = ref.collection("games").doc(gameInstanceId);
            const gameSnap = await tx.get(gameRef);
            if (!gameSnap.exists) {
                throw new functions.https.HttpsError("failed-precondition", "game not found");
            }
            const gameData = gameSnap.data();
            let cfg;
            try {
                cfg = parseCommonConfig(gameData.commonConfigDataBase64);
            }
            catch (_a) {
                throw new functions.https.HttpsError("failed-precondition", "invalid game config");
            }
            if (cfg.lifecycleState !== "started") {
                throw new functions.https.HttpsError("failed-precondition", "game not started");
            }
            const gameMode = cfg.gameMode;
            const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
            const key = bucketKey(gameInstanceId, regionId);
            const existingForTarget = buckets.get(key) || [];
            const outcome = evaluateDiscoverySubmission(gameMode, tripMode, existingForTarget, userId);
            if (outcome === "rejected_duplicate" || outcome === "rejected_invalid_participant") {
                const rejId = serverRejectionDocId(event.id);
                const rejRef = ref.collection("activity_events").doc(rejId);
                const existingRej = await tx.get(rejRef);
                if (existingRej.exists) {
                    const wire = eventWireFromDoc(rejId, tripSessionId, existingRej.data());
                    return { success: true, resolution: "superseded", rejectionEvent: wire };
                }
                const sorted = [...existingForTarget].sort(compareDiscovery);
                const first = sorted[0];
                const nowTs = admin.firestore.Timestamp.now();
                const nowSec = nowTs.seconds;
                const reason = outcome === "rejected_duplicate" ? REJECTION_SERVER_LATE_COMPETITIVE : REJECTION_INVALID_PARTICIPANT;
                const rejPayload = {
                    [exports.PK.regionId]: regionId,
                    [exports.PK.gameInstanceId]: gameInstanceId,
                    [exports.PK.participantId]: userId,
                    [exports.PK.clientAttemptEventId]: event.id,
                    [exports.PK.rejectionReason]: reason,
                    [exports.PK.clientClaimedAt]: String(Math.floor(event.timestamp)),
                    [exports.PK.serverResolvedAt]: String(nowSec),
                };
                if (first) {
                    rejPayload[exports.PK.firstFinderParticipantId] = first.participantId;
                    rejPayload[exports.PK.firstFinderDiscoveredAt] = String(tsToSeconds(first.discoveredAt));
                    rejPayload[exports.PK.firstFinderEventId] = first.id;
                }
                if (incomingPayload[exports.PK.inputMethod]) {
                    rejPayload[exports.PK.inputMethod] = incomingPayload[exports.PK.inputMethod];
                }
                rejPayload[exports.PK.gameMode] = gameMode;
                rejPayload[exports.PK.participantCount] = String(participants.length);
                tx.set(rejRef, {
                    sessionId: tripSessionId,
                    kind: KIND_DISCOVERY_REJECTED,
                    timestamp: nowTs,
                    actorId: userId,
                    payload: rejPayload,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                tx.update(ref, { updatedAt: admin.firestore.FieldValue.serverTimestamp() });
                const wire = eventWireFromDoc(rejId, tripSessionId, {
                    sessionId: tripSessionId,
                    kind: KIND_DISCOVERY_REJECTED,
                    timestamp: nowTs,
                    actorId: userId,
                    payload: rejPayload,
                });
                return { success: true, resolution: "superseded", rejectionEvent: wire };
            }
            normalizeAndWrite(Object.assign(Object.assign({}, incomingPayload), { [exports.PK.participantId]: userId }));
            return { success: true, resolution: "accepted", appliedEventId: event.id };
        }
        if (kind === exports.KIND_REGION_REMOVED) {
            const gameInstanceId = incomingPayload[exports.PK.gameInstanceId];
            const regionId = incomingPayload[exports.PK.regionId];
            if (!gameInstanceId || !regionId) {
                throw new functions.https.HttpsError("invalid-argument", "gameInstanceId and regionId required");
            }
            const gameRef = ref.collection("games").doc(gameInstanceId);
            const gameSnap = await tx.get(gameRef);
            if (!gameSnap.exists) {
                throw new functions.https.HttpsError("failed-precondition", "game not found");
            }
            let cfg;
            try {
                cfg = parseCommonConfig(gameSnap.data().commonConfigDataBase64);
            }
            catch (_b) {
                throw new functions.https.HttpsError("failed-precondition", "invalid game config");
            }
            const gameMode = cfg.gameMode;
            const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
            const key = bucketKey(gameInstanceId, regionId);
            const forTarget = buckets.get(key) || [];
            const removedDiscoveryEventId = incomingPayload[exports.PK.removedDiscoveryEventId];
            if (removedDiscoveryEventId) {
                const discovery = forTarget.find((d) => d.id === removedDiscoveryEventId);
                if (!discovery) {
                    throw new functions.https.HttpsError("failed-precondition", "discovery not found for removal");
                }
                if (!canParticipantUnfind(gameMode, userId, discovery, forTarget)) {
                    throw new functions.https.HttpsError("permission-denied", "cannot remove this find");
                }
            }
            else {
                if (forTarget.length === 0) {
                    throw new functions.https.HttpsError("failed-precondition", "no finds to remove");
                }
                if (gameMode === "competitive") {
                    if (forTarget.length !== 1 || forTarget[0].participantId !== userId) {
                        throw new functions.https.HttpsError("permission-denied", "legacy unfind not allowed");
                    }
                }
                else {
                    if (!forTarget.some((d) => d.participantId === userId)) {
                        throw new functions.https.HttpsError("permission-denied", "cannot clear finds for this region");
                    }
                }
            }
            normalizeAndWrite(incomingPayload);
            return { success: true, resolution: "accepted", appliedEventId: event.id };
        }
        if (kind === KIND_DISCOVERY_REJECTED) {
            const gameInstanceId = incomingPayload[exports.PK.gameInstanceId];
            if (!gameInstanceId) {
                throw new functions.https.HttpsError("invalid-argument", "gameInstanceId required");
            }
            const gameSnap = await tx.get(ref.collection("games").doc(gameInstanceId));
            if (!gameSnap.exists) {
                throw new functions.https.HttpsError("failed-precondition", "game not found");
            }
            const pid = incomingPayload[exports.PK.participantId] || "";
            if (pid !== userId) {
                throw new functions.https.HttpsError("permission-denied", "participantId must match caller");
            }
            const reason = incomingPayload[exports.PK.rejectionReason] || "";
            if (!reason) {
                throw new functions.https.HttpsError("invalid-argument", "rejectionReason required");
            }
            if (reason === "rejected_duplicate") {
                const rid = incomingPayload[exports.PK.regionId];
                if (!rid) {
                    throw new functions.https.HttpsError("invalid-argument", "regionId required");
                }
                const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
                const key = bucketKey(gameInstanceId, rid);
                const forTarget = buckets.get(key) || [];
                const others = forTarget.filter((d) => d.participantId !== userId);
                if (others.length === 0) {
                    throw new functions.https.HttpsError("failed-precondition", "rejection inconsistent with server state");
                }
            }
            normalizeAndWrite(incomingPayload);
            return { success: true, resolution: "passthrough", appliedEventId: event.id };
        }
        normalizeAndWrite(incomingPayload);
        return { success: true, resolution: "passthrough", appliedEventId: event.id };
    });
}
//# sourceMappingURL=gameplayEventResolver.js.map