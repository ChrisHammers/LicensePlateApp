/**
 * FR-76 (F-32) — the single vocabulary of `activity_events` kinds and payload keys.
 *
 * Everything that decides what a payload key MEANS derives from here, so the three
 * consumers cannot drift apart:
 *
 *  - `gameplayEventResolver.ts` — sanitizes every client-submitted payload against
 *    `SERVER_STAMPED_PAYLOAD_KEYS` + `PAYLOAD_ALLOWLIST_BY_EVENT_KIND` before it is
 *    evaluated, compared for idempotency, or written.
 *  - `accountDeletionDeidentifyCore.ts` — strips `LOCATION_PAYLOAD_KEYS` from a deleted
 *    user's events (it re-exports the list from here).
 *  - the iOS client — `TripActivityEventKind`, `TripActivityEventPayloadKey` and
 *    `LocationData.payloadFields()` are the wire format these strings mirror verbatim.
 *
 * The allowlist is a SECURITY boundary, not a schema: a key that no legitimate client
 * sends is dropped silently, because `stringifyPayload` used to copy every key it was
 * handed into a document every trip member can read.
 */

/* ------------------------------------------------------------------ *
 * Event kinds (wire strings — mirror `TripActivityEventKind`)
 * ------------------------------------------------------------------ */

export const KIND_TRIP_STARTED = "trip_started";
export const KIND_TRIP_ENDED = "trip_ended";
export const KIND_REGION_FOUND = "region_found";
export const KIND_REGION_REMOVED = "region_removed";
export const KIND_DISCOVERY_REJECTED = "discovery_rejected";
export const KIND_GAME_STARTED = "game_started";
export const KIND_GAME_ENDED = "game_ended";
export const KIND_GAME_COMPLETED = "game_completed";
export const KIND_PARTICIPANT_LEFT = "participant_left";
export const KIND_PARTICIPANT_INVITED = "participant_invited";
export const KIND_PARTICIPANT_JOINED = "participant_joined";

/* ------------------------------------------------------------------ *
 * Payload keys (mirror `TripActivityEventPayloadKey`)
 * ------------------------------------------------------------------ */

export const PK = {
  regionId: "regionId",
  gameInstanceId: "gameInstanceId",
  participantId: "participantId",
  inputMethod: "inputMethod",
  rejectionReason: "rejectionReason",
  removedDiscoveryEventId: "removedDiscoveryEventId",
  /** Client's own copy of the `region_found` event id (sync/debug). The server ignores it. */
  discoveryEventId: "discoveryEventId",
  clientAttemptEventId: "clientAttemptEventId",
  firstFinderParticipantId: "firstFinderParticipantId",
  firstFinderDiscoveredAt: "firstFinderDiscoveredAt",
  firstFinderEventId: "firstFinderEventId",
  serverResolvedAt: "serverResolvedAt",
  clientClaimedAt: "clientClaimedAt",
  gameMode: "gameMode",
  participantCount: "participantCount",
  leaveReason: "leaveReason",
  initiatedByUserId: "initiatedByUserId",
  fromUserId: "fromUserId",
  toUserId: "toUserId",
  inviteId: "inviteId",
  inviteMethod: "inviteMethod",
  /** Unix seconds when server accepted this `region_found` (tie-break after client timestamp). */
  serverCommittedAt: "serverCommittedAt",
  /** `discovery_rejected`: `region_found` doc id voided by server_rejected_superseded_by_earlier_timestamp. */
  supersededRegionFoundEventId: "supersededRegionFoundEventId",
  /** Optional client calendar day `YYYY-MM-DD` for first-find-of-day XP (local device calendar). */
  xpDayKey: "xpDayKey",
  /**
   * FR-28h: server-stamped `"true"` on a `region_found` accepted into an already-ended
   * game (offline/consent replay). SERVER-SET ONLY — any client-supplied value is
   * stripped before evaluation, because this flag is what freezes competitive outcomes.
   */
  lateReplay: "lateReplay",
  /** `region_found` only. Written by `LocationData.payloadFields()`, ~110 m coarse. */
  locationLatitude: "locationLatitude",
  locationLongitude: "locationLongitude",
  /** Legacy, never written by a current client and never accepted from one (FR-76). */
  locationAltitude: "locationAltitude",
  locationHorizontalAccuracy: "locationHorizontalAccuracy",
  locationVerticalAccuracy: "locationVerticalAccuracy",
  locationTimestamp: "locationTimestamp",
} as const;

/* ------------------------------------------------------------------ *
 * Location keys
 * ------------------------------------------------------------------ */

/**
 * The location keys a current client may send on a `region_found`: a coarse
 * latitude/longitude plus the capture time. Subject to the FR-76 actor rules — stripped
 * outright for a child, re-rounded server-side for an adult.
 */
export const COARSE_LOCATION_PAYLOAD_KEYS: readonly string[] = [
  PK.locationLatitude,
  PK.locationLongitude,
  PK.locationTimestamp,
];

/**
 * Every precise-location key that has ever existed on a `region_found`. The deletion sweep
 * strips all of them; the FR-76 allowlist accepts only the coarse subset, so the altitude
 * and accuracy keys can no longer be written at all.
 */
export const LOCATION_PAYLOAD_KEYS: readonly string[] = [
  PK.locationLatitude,
  PK.locationLongitude,
  PK.locationAltitude,
  PK.locationHorizontalAccuracy,
  PK.locationVerticalAccuracy,
  PK.locationTimestamp,
];

/**
 * Payload keys the SERVER owns. They exist on a stored event but never on an incoming one,
 * so they must be excluded from the idempotency comparison — otherwise a retry of an
 * already-committed accept (a flaky network on the consent-resume drain, precisely the
 * cohort FR-28h serves) compares stripped-incoming against stamped-stored, mismatches, and
 * throws `already-exists`, which the client files as a permanent verdict.
 */
export const SERVER_STAMPED_PAYLOAD_KEYS: readonly string[] = [PK.lateReplay, PK.serverCommittedAt];

/* ------------------------------------------------------------------ *
 * FR-76 allowlist
 * ------------------------------------------------------------------ */

/**
 * Per-kind allowlist of client-authored payload keys. Derived from what the iOS client
 * actually writes before `recordForSync` (the only path into `appendTripActivityEvent`)
 * and from what the server itself reads back.
 *
 * A kind that is absent — including a kind a modified client invents — allows nothing.
 * Server-authored payloads (`srvrej_*` rejections, `inv_*`/`join_*` invite events, the
 * owner kick) are written directly by Cloud Functions and never pass through here.
 */
export const PAYLOAD_ALLOWLIST_BY_EVENT_KIND: Readonly<Record<string, readonly string[]>> = {
  // No payload at all.
  [KIND_TRIP_STARTED]: [],
  [KIND_TRIP_ENDED]: [],
  [KIND_REGION_FOUND]: [
    PK.regionId,
    PK.gameInstanceId,
    PK.participantId,
    PK.inputMethod,
    PK.discoveryEventId,
    PK.xpDayKey,
    ...COARSE_LOCATION_PAYLOAD_KEYS,
  ],
  [KIND_REGION_REMOVED]: [PK.regionId, PK.gameInstanceId, PK.removedDiscoveryEventId],
  // The client authors its own local duplicate/invalid-participant rejections. The
  // `firstFinder*` / `superseded*` metadata is server-authored only: allowing it here
  // would let a client publish a rejection that voids someone else's find on replay.
  [KIND_DISCOVERY_REJECTED]: [
    PK.regionId,
    PK.gameInstanceId,
    PK.participantId,
    PK.inputMethod,
    PK.rejectionReason,
    PK.participantCount,
    PK.gameMode,
  ],
  // `initiatedByUserId` is the kick path, which is server-written.
  [KIND_PARTICIPANT_LEFT]: [PK.participantId, PK.leaveReason],
  [KIND_GAME_STARTED]: [PK.gameInstanceId],
  [KIND_GAME_ENDED]: [PK.gameInstanceId],
  [KIND_GAME_COMPLETED]: [PK.gameInstanceId],
  // Server-written kinds; the resolver refuses them from clients outright.
  [KIND_PARTICIPANT_INVITED]: [],
  [KIND_PARTICIPANT_JOINED]: [],
};

/* ------------------------------------------------------------------ *
 * Sanitization
 * ------------------------------------------------------------------ */

/** ~110 m. Mirrors `LocationData.payloadCoordinateDecimalPlaces` on iOS. */
export const PAYLOAD_COORDINATE_DECIMAL_PLACES = 3;

function finiteNumber(raw: string): number | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Round to `PAYLOAD_COORDINATE_DECIMAL_PLACES`; idempotent for a value already that coarse. */
export function coarsenCoordinateValue(value: number): number {
  const scale = 10 ** PAYLOAD_COORDINATE_DECIMAL_PLACES;
  return Math.round(value * scale) / scale;
}

/**
 * Validate + coarsen one coarse-location value. `null` drops the key: the client is
 * trusted for neither the precision nor the plausibility of what it sends.
 */
export function normalizeCoarseLocationValue(key: string, raw: string): string | null {
  const parsed = finiteNumber(raw);
  if (parsed === null) return null;
  if (key === PK.locationLatitude && Math.abs(parsed) > 90) return null;
  if (key === PK.locationLongitude && Math.abs(parsed) > 180) return null;
  return String(coarsenCoordinateValue(parsed));
}

/** True when the incoming payload carries any coarse-location key (gates the actor read). */
export function payloadCarriesCoarseLocation(payload: Record<string, string>): boolean {
  return COARSE_LOCATION_PAYLOAD_KEYS.some((key) => payload[key] !== undefined);
}

export interface SanitizeIncomingPayloadInput {
  kind: string;
  payload: Record<string, string>;
  /** Server-resolved `users/{uid}.isChildAccount` for the ACTOR — never a client claim. */
  actorIsChild: boolean;
}

/**
 * FR-76: the one sanitize pass every client-submitted payload goes through.
 *
 *  1. Server-owned keys are dropped (they are stamped later, on the server path only).
 *  2. Anything outside this kind's allowlist is dropped silently — not an error, because
 *     an old or noisy client should still have its find recorded.
 *  3. `region_found` location keys: STRIPPED when the actor is a child (FR-33/75 say the
 *     client should never have sent them; the server stops taking that on trust), and for
 *     everyone else validated numeric and re-rounded to 3 decimals server-side. Altitude
 *     and horizontal/vertical accuracy are not on any allowlist, so they drop with (2).
 */
export function sanitizeIncomingEventPayload(
  input: SanitizeIncomingPayloadInput
): Record<string, string> {
  const allowed = PAYLOAD_ALLOWLIST_BY_EVENT_KIND[input.kind] ?? [];
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(input.payload)) {
    if (SERVER_STAMPED_PAYLOAD_KEYS.includes(key)) continue;
    if (!allowed.includes(key)) continue;
    if (COARSE_LOCATION_PAYLOAD_KEYS.includes(key)) {
      if (input.actorIsChild) continue;
      const normalized = normalizeCoarseLocationValue(key, value);
      if (normalized === null) continue;
      out[key] = normalized;
      continue;
    }
    out[key] = value;
  }
  return out;
}
