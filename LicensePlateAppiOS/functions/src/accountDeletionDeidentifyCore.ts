/**
 * Pure de-identification rules for account deletion (COPPA G2 / FR-50).
 * Firestore-free so vitest can cover the rewrite rules directly; the Firestore
 * driver lives in accountDeletionDeidentify.ts.
 */

import { createHash } from "crypto";

/**
 * Prefix shared by every deleted-user tombstone id. Clients match on this prefix
 * to render "Deleted user" instead of a raw id.
 */
export const DELETED_USER_TOMBSTONE_PREFIX = "deleted-user";

/**
 * Per-user tombstone id: `deleted-user-<8 hex chars of sha256(uid)>`.
 * - Deterministic, so interrupted deletions re-run idempotently.
 * - Distinct per deleted user, so leaderboards/rosters never merge two deleted
 *   people into one row.
 * - Carries no personal information: Firebase uids are high-entropy random
 *   strings, so the truncated hash is not reversible or linkable, and it is
 *   never a valid uid shape (guards like `createdBy === userId` cannot re-match).
 */
export function deletedUserTombstoneIdFor(userId: string): string {
  const hash = createHash("sha256").update(userId).digest("hex").slice(0, 8);
  return `${DELETED_USER_TOMBSTONE_PREFIX}-${hash}`;
}

/**
 * Precise-location payload keys on `region_found` events. Mirrors
 * `TripActivityEventPayloadKey.location*` / `LocationData.payloadFields()` on iOS.
 * These are stripped outright — they are the finder's own geolocation, never
 * de-identifiable by swapping the actor id.
 */
export const LOCATION_PAYLOAD_KEYS: readonly string[] = [
  "locationLatitude",
  "locationLongitude",
  "locationAltitude",
  "locationHorizontalAccuracy",
  "locationVerticalAccuracy",
  "locationTimestamp",
];

/**
 * Payload keys whose value is a uid. Any of these equal to the deleted uid is
 * rewritten to the tombstone so replay/attribution keeps working without the id.
 * Mirrors the uid-valued entries of `PK` in gameplayEventResolver.ts.
 */
export const UID_PAYLOAD_KEYS: readonly string[] = [
  "participantId",
  "firstFinderParticipantId",
  "initiatedByUserId",
  "fromUserId",
  "toUserId",
];

/** Fields to write back on one activity_event; `null` when the doc is already clean. */
export interface DeidentifiedEventUpdate {
  actorId: string;
  payload: Record<string, unknown>;
}

/**
 * Rewrite one activity_event doc for a deleted uid.
 * Returns null when nothing about the doc references the uid and no location keys
 * belonging to it are present — that null is what makes a second run a no-op.
 */
export function deidentifyEventFields(
  data: Record<string, unknown> | undefined | null,
  userId: string
): DeidentifiedEventUpdate | null {
  if (!data) return null;

  const actorId = typeof data.actorId === "string" ? data.actorId : null;
  const rawPayload =
    data.payload && typeof data.payload === "object" && !Array.isArray(data.payload)
      ? (data.payload as Record<string, unknown>)
      : {};

  const actorMatches = actorId === userId;
  const payloadMatches = UID_PAYLOAD_KEYS.some((key) => rawPayload[key] === userId);
  if (!actorMatches && !payloadMatches) {
    return null;
  }

  const tombstone = deletedUserTombstoneIdFor(userId);
  const payload: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(rawPayload)) {
    if (LOCATION_PAYLOAD_KEYS.includes(key)) continue;
    payload[key] = value === userId && UID_PAYLOAD_KEYS.includes(key)
      ? tombstone
      : value;
  }

  return {
    actorId: actorMatches ? tombstone : (actorId ?? tombstone),
    payload,
  };
}

/**
 * Parent `trip_sessions/{id}` fields that still name the deleted uid.
 * Returns null when the session doc is already clean.
 */
export function deidentifySessionFields(
  data: Record<string, unknown> | undefined | null,
  userId: string
): Record<string, unknown> | null {
  if (!data) return null;
  const update: Record<string, unknown> = {};
  const tombstone = deletedUserTombstoneIdFor(userId);

  if (data.createdBy === userId) {
    update.createdBy = tombstone;
  }
  if (data.canonicalEndedBy === userId) {
    update.canonicalEndedBy = tombstone;
  }

  // Tombstone (never prune) the roster row: the participant's de-identified
  // events remain on the trip, so the roster must keep a matching entry or
  // clients render finds by a participant who "doesn't exist" and the
  // participant count silently drops.
  const participants = data.canonicalParticipants;
  if (Array.isArray(participants)) {
    let changed = false;
    const tombstoned = participants.map((p) => {
      if (
        p &&
        typeof p === "object" &&
        "userId" in p &&
        String((p as { userId: unknown }).userId) === userId
      ) {
        changed = true;
        return { ...(p as Record<string, unknown>), userId: tombstone };
      }
      return p;
    });
    if (changed) {
      update.canonicalParticipants = tombstoned;
    }
  }

  return Object.keys(update).length > 0 ? update : null;
}
