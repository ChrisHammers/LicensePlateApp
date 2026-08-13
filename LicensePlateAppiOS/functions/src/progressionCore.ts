/**
 * Pure progression deltas for `user_progression` (Swift parity: TripParticipantRanking + lifetime credit rules).
 * Component grants: one xp_grants row + scope per component (see progressionXpAmounts.ts).
 */

import * as admin from "firebase-admin";
import {
  PK,
  KIND_REGION_FOUND,
  KIND_DISCOVERY_REJECTED,
  REJECTION_SERVER_LATE_COMPETITIVE,
  replayDiscoveriesFromDocs,
} from "./gameplayEventResolver";
import { parseCommonConfigGameMode, parseTeamsDataBase64 } from "./publicLifetimeStatsCore";
import {
  XP_AMOUNTS,
  XP_PER_ACCEPTED_REGION_FOUND,
  XP_PER_COMPETITIVE_FIRST_FINDER_BONUS,
  XP_PER_COMPETITIVE_FIRST_PLACE_FINISH,
} from "./progressionXpAmounts";
import { XP_GRANT_REASON, type XpGrantReason } from "./xpGrantLedgerCore";

export {
  XP_PER_ACCEPTED_REGION_FOUND,
  XP_PER_COMPETITIVE_FIRST_FINDER_BONUS,
  XP_PER_COMPETITIVE_FIRST_PLACE_FINISH,
  XP_AMOUNTS,
};

export const KIND_GAME_ENDED = "game_ended";
export const KIND_GAME_COMPLETED = "game_completed";
export const KIND_TRIP_ENDED = "trip_ended";

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

type DiscoveryRow = {
  id: string;
  gameInstanceId: string;
  participantId: string;
  targetId: string;
  discoveredAt: admin.firestore.Timestamp;
  inputMethod: string;
  serverCommittedAtSec: number;
  /** FR-28h: server-stamped late replay (excluded from competitive OUTCOME). */
  isLateReplay?: boolean;
};

type GameCredit = { discoveryId: string; participantId: string; weight: number; teamId?: string | null };

type ParticipantContribution = {
  participantId: string;
  discoveryCount: number;
  weightedScore: number;
  firstFindCount: number;
};

export type ProgressionComponentGrant = {
  scopeKey: string;
  amount: number;
  reason: XpGrantReason;
  acceptedRegionFindCount?: number;
  competitiveFirstPlaceFinishes?: number;
  awardEverCompetitiveFirstPlace?: boolean;
};

export type ProgressionUserDelta = {
  totalXp: number;
  acceptedRegionFindCount: number;
  competitiveFirstPlaceFinishes: number;
  /** Set true in Firestore merge when this delta includes a competitive first-place finish. */
  awardEverCompetitiveFirstPlace: boolean;
};

function stringifyPayload(p: Record<string, unknown> | null | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  if (!p || typeof p !== "object") return out;
  for (const [k, v] of Object.entries(p)) {
    if (v === null || v === undefined) continue;
    out[k] = typeof v === "string" ? v : String(v);
  }
  return out;
}

function discoveryOrderingAscending(a: DiscoveryRow, b: DiscoveryRow): number {
  const as = a.discoveredAt.seconds + a.discoveredAt.nanoseconds / 1e9;
  const bs = b.discoveredAt.seconds + b.discoveredAt.nanoseconds / 1e9;
  if (as !== bs) return as - bs;
  const aSrv = a.serverCommittedAtSec > 0 ? a.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
  const bSrv = b.serverCommittedAtSec > 0 ? b.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
  if (aSrv !== bSrv) return aSrv - bSrv;
  if (a.targetId !== b.targetId) return a.targetId < b.targetId ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

function teamIdFor(participantId: string, teams: { id: string; participantUserIds: string[] }[]): string | null {
  if (!teams.length) return null;
  const t = teams.find((x) => x.participantUserIds.includes(participantId));
  return t?.id ?? null;
}

function calcCredits(
  mode: "collaborative" | "competitive",
  discovery: DiscoveryRow,
  existingForTarget: DiscoveryRow[],
  teams: { id: string; participantUserIds: string[] }[]
): GameCredit[] {
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

function creditsForGameDiscoveries(
  mode: "collaborative" | "competitive",
  discoveriesByTarget: Map<string, DiscoveryRow[]>,
  teams: { id: string; participantUserIds: string[] }[]
): GameCredit[] {
  const isShared = mode === "collaborative";
  const out: GameCredit[] = [];
  for (const [, targetDiscoveries] of discoveriesByTarget) {
    const sorted = [...targetDiscoveries].sort(discoveryOrderingAscending);
    const discovery = isShared ? sorted[sorted.length - 1] : sorted[0];
    if (!discovery) continue;
    const existing = isShared ? sorted.slice(0, -1) : sorted.slice(1);
    out.push(...calcCredits(mode, discovery, existing, teams));
  }
  return out;
}

function buildFirstFindCountByParticipant(discoveries: DiscoveryRow[]): Record<string, number> {
  const byKey = new Map<string, DiscoveryRow[]>();
  for (const d of discoveries) {
    const k = `${d.gameInstanceId}_${d.targetId}`;
    byKey.set(k, [...(byKey.get(k) || []), d]);
  }
  const firstFindCount: Record<string, number> = {};
  for (const list of byKey.values()) {
    const sorted = [...list].sort(discoveryOrderingAscending);
    const firstId = sorted[0]?.participantId;
    if (firstId) {
      firstFindCount[firstId] = (firstFindCount[firstId] || 0) + 1;
    }
  }
  return firstFindCount;
}

function contributionSummary(discoveries: DiscoveryRow[], credits: GameCredit[]): ParticipantContribution[] {
  const discoveryCountByParticipant: Record<string, number> = {};
  for (const d of discoveries) {
    discoveryCountByParticipant[d.participantId] = (discoveryCountByParticipant[d.participantId] || 0) + 1;
  }
  let weightedScoreByParticipant: Record<string, number>;
  if (credits.length === 0) {
    weightedScoreByParticipant = Object.fromEntries(
      Object.entries(discoveryCountByParticipant).map(([k, v]) => [k, v])
    );
  } else {
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

function mergeWithRoster(rosterUserIds: string[], contributions: ParticipantContribution[]): ParticipantContribution[] {
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
export function rankContributionsSwiftParity(items: ParticipantContribution[]): { participantId: string; rank: number }[] {
  if (items.length === 0) return [];

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

  const result: { participantId: string; rank: number }[] = [];
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
export function competitiveFirstPlaceParticipantIds(mergedContributions: ParticipantContribution[]): string[] {
  const ranked = rankContributionsSwiftParity(mergedContributions);
  return ranked.filter((r) => r.rank === 1).map((r) => r.participantId);
}

export function participantsAtRank(
  mergedContributions: ParticipantContribution[],
  rank: number
): string[] {
  const ranked = rankContributionsSwiftParity(mergedContributions);
  return ranked.filter((r) => r.rank === rank).map((r) => r.participantId);
}

export function baseRegionDiscoveryScopeKey(input: {
  userId: string;
  sessionId: string;
  payload: Record<string, unknown> | null | undefined;
}): string | null {
  const payload = stringifyPayload(input.payload);
  const gameInstanceId = payload[PK.gameInstanceId];
  const regionId = payload[PK.regionId];
  if (!gameInstanceId || !regionId) return null;
  return `xp_scope|v1|${input.userId}|${input.sessionId}|${gameInstanceId}|${regionId}|base_region_discovery`;
}

export function competitiveFirstFinderScopeKey(input: {
  userId: string;
  sessionId: string;
  payload: Record<string, unknown> | null | undefined;
}): string | null {
  const payload = stringifyPayload(input.payload);
  const gameInstanceId = payload[PK.gameInstanceId];
  const regionId = payload[PK.regionId];
  if (!gameInstanceId || !regionId) return null;
  return `xp_scope|v1|${input.userId}|${input.sessionId}|${gameInstanceId}|${regionId}|competitive_first_finder`;
}

export function lifetimeUniqueRegionScopeKey(userId: string, regionId: string): string {
  return `lifetime_unique_region|v1|${userId}|${regionId}`;
}

export function firstFindOfDayScopeKey(userId: string, dayKey: string): string {
  return `first_find_of_day|v1|${userId}|${dayKey}`;
}

export function gameEndedScopeKey(userId: string, gameInstanceId: string): string {
  return `game_ended|v1|${userId}|${gameInstanceId}`;
}

export function gameFullClearScopeKey(userId: string, gameInstanceId: string): string {
  return `game_full_clear|v1|${userId}|${gameInstanceId}`;
}

export function competitivePlaceScopeKey(
  userId: string,
  gameInstanceId: string,
  place: 1 | 2 | 3
): string {
  return `competitive_place|${place}|v1|${userId}|${gameInstanceId}`;
}

export function tripEndedScopeKey(userId: string, sessionId: string): string {
  return `trip_ended|v1|${userId}|${sessionId}`;
}

export function tripParticipationScopeKey(userId: string, sessionId: string): string {
  return `trip_participation|v1|${userId}|${sessionId}`;
}

export function tripCompetitiveFirstScopeKey(userId: string, sessionId: string): string {
  return `trip_competitive_first|v1|${userId}|${sessionId}`;
}

/** Idempotent XP grant scope when an achievement unlock is persisted server-side. */
export function achievementUnlockScopeKey(userId: string, achievementId: string): string {
  return `achievement_xp|v1|${userId}|${achievementId}`;
}

export function normalizeXpDayKey(raw: string | undefined | null): string | null {
  if (!raw || !DAY_KEY_RE.test(raw)) return null;
  return raw;
}

export function utcDayKeyFromUnixSeconds(seconds: number): string {
  const d = new Date(Math.floor(seconds) * 1000);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function emptyDelta(): ProgressionUserDelta {
  return {
    totalXp: 0,
    acceptedRegionFindCount: 0,
    competitiveFirstPlaceFinishes: 0,
    awardEverCompetitiveFirstPlace: false,
  };
}

function sumComponents(components: ProgressionComponentGrant[]): ProgressionUserDelta {
  const d = emptyDelta();
  for (const c of components) {
    d.totalXp += c.amount;
    d.acceptedRegionFindCount += c.acceptedRegionFindCount ?? 0;
    d.competitiveFirstPlaceFinishes += c.competitiveFirstPlaceFinishes ?? 0;
    if (c.awardEverCompetitiveFirstPlace) d.awardEverCompetitiveFirstPlace = true;
  }
  return d;
}

function appendFindBonuses(input: {
  uid: string;
  sessionId: string;
  payload: Record<string, string>;
  includeFirstFinder: boolean;
  dayKey: string | null;
  components: ProgressionComponentGrant[];
}): void {
  const baseScope = baseRegionDiscoveryScopeKey({
    userId: input.uid,
    sessionId: input.sessionId,
    payload: input.payload,
  });
  if (baseScope) {
    input.components.push({
      scopeKey: baseScope,
      amount: XP_AMOUNTS.baseDiscoveryXp,
      reason: XP_GRANT_REASON.REGION_FOUND,
      acceptedRegionFindCount: 1,
    });
  }

  if (input.includeFirstFinder) {
    const ffScope = competitiveFirstFinderScopeKey({
      userId: input.uid,
      sessionId: input.sessionId,
      payload: input.payload,
    });
    if (ffScope) {
      input.components.push({
        scopeKey: ffScope,
        amount: XP_AMOUNTS.firstFinderBonusXp,
        reason: XP_GRANT_REASON.COMPETITIVE_FIRST_FINDER,
      });
    }
  }

  const regionId = input.payload[PK.regionId];
  if (regionId) {
    input.components.push({
      scopeKey: lifetimeUniqueRegionScopeKey(input.uid, regionId),
      amount: XP_AMOUNTS.lifetimeUniqueRegionFindBonusXp,
      reason: XP_GRANT_REASON.LIFETIME_UNIQUE_REGION,
    });
  }

  if (input.dayKey) {
    input.components.push({
      scopeKey: firstFindOfDayScopeKey(input.uid, input.dayKey),
      amount: XP_AMOUNTS.firstFindOfDayBonusXp,
      reason: XP_GRANT_REASON.FIRST_FIND_OF_DAY,
    });
  }
}

function replayAllDiscoveries(
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[]
): DiscoveryRow[] {
  const buckets = replayDiscoveriesFromDocs(activityEventDocs, undefined);
  const allDiscoveries: DiscoveryRow[] = [];
  for (const list of buckets.values()) {
    for (const row of list) {
      allDiscoveries.push(row);
    }
  }
  return allDiscoveries;
}

function tripHasCompetitiveGame(gameDocs: admin.firestore.QueryDocumentSnapshot[]): boolean {
  return gameDocs.some((g) => {
    const mode = parseCommonConfigGameMode(g.data().commonConfigDataBase64 as string | undefined);
    return mode === "competitive";
  });
}

/**
 * FR-28h: a competitive OUTCOME (placement, winner, weighted points) is frozen at trip
 * end, so server-stamped late replays are excluded from it. Their per-find XP and their
 * lifetime-stats contribution are untouched — only the podium is frozen.
 */
export function outcomeEligibleDiscoveries(rows: DiscoveryRow[]): DiscoveryRow[] {
  return rows.filter((d) => d.isLateReplay !== true);
}

function tripLevelContributions(input: {
  memberUserIds: string[];
  gameDocs: admin.firestore.QueryDocumentSnapshot[];
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[];
}): ParticipantContribution[] {
  const allDiscoveries = outcomeEligibleDiscoveries(replayAllDiscoveries(input.activityEventDocs));
  const gamesById = new Map(input.gameDocs.map((d) => [d.id, d]));
  const credits: GameCredit[] = [];

  const byGame = new Map<string, DiscoveryRow[]>();
  for (const d of allDiscoveries) {
    const arr = byGame.get(d.gameInstanceId) || [];
    arr.push(d);
    byGame.set(d.gameInstanceId, arr);
  }

  for (const [gameId, gameDisco] of byGame) {
    const gameDoc = gamesById.get(gameId);
    if (!gameDoc) continue;
    const data = gameDoc.data();
    const mode = parseCommonConfigGameMode(data.commonConfigDataBase64 as string | undefined);
    const teams = parseTeamsDataBase64(data.teamsDataBase64 as string | undefined);
    const byTarget = new Map<string, DiscoveryRow[]>();
    for (const d of gameDisco) {
      const arr = byTarget.get(d.targetId) || [];
      arr.push(d);
      byTarget.set(d.targetId, arr);
    }
    credits.push(...creditsForGameDiscoveries(mode, byTarget, teams));
  }

  const raw = contributionSummary(allDiscoveries, credits);
  return mergeWithRoster(input.memberUserIds, raw);
}

/**
 * Planned component grants for one activity event (caller filters already-applied scopes).
 */
export function previewProgressionComponentsForActivityEvent(input: {
  kind: string;
  actorId: string | null | undefined;
  payload: Record<string, unknown> | null | undefined;
  memberUserIds: string[];
  sessionId: string;
  eventTimestampSeconds?: number;
  gameDocs: admin.firestore.QueryDocumentSnapshot[];
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[];
}): Record<string, ProgressionComponentGrant[]> {
  const payload = stringifyPayload(input.payload);
  const out: Record<string, ProgressionComponentGrant[]> = {};
  const push = (uid: string, components: ProgressionComponentGrant[]) => {
    if (!uid || components.length === 0) return;
    out[uid] = [...(out[uid] || []), ...components];
  };

  const dayKeyFromPayload =
    normalizeXpDayKey(payload.xpDayKey) ||
    (typeof input.eventTimestampSeconds === "number"
      ? utcDayKeyFromUnixSeconds(input.eventTimestampSeconds)
      : null);

  if (input.kind === KIND_REGION_FOUND) {
    const participantId = payload[PK.participantId] || (input.actorId ?? "");
    if (!participantId) return {};
    const gameInstanceId = payload[PK.gameInstanceId];
    const gameDoc = gameInstanceId
      ? input.gameDocs.find((d) => d.id === gameInstanceId)
      : undefined;
    const mode = gameDoc
      ? parseCommonConfigGameMode(gameDoc.data().commonConfigDataBase64 as string | undefined)
      : "collaborative";
    const components: ProgressionComponentGrant[] = [];
    appendFindBonuses({
      uid: participantId,
      sessionId: input.sessionId,
      payload,
      includeFirstFinder: mode === "competitive",
      dayKey: dayKeyFromPayload,
      components,
    });
    push(participantId, components);
    return out;
  }

  if (input.kind === KIND_DISCOVERY_REJECTED) {
    const reason = payload[PK.rejectionReason];
    // Only late competitive (never accepted). Superseded finders already received region_found XP.
    if (reason !== REJECTION_SERVER_LATE_COMPETITIVE) {
      return {};
    }
    const participantId = payload[PK.participantId] || (input.actorId ?? "");
    if (!participantId) return {};
    const components: ProgressionComponentGrant[] = [];
    appendFindBonuses({
      uid: participantId,
      sessionId: input.sessionId,
      payload,
      includeFirstFinder: false,
      dayKey: dayKeyFromPayload,
      components,
    });
    push(participantId, components);
    return out;
  }

  if (input.kind === KIND_GAME_COMPLETED) {
    const gameInstanceId = payload[PK.gameInstanceId];
    if (!gameInstanceId) return {};
    for (const uid of input.memberUserIds) {
      push(uid, [
        {
          scopeKey: gameFullClearScopeKey(uid, gameInstanceId),
          amount: XP_AMOUNTS.gameFullClearBonusXp,
          reason: XP_GRANT_REASON.GAME_FULL_CLEAR,
        },
      ]);
    }
    return out;
  }

  if (input.kind === KIND_GAME_ENDED) {
    const gameInstanceId = payload[PK.gameInstanceId];
    if (!gameInstanceId) return {};

    const gameDoc = input.gameDocs.find((d) => d.id === gameInstanceId);
    if (!gameDoc) return {};

    for (const uid of input.memberUserIds) {
      push(uid, [
        {
          scopeKey: gameEndedScopeKey(uid, gameInstanceId),
          amount: XP_AMOUNTS.gameEndedBonusXp,
          reason: XP_GRANT_REASON.GAME_ENDED,
        },
      ]);
    }

    const data = gameDoc.data();
    const mode = parseCommonConfigGameMode(data.commonConfigDataBase64 as string | undefined);
    if (mode !== "competitive") {
      return out;
    }

    const teams = parseTeamsDataBase64(data.teamsDataBase64 as string | undefined);
    const allDiscoveries = replayAllDiscoveries(input.activityEventDocs);
    // FR-28h: placement is an OUTCOME — late replays are excluded from BOTH the discovery
    // set and the credits built from it. Filtering only the discoveries would leave
    // `weightedScore` (which comes entirely from credits) still moving.
    const gameDisco = outcomeEligibleDiscoveries(
      allDiscoveries.filter((d) => d.gameInstanceId === gameInstanceId)
    );
    if (gameDisco.length === 0) {
      // No frozen result to award: everyone would tie at zero and all take first place.
      return out;
    }
    const byTarget = new Map<string, DiscoveryRow[]>();
    for (const d of gameDisco) {
      const arr = byTarget.get(d.targetId) || [];
      arr.push(d);
      byTarget.set(d.targetId, arr);
    }
    const credits = creditsForGameDiscoveries(mode, byTarget, teams);
    const raw = contributionSummary(gameDisco, credits);
    const merged = mergeWithRoster(input.memberUserIds, raw);

    const placeAmounts: Record<1 | 2 | 3, { amount: number; reason: XpGrantReason }> = {
      1: {
        amount: XP_AMOUNTS.competitiveFirstPlaceFinishBonusXp,
        reason: XP_GRANT_REASON.COMPETITIVE_FIRST_PLACE,
      },
      2: {
        amount: XP_AMOUNTS.competitiveSecondPlaceFinishBonusXp,
        reason: XP_GRANT_REASON.COMPETITIVE_SECOND_PLACE,
      },
      3: {
        amount: XP_AMOUNTS.competitiveThirdPlaceFinishBonusXp,
        reason: XP_GRANT_REASON.COMPETITIVE_THIRD_PLACE,
      },
    };

    for (const place of [1, 2, 3] as const) {
      const ids = participantsAtRank(merged, place);
      for (const uid of ids) {
        push(uid, [
          {
            scopeKey: competitivePlaceScopeKey(uid, gameInstanceId, place),
            amount: placeAmounts[place].amount,
            reason: placeAmounts[place].reason,
            competitiveFirstPlaceFinishes: place === 1 ? 1 : 0,
            awardEverCompetitiveFirstPlace: place === 1,
          },
        ]);
      }
    }
    return out;
  }

  if (input.kind === KIND_TRIP_ENDED) {
    const sessionId = input.sessionId;
    for (const uid of input.memberUserIds) {
      push(uid, [
        {
          scopeKey: tripEndedScopeKey(uid, sessionId),
          amount: XP_AMOUNTS.tripEndedBonusXp,
          reason: XP_GRANT_REASON.TRIP_ENDED,
        },
      ]);
    }

    const allDiscoveries = replayAllDiscoveries(input.activityEventDocs);
    const finders = new Set(allDiscoveries.map((d) => d.participantId));
    for (const uid of input.memberUserIds) {
      if (!finders.has(uid)) continue;
      push(uid, [
        {
          scopeKey: tripParticipationScopeKey(uid, sessionId),
          amount: XP_AMOUNTS.tripParticipationBonusXp,
          reason: XP_GRANT_REASON.TRIP_PARTICIPATION,
        },
      ]);
    }

    if (
      tripHasCompetitiveGame(input.gameDocs) &&
      // FR-28h: a trip whose competitive finds were ALL late replays has no frozen result
      // to award. Without this every participant ties at zero and everyone takes first.
      outcomeEligibleDiscoveries(replayAllDiscoveries(input.activityEventDocs)).length > 0
    ) {
      const merged = tripLevelContributions({
        memberUserIds: input.memberUserIds,
        gameDocs: input.gameDocs,
        activityEventDocs: input.activityEventDocs,
      });
      for (const uid of participantsAtRank(merged, 1)) {
        push(uid, [
          {
            scopeKey: tripCompetitiveFirstScopeKey(uid, sessionId),
            amount: XP_AMOUNTS.tripCompetitiveFirstPlaceBonusXp,
            reason: XP_GRANT_REASON.TRIP_COMPETITIVE_FIRST,
          },
        ]);
      }
    }
    return out;
  }

  return {};
}

/**
 * Per-user Firestore field increments for one new activity event (caller enforces idempotency per user doc).
 * Totals assume all planned components apply (tests); production trigger filters scopes.
 */
export function previewProgressionDeltasForActivityEvent(input: {
  kind: string;
  actorId: string | null | undefined;
  payload: Record<string, unknown> | null | undefined;
  memberUserIds: string[];
  gameDocs: admin.firestore.QueryDocumentSnapshot[];
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[];
  sessionId?: string;
  eventTimestampSeconds?: number;
}): Record<string, ProgressionUserDelta> {
  const componentsByUser = previewProgressionComponentsForActivityEvent({
    ...input,
    sessionId: input.sessionId ?? "session",
  });
  const out: Record<string, ProgressionUserDelta> = {};
  for (const [uid, components] of Object.entries(componentsByUser)) {
    out[uid] = sumComponents(components);
  }
  return out;
}
