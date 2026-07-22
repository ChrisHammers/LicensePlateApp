/**
 * Pure aggregation for public lifetime stats (Swift parity: TripSummaryBuilder + ParticipantContributionBuilder + social trip classification).
 */

import * as admin from "firebase-admin";
import { replayDiscoveriesFromDocs } from "./gameplayEventResolver";

export const KIND_TRIP_ENDED = "trip_ended";

export type TripTeamWire = { id: string; name?: string; participantUserIds: string[] };

type DiscoveryRow = {
  id: string;
  gameInstanceId: string;
  participantId: string;
  targetId: string;
  discoveredAt: admin.firestore.Timestamp;
  inputMethod: string;
  serverCommittedAtSec: number;
};

type GameCredit = { discoveryId: string; participantId: string; weight: number; teamId?: string | null };

type ParticipantContribution = {
  participantId: string;
  discoveryCount: number;
  weightedScore: number;
  firstFindCount: number;
};

export function parseCommonConfigGameMode(commonConfigDataBase64: string | undefined): "collaborative" | "competitive" {
  if (!commonConfigDataBase64) {
    return "collaborative";
  }
  try {
    const json = Buffer.from(commonConfigDataBase64, "base64").toString("utf8");
    const o = JSON.parse(json) as { gameMode?: string };
    return o.gameMode === "competitive" ? "competitive" : "collaborative";
  } catch {
    return "collaborative";
  }
}

export function parseTeamsDataBase64(teamsDataBase64: string | null | undefined): TripTeamWire[] {
  if (!teamsDataBase64) return [];
  try {
    const json = Buffer.from(teamsDataBase64, "base64").toString("utf8");
    const arr = JSON.parse(json) as TripTeamWire[];
    if (!Array.isArray(arr)) return [];
    return arr.filter((t) => t && typeof t.id === "string" && Array.isArray(t.participantUserIds));
  } catch {
    return [];
  }
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

function teamIdFor(participantId: string, teams: TripTeamWire[]): string | null {
  if (!teams.length) return null;
  const t = teams.find((x) => x.participantUserIds.includes(participantId));
  return t?.id ?? null;
}

function calcCredits(
  mode: "collaborative" | "competitive",
  discovery: DiscoveryRow,
  existingForTarget: DiscoveryRow[],
  teams: TripTeamWire[]
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
  teams: TripTeamWire[]
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

export type SocialTripBucket = "familyOnly" | "friendsOnly" | "mixed" | "neither";

/** Active roster ⊆ family, and at least two people still on the trip. */
export function isFamilyOnlyTrip(activeUserIds: string[], familyMemberUserIds: Set<string>): boolean {
  if (familyMemberUserIds.size === 0) return false;
  if (activeUserIds.length < 2) return false;
  return activeUserIds.every((id) => familyMemberUserIds.has(id));
}

/** Every active family member is still on the trip (`|F| >= 2` ∧ `F ⊆ R`). */
export function isEntireFamilyTrip(activeUserIds: string[], familyMemberUserIds: Set<string>): boolean {
  if (familyMemberUserIds.size < 2) return false;
  const roster = new Set(activeUserIds);
  for (const id of familyMemberUserIds) {
    if (!roster.has(id)) return false;
  }
  return true;
}

/**
 * Family-wins for peers who are both family and friend (`Friends \ F`).
 * Parity: LifetimeStatsSocialClassification.classifySocialTrip
 */
export function classifySocialTrip(
  activeUserIds: string[],
  subjectUserId: string,
  familyMemberUserIds: Set<string>,
  friendUserIds: Set<string>
): SocialTripBucket {
  if (activeUserIds.length < 2) return "neither";

  if (isFamilyOnlyTrip(activeUserIds, familyMemberUserIds)) {
    return "familyOnly";
  }

  const effectiveFriends = new Set([...friendUserIds].filter((id) => !familyMemberUserIds.has(id)));
  const peers = activeUserIds.filter((id) => id !== subjectUserId);
  const famPeers = peers.filter((id) => familyMemberUserIds.has(id));
  const friendPeers = peers.filter((id) => effectiveFriends.has(id));

  if (famPeers.length > 0 && friendPeers.length > 0) {
    return "mixed";
  }

  if (peers.length > 0 && peers.every((id) => effectiveFriends.has(id))) {
    return "friendsOnly";
  }

  return "neither";
}

export type TripEndedApplyPreview = {
  memberUserIds: string[];
  perUser: Record<
    string,
    {
      totalCompletedTrips: number;
      totalGamesPlayed: number;
      totalDiscoveries: number;
      totalWeightedScore: number;
      familyOnlyTripsCount: number;
      friendsOnlyTripsCount: number;
      mixedFriendsFamilyTripsCount: number;
      entireFamilyTripsCount: number;
    }
  >;
};

/**
 * Preview per-user Firestore increments for one ended trip from canonical docs (no idempotency here).
 */
export function previewTripEndedAggregates(input: {
  canonicalStatus: string | undefined;
  memberUserIds: string[];
  gameDocs: admin.firestore.QueryDocumentSnapshot[];
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[];
  familyMemberIdsByUser: Record<string, Set<string>>;
  friendUserIdsByUser: Record<string, Set<string>>;
}): TripEndedApplyPreview | null {
  const status = input.canonicalStatus;
  if (status !== "ended") {
    return null;
  }
  const memberUserIds = [...input.memberUserIds].sort();
  if (memberUserIds.length === 0) {
    return null;
  }

  const buckets = replayDiscoveriesFromDocs(input.activityEventDocs, undefined);
  const allDiscoveries: DiscoveryRow[] = [];
  for (const list of buckets.values()) {
    for (const row of list) {
      allDiscoveries.push(row);
    }
  }

  const allCredits: GameCredit[] = [];
  for (const gameDoc of input.gameDocs) {
    const gid = gameDoc.id;
    const data = gameDoc.data();
    const mode = parseCommonConfigGameMode(data.commonConfigDataBase64 as string | undefined);
    const teams = parseTeamsDataBase64(data.teamsDataBase64 as string | undefined);
    const gameDisco = allDiscoveries.filter((d) => d.gameInstanceId === gid);
    const byTarget = new Map<string, DiscoveryRow[]>();
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
  const perUser: TripEndedApplyPreview["perUser"] = {};

  for (const uid of memberUserIds) {
    const fam = input.familyMemberIdsByUser[uid] || new Set<string>();
    const friends = input.friendUserIdsByUser[uid] || new Set<string>();
    const bucket = classifySocialTrip(memberUserIds, uid, fam, friends);
    const row = mergedByUser.get(uid);
    perUser[uid] = {
      totalCompletedTrips: 1,
      totalGamesPlayed: gameCount,
      totalDiscoveries: row?.discoveryCount ?? 0,
      totalWeightedScore: row?.weightedScore ?? 0,
      familyOnlyTripsCount: bucket === "familyOnly" ? 1 : 0,
      friendsOnlyTripsCount: bucket === "friendsOnly" ? 1 : 0,
      mixedFriendsFamilyTripsCount: bucket === "mixed" ? 1 : 0,
      entireFamilyTripsCount: isEntireFamilyTrip(memberUserIds, fam) ? 1 : 0,
    };
  }

  return { memberUserIds, perUser };
}
