"use strict";
/**
 * Pure progression deltas for `user_progression` (Swift parity: TripParticipantRanking + lifetime credit rules).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.XP_PER_COMPETITIVE_FIRST_PLACE_FINISH = exports.XP_PER_ACCEPTED_REGION_FOUND = exports.KIND_GAME_ENDED = void 0;
exports.rankContributionsSwiftParity = rankContributionsSwiftParity;
exports.competitiveFirstPlaceParticipantIds = competitiveFirstPlaceParticipantIds;
exports.baseRegionDiscoveryScopeKey = baseRegionDiscoveryScopeKey;
exports.previewProgressionDeltasForActivityEvent = previewProgressionDeltasForActivityEvent;
const gameplayEventResolver_1 = require("./gameplayEventResolver");
const publicLifetimeStatsCore_1 = require("./publicLifetimeStatsCore");
exports.KIND_GAME_ENDED = "game_ended";
/** XP awarded per accepted `region_found` (canonical event on server). */
exports.XP_PER_ACCEPTED_REGION_FOUND = 10;
/** XP awarded per competitive first-place finish at `game_ended` (ties: each rank-1 receives this). */
exports.XP_PER_COMPETITIVE_FIRST_PLACE_FINISH = 50;
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
/**
 * Swift `TripParticipantRanking.rankContributions` parity: sort by weightedScore desc, firstFindCount desc,
 * discoveryCount desc, participantId asc; competition ranks (1,1,3).
 */
function rankContributionsSwiftParity(items) {
    if (items.length === 0)
        return [];
    const sorted = [...items].sort((a, b) => {
        if (a.weightedScore !== b.weightedScore) {
            return b.weightedScore - a.weightedScore;
        }
        if (a.firstFindCount !== b.firstFindCount) {
            return b.firstFindCount - a.firstFindCount;
        }
        if (a.discoveryCount !== b.discoveryCount) {
            return b.discoveryCount - a.discoveryCount;
        }
        return a.participantId.localeCompare(b.participantId);
    });
    const result = [];
    let currentRank = 1;
    for (let index = 0; index < sorted.length; index++) {
        const c = sorted[index];
        if (index > 0) {
            const prev = sorted[index - 1];
            if (c.weightedScore !== prev.weightedScore) {
                currentRank = index + 1;
            }
        }
        result.push({ participantId: c.participantId, rank: currentRank });
    }
    return result;
}
/** All participant ids tied for first place (competition rank 1). */
function competitiveFirstPlaceParticipantIds(mergedContributions) {
    const ranked = rankContributionsSwiftParity(mergedContributions);
    return ranked.filter((r) => r.rank === 1).map((r) => r.participantId);
}
/**
 * Scoped idempotency key for base region discovery progression grants.
 * Shape parity with client-side intent: user + trip/session + game + region + grant category.
 */
function baseRegionDiscoveryScopeKey(input) {
    const payload = stringifyPayload(input.payload);
    const gameInstanceId = payload[gameplayEventResolver_1.PK.gameInstanceId];
    const regionId = payload[gameplayEventResolver_1.PK.regionId];
    if (!gameInstanceId || !regionId)
        return null;
    return `xp_scope|v1|${input.userId}|${input.sessionId}|${gameInstanceId}|${regionId}|base_region_discovery`;
}
/**
 * Per-user Firestore field increments for one new activity event (caller enforces idempotency per user doc).
 */
function previewProgressionDeltasForActivityEvent(input) {
    var _a;
    const payload = stringifyPayload(input.payload);
    const out = {};
    const add = (uid, delta) => {
        const cur = out[uid] || {
            totalXp: 0,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            awardEverCompetitiveFirstPlace: false,
        };
        out[uid] = {
            totalXp: cur.totalXp + delta.totalXp,
            acceptedRegionFindCount: cur.acceptedRegionFindCount + delta.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: cur.competitiveFirstPlaceFinishes + delta.competitiveFirstPlaceFinishes,
            awardEverCompetitiveFirstPlace: cur.awardEverCompetitiveFirstPlace || delta.awardEverCompetitiveFirstPlace,
        };
    };
    if (input.kind === gameplayEventResolver_1.KIND_REGION_FOUND) {
        const participantId = payload[gameplayEventResolver_1.PK.participantId] || ((_a = input.actorId) !== null && _a !== void 0 ? _a : "");
        if (!participantId)
            return {};
        add(participantId, {
            totalXp: exports.XP_PER_ACCEPTED_REGION_FOUND,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            awardEverCompetitiveFirstPlace: false,
        });
        return out;
    }
    if (input.kind === exports.KIND_GAME_ENDED) {
        const gameInstanceId = payload[gameplayEventResolver_1.PK.gameInstanceId];
        if (!gameInstanceId)
            return {};
        const gameDoc = input.gameDocs.find((d) => d.id === gameInstanceId);
        if (!gameDoc)
            return {};
        const data = gameDoc.data();
        const mode = (0, publicLifetimeStatsCore_1.parseCommonConfigGameMode)(data.commonConfigDataBase64);
        if (mode !== "competitive") {
            return {};
        }
        const teams = (0, publicLifetimeStatsCore_1.parseTeamsDataBase64)(data.teamsDataBase64);
        const buckets = (0, gameplayEventResolver_1.replayDiscoveriesFromDocs)(input.activityEventDocs, undefined);
        const allDiscoveries = [];
        for (const list of buckets.values()) {
            for (const row of list) {
                allDiscoveries.push(row);
            }
        }
        const gameDisco = allDiscoveries.filter((d) => d.gameInstanceId === gameInstanceId);
        const byTarget = new Map();
        for (const d of gameDisco) {
            const arr = byTarget.get(d.targetId) || [];
            arr.push(d);
            byTarget.set(d.targetId, arr);
        }
        const credits = creditsForGameDiscoveries(mode, byTarget, teams);
        const raw = contributionSummary(gameDisco, credits);
        const merged = mergeWithRoster(input.memberUserIds, raw);
        const firstPlaceIds = competitiveFirstPlaceParticipantIds(merged);
        for (const uid of firstPlaceIds) {
            add(uid, {
                totalXp: exports.XP_PER_COMPETITIVE_FIRST_PLACE_FINISH,
                acceptedRegionFindCount: 0,
                competitiveFirstPlaceFinishes: 1,
                awardEverCompetitiveFirstPlace: true,
            });
        }
        return out;
    }
    return {};
}
//# sourceMappingURL=progressionCore.js.map