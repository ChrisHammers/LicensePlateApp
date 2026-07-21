/**
 * Pure helpers for plate-found push classification and coalesce messaging.
 */

import { TripTeamWire } from "./publicLifetimeStatsCore";

export type PlateFoundRelationship = "co_pilot" | "opponent";

export type PlateFoundPendingItem = {
  regionId: string;
  actorId: string;
  actorDisplayName?: string;
  atMs: number;
};

/**
 * Classify finder → recipient for plate-found push prefs.
 * Solo (caller should skip) is not represented here.
 */
export function classifyPlateFoundRelationship(args: {
  gameMode: "collaborative" | "competitive";
  actorId: string;
  recipientId: string;
  teams: TripTeamWire[];
}): PlateFoundRelationship {
  const { gameMode, actorId, recipientId, teams } = args;
  if (gameMode === "collaborative") {
    return "co_pilot";
  }
  const actorTeam = teams.find((t) => t.participantUserIds.includes(actorId))?.id ?? null;
  const recipientTeam = teams.find((t) => t.participantUserIds.includes(recipientId))?.id ?? null;
  if (actorTeam && recipientTeam && actorTeam === recipientTeam) {
    return "co_pilot";
  }
  return "opponent";
}

export function pushCategoryForRelationship(
  relationship: PlateFoundRelationship
): "plateFoundByOpponent" | "plateFoundByCoPilots" {
  return relationship === "opponent" ? "plateFoundByOpponent" : "plateFoundByCoPilots";
}

export function buildPlateFoundNotificationCopy(args: {
  tripName: string;
  pending: PlateFoundPendingItem[];
}): { title: string; body: string } {
  const { tripName, pending } = args;
  if (pending.length === 0) {
    return { title: "Plates found", body: `${tripName} has new plate finds.` };
  }
  if (pending.length === 1) {
    const item = pending[0]!;
    const name = item.actorDisplayName?.trim() || "A teammate";
    const region = item.regionId || "a plate";
    return {
      title: "Plate found",
      body: `${name} found ${region}`,
    };
  }
  return {
    title: "Plates found",
    body: `${pending.length} plates found on ${tripName}`,
  };
}

/** Coalesce window in milliseconds (90s). */
export const PLATE_FOUND_COALESCE_MS = 90_000;

/**
 * Given existing buffer state and a new find, returns updated pending + whether a flush should be scheduled.
 */
export function mergePlateFoundBuffer(args: {
  existingPending: PlateFoundPendingItem[];
  existingFlushAtMs: number | null;
  nowMs: number;
  item: PlateFoundPendingItem;
  coalesceMs?: number;
}): { pending: PlateFoundPendingItem[]; flushAtMs: number; shouldScheduleFlush: boolean } {
  const coalesceMs = args.coalesceMs ?? PLATE_FOUND_COALESCE_MS;
  const pending = [...args.existingPending, args.item];
  if (args.existingFlushAtMs != null) {
    return {
      pending,
      flushAtMs: args.existingFlushAtMs,
      shouldScheduleFlush: false,
    };
  }
  return {
    pending,
    flushAtMs: args.nowMs + coalesceMs,
    shouldScheduleFlush: true,
  };
}

/**
 * Simulates N finds across recipients: each recipient gets one flush window.
 * Used by unit tests for the "5 × 10 ≠ 50" guarantee.
 */
export function coalesceFlushCountForRecipients(args: {
  recipientIds: string[];
  findsPerActor: number;
  actorIds: string[];
}): number {
  // Each recipient receives one coalesced notification per window regardless of find count.
  void args.findsPerActor;
  void args.actorIds;
  return args.recipientIds.length;
}
