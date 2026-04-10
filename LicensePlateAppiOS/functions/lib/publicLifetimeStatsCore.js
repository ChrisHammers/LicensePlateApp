"use strict";
/**
 * Pure aggregation for public lifetime stats (Swift parity: TripSummaryBuilder + ParticipantContributionBuilder + family-only rule).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.KIND_TRIP_ENDED = void 0;
exports.parseCommonConfigGameMode = parseCommonConfigGameMode;
exports.parseTeamsDataBase64 = parseTeamsDataBase64;
exports.isFamilyOnlyTrip = isFamilyOnlyTrip;
exports.previewTripEndedAggregates = previewTripEndedAggregates;
const gameplayEventResolver_1 = require("./gameplayEventResolver");
exports.KIND_TRIP_ENDED = "trip_ended";
function parseCommonConfigGameMode(commonConfigDataBase64) {
    if (!commonConfigDataBase64) {
        return "collaborative";
    }
    try {
        const json = Buffer.from(commonConfigDataBase64, "base64").toString("utf8");
        const o = JSON.parse(json);
        return o.gameMode === "competitive" ? "competitive" : "collaborative";
    }
    catch (_a) {
        return "collaborative";
    }
}
function parseTeamsDataBase64(teamsDataBase64) {
    if (!teamsDataBase64)
        return [];
    try {
        const json = Buffer.from(teamsDataBase64, "base64").toString("utf8");
        const arr = JSON.parse(json);
        if (!Array.isArray(arr))
            return [];
        return arr.filter((t) => t && typeof t.id === "string" && Array.isArray(t.participantUserIds));
    }
    catch (_a) {
        return [];
    }
}
function discoveryOrderingAscending(a, b) {
    const as = a.discoveredAt.seconds + a.discoveredAt.nanoseconds / 1e9;
    const bs = b.discoveredAt.seconds + b.discoveredAt.nanoseconds / 1e9;
    if (as !== bs)
        return as - bs;
    const aSrv = a.serverCommittedAtSec > 0 ? a.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
    const bSrv = b.serverCommittedAtSec > 0 ? b.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
    if (aSrv !== bSrv)
        return aSrv - bSrv;
    if (a.targetId !== b.targetId)
        return a.targetId < b.targetId ? -1 : 1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}
function teamIdFor(participantId, teams) {
    var _a;
    if (!teams.length)
        return null;
    const t = teams.find((x) => x.participantUserIds.includes(participantId));
    return (_a = t === null || t === void 0 ? void 0 : t.id) !== null && _a !== void 0 ? _a : null;
}
function calcCredits(mode, discovery, existingForTarget, teams) {
    if (mode === "collaborative") {
        const allFinderIds = new Set(existingForTarget.map((d) => d.participantId));
        allFinderIds.add(discovery.participantId);
        const count = allFinderIds.size;
        const weight = count > 0 ? 1.0 / count : 1.0;
        return [...allFinderIds].map((participantId) => ({
            discoveryId: discovery.id,
            participantId,
            weight,
            teamId: teamIdFor(participantId, teams),
        }));
    }
    return [
        {
            discoveryId: discovery.id,
            participantId: discovery.participantId,
            weight: 1.0,
            teamId: teamIdFor(discovery.participantId, teams),
        },
    ];
}
function creditsForGameDiscoveries(mode, discoveriesByTarget, teams) {
    const isShared = mode === "collaborative";
    const out = [];
    for (const [, targetDiscoveries] of discoveriesByTarget) {
        const sorted = [...targetDiscoveries].sort(discoveryOrderingAscending);
        const discovery = isShared ? sorted[sorted.length - 1] : sorted[0];
        if (!discovery)
            continue;
        const existing = isShared ? sorted.slice(0, -1) : sorted.slice(1);
        out.push(...calcCredits(mode, discovery, existing, teams));
    }
    return out;
}
function buildFirstFindCountByParticipant(discoveries) {
    var _a;
    const byKey = new Map();
    for (const d of discoveries) {
        const k = `${d.gameInstanceId}_${d.targetId}`;
        byKey.set(k, [...(byKey.get(k) || []), d]);
    }
    const firstFindCount = {};
    for (const list of byKey.values()) {
        const sorted = [...list].sort(discoveryOrderingAscending);
        const firstId = (_a = sorted[0]) === null || _a === void 0 ? void 0 : _a.participantId;
        if (firstId) {
            firstFindCount[firstId] = (firstFindCount[firstId] || 0) + 1;
        }
    }
    return firstFindCount;
}
function contributionSummary(discoveries, credits) {
    const discoveryCountByParticipant = {};
    for (const d of discoveries) {
        discoveryCountByParticipant[d.participantId] = (discoveryCountByParticipant[d.participantId] || 0) + 1;
    }
    let weightedScoreByParticipant;
    if (credits.length === 0) {
        weightedScoreByParticipant = Object.fromEntries(Object.entries(discoveryCountByParticipant).map(([k, v]) => [k, v]));
    }
    else {
        weightedScoreByParticipant = {};
        for (const c of credits) {
            weightedScoreByParticipant[c.participantId] =
                (weightedScoreByParticipant[c.participantId] || 0) + c.weight;
        }
    }
    const firstFind = buildFirstFindCountByParticipant(discoveries);
    const allIds = new Set([
        ...Object.keys(discoveryCountByParticipant),
        ...Object.keys(weightedScoreByParticipant),
    ]);
    return [...allIds].sort().map((participantId) => ({
        participantId,
        discoveryCount: discoveryCountByParticipant[participantId] || 0,
        weightedScore: weightedScoreByParticipant[participantId] || 0,
        firstFindCount: firstFind[participantId] || 0,
    }));
}
function mergeWithRoster(rosterUserIds, contributions) {
    const byId = new Map(contributions.map((c) => [c.participantId, c]));
    for (const uid of rosterUserIds) {
        if (!byId.has(uid)) {
            byId.set(uid, {
                participantId: uid,
                discoveryCount: 0,
                weightedScore: 0,
                firstFindCount: 0,
            });
        }
    }
    return [...byId.values()].sort((a, b) => a.participantId.localeCompare(b.participantId));
}
function isFamilyOnlyTrip(activeUserIds, familyMemberUserIds) {
    if (familyMemberUserIds.size === 0)
        return false;
    if (activeUserIds.length === 0)
        return false;
    return activeUserIds.every((id) => familyMemberUserIds.has(id));
}
/**
 * Preview per-user Firestore increments for one ended trip from canonical docs (no idempotency here).
 */
function previewTripEndedAggregates(input) {
    var _a, _b;
    const status = input.canonicalStatus;
    if (status !== "ended") {
        return null;
    }
    const memberUserIds = [...input.memberUserIds].sort();
    if (memberUserIds.length === 0) {
        return null;
    }
    const buckets = (0, gameplayEventResolver_1.replayDiscoveriesFromDocs)(input.activityEventDocs, undefined);
    const allDiscoveries = [];
    for (const list of buckets.values()) {
        for (const row of list) {
            allDiscoveries.push(row);
        }
    }
    const allCredits = [];
    for (const gameDoc of input.gameDocs) {
        const gid = gameDoc.id;
        const data = gameDoc.data();
        const mode = parseCommonConfigGameMode(data.commonConfigDataBase64);
        const teams = parseTeamsDataBase64(data.teamsDataBase64);
        const gameDisco = allDiscoveries.filter((d) => d.gameInstanceId === gid);
        const byTarget = new Map();
        for (const d of gameDisco) {
            const arr = byTarget.get(d.targetId) || [];
            arr.push(d);
            byTarget.set(d.targetId, arr);
        }
        allCredits.push(...creditsForGameDiscoveries(mode, byTarget, teams));
    }
    const rawContributions = contributionSummary(allDiscoveries, allCredits);
    const merged = mergeWithRoster(memberUserIds, rawContributions);
    const mergedByUser = new Map(merged.map((m) => [m.participantId, m]));
    const gameCount = input.gameDocs.length;
    const perUser = {};
    for (const uid of memberUserIds) {
        const fam = input.familyMemberIdsByUser[uid] || new Set();
        const famOnly = isFamilyOnlyTrip(memberUserIds, fam) ? 1 : 0;
        const row = mergedByUser.get(uid);
        perUser[uid] = {
            totalCompletedTrips: 1,
            totalGamesPlayed: gameCount,
            totalDiscoveries: (_a = row === null || row === void 0 ? void 0 : row.discoveryCount) !== null && _a !== void 0 ? _a : 0,
            totalWeightedScore: (_b = row === null || row === void 0 ? void 0 : row.weightedScore) !== null && _b !== void 0 ? _b : 0,
            familyOnlyTripsCount: famOnly,
        };
    }
    return { memberUserIds, perUser };
}
//# sourceMappingURL=publicLifetimeStatsCore.js.map