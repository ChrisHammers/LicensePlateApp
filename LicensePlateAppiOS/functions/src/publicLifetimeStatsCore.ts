/**
 * Pure aggregation for public lifetime stats (Swift parity: TripSummaryBuilder + ParticipantContributionBuilder + social trip classification).
 */

import * as admin from "firebase-admin";
import { replayDiscoveriesFromDocs, KIND_REGION_FOUND, PK } from "./gameplayEventResolver";

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
 * Whether this session's trip-end baseline has already been folded into a stats doc.
 *
 * The baseline records it with `set(..., {merge:true})` and a key of `appliedTrips.<id>`.
 * Dot-path EXPANSION is an `update()` behaviour — under `set()` the SDK stores a literal
 * top-level field whose name contains a dot. So the nested `appliedTrips` map the obvious
 * read expects never exists, and a guard written against it always misses. Both shapes are
 * checked here: the literal key is what production actually has, the nested map is what a
 * future `update()`-based writer would produce.
 */
export function hasAppliedTripBaseline(
  statsData: admin.firestore.DocumentData | undefined,
  sessionId: string
): boolean {
  if (!statsData) return false;
  if (statsData[`appliedTrips.${sessionId}`] != null) return true;
  const nested = statsData.appliedTrips as Record<string, unknown> | undefined;
  return !!nested && nested[sessionId] != null;
}

/** The only two lifetime fields an extra find can move. Trip/game/social counts are trip-level. */
export interface LateReplayStatsContribution {
  totalDiscoveries: number;
  totalWeightedScore: number;
}

/**
 * Per-session record of how much LATE-REPLAY contribution is already inside a user's
 * lifetime totals — written by whichever of the two triggers counted it.
 *
 * A subcollection, not a map field on the stats doc, so it is never subject to the
 * dot-path trap described on `hasAppliedTripBaseline`.
 */
export function lateReplayLedgerRef(
  db: admin.firestore.Firestore,
  uid: string,
  sessionId: string
): admin.firestore.DocumentReference {
  return db
    .collection("public_lifetime_stats")
    .doc(uid)
    .collection("late_replay_applied")
    .doc(sessionId);
}

export function readLateReplayLedger(
  data: admin.firestore.DocumentData | undefined
): LateReplayStatsContribution {
  return {
    totalDiscoveries: Number(data?.totalDiscoveries ?? 0) || 0,
    totalWeightedScore: Number(data?.totalWeightedScore ?? 0) || 0,
  };
}

/**
 * Whether the session has a `trip_ended` event yet — i.e. whether the trip-end baseline
 * has been TRIGGERED, regardless of whether it has committed.
 *
 * This is what distinguishes the two no-baseline-marker cases for a late find:
 *   - no `trip_ended` → genuinely pre-baseline; the baseline's own later read will include
 *     this find (finds drain before `trip_ended`), so doing nothing is correct.
 *   - `trip_ended` present but marker absent → the baseline is in flight and may have read
 *     the event log BEFORE this find existed, so nobody would ever count it.
 */
export function sessionHasTripEndedEvent(
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[]
): boolean {
  return activityEventDocs.some((d) => (d.data()?.kind as string) === KIND_TRIP_ENDED);
}

/** Re-check cadence and bound for the baseline marker (per-user txs commit in seconds). */
export const BASELINE_MARKER_POLL_INTERVAL_MS = 2_000;
export const BASELINE_MARKER_MAX_WAIT_MS = 60_000;

export type BaselineWaitDecision = "proceed" | "wait" | "skip";

/**
 * What a late find should do when no baseline marker is present yet.
 *
 * The trip-end trigger reads the event log ONCE and then commits per-user transactions
 * sequentially. A find created inside that window is missing from the baseline's totals
 * and has no marker to key off — so without this it is counted nowhere.
 */
export function decideBaselineWait(params: {
  hasTripEnded: boolean;
  markerPresent: boolean;
}): BaselineWaitDecision {
  if (params.markerPresent) return "proceed";
  // No trip_ended: genuinely pre-baseline. Finds drain before `trip_ended`, so the
  // baseline's own read will include this one.
  if (!params.hasTripEnded) return "skip";
  // trip_ended exists but the marker has not landed — the baseline is in flight.
  return "wait";
}

/** FR-28h: a `region_found` the server accepted into an already-ended game. */
export function isLateReplayFindDoc(doc: admin.firestore.QueryDocumentSnapshot): boolean {
  const data = doc.data();
  if ((data?.kind as string) !== KIND_REGION_FOUND) return false;
  const payload = data?.payload as Record<string, unknown> | undefined;
  return String(payload?.[PK.lateReplay] ?? "") === "true";
}

/**
 * How much of this session's lifetime stats is owed to LATE-REPLAY finds, per user.
 *
 * Computed as a difference of two full recomputes — with and without the late finds —
 * rather than a per-find increment, because `totalWeightedScore` is not additive: in
 * collaborative mode a target's credit is split `1/n` across its finders, so a late find
 * arriving on an already-found target REDUCES every earlier finder's credit for it. Only a
 * recompute-and-diff gets that right, and it gets it right for every affected member, not
 * just the late finder.
 *
 * The result is CUMULATIVE (all late finds so far), which is what makes applying it
 * idempotent: the caller stores what it has already applied and increments by the
 * remainder, so replaying the trigger — or a second late find — converges instead of
 * double-counting.
 *
 * Returns null when the trip is not in a state the trip-end aggregator would have scored.
 */
export function previewLateReplayContribution(input: {
  canonicalStatus: string | undefined;
  memberUserIds: string[];
  gameDocs: admin.firestore.QueryDocumentSnapshot[];
  activityEventDocs: admin.firestore.QueryDocumentSnapshot[];
}): Record<string, LateReplayStatsContribution> | null {
  const empty: Record<string, Set<string>> = {};
  const shared = {
    canonicalStatus: input.canonicalStatus,
    memberUserIds: input.memberUserIds,
    gameDocs: input.gameDocs,
    familyMemberIdsByUser: empty,
    friendUserIdsByUser: empty,
  };

  const withLate = previewTripEndedAggregates({ ...shared, activityEventDocs: input.activityEventDocs });
  if (!withLate) return null;
  const withoutLateDocs = input.activityEventDocs.filter((d) => !isLateReplayFindDoc(d));
  if (withoutLateDocs.length === input.activityEventDocs.length) {
    return null; // No late finds recorded — nothing owed.
  }
  const withoutLate = previewTripEndedAggregates({ ...shared, activityEventDocs: withoutLateDocs });
  if (!withoutLate) return null;

  const out: Record<string, LateReplayStatsContribution> = {};
  for (const uid of withLate.memberUserIds) {
    const a = withLate.perUser[uid];
    const b = withoutLate.perUser[uid];
    if (!a || !b) continue;
    out[uid] = {
      totalDiscoveries: a.totalDiscoveries - b.totalDiscoveries,
      totalWeightedScore: a.totalWeightedScore - b.totalWeightedScore,
    };
  }
  return out;
}

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
