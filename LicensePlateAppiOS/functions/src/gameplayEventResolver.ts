/**
 * Step 13 — Server-side validation for score-sensitive TripActivityEvents.
 * Parity with DiscoveryRulesEngine + TripActivityEventDiscoveryReplay (Swift).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import type { ClientMetadata } from "./clientMetadata";

const MAX_EVENTS_POLICY = 2500;

export const PK = {
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
} as const;

export const KIND_REGION_FOUND = "region_found";
export const KIND_GAME_STARTED = "game_started";
export const KIND_GAME_ENDED = "game_ended";
export const KIND_GAME_COMPLETED = "game_completed";
export const KIND_REGION_REMOVED = "region_removed";
export const KIND_PARTICIPANT_LEFT = "participant_left";
export const KIND_PARTICIPANT_INVITED = "participant_invited";
export const KIND_PARTICIPANT_JOINED = "participant_joined";
export const KIND_DISCOVERY_REJECTED = "discovery_rejected";

/** Appended only by Cloud Functions / trusted paths — not via appendTripActivityEvent from clients. */
const CLIENT_FORBIDDEN_KINDS = new Set<string>([KIND_PARTICIPANT_INVITED, KIND_PARTICIPANT_JOINED]);

export const REJECTION_SERVER_LATE_COMPETITIVE = "server_rejected_late_competitive";
const REJECTION_INVALID_PARTICIPANT = "rejected_invalid_participant";
export const REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP = "server_rejected_superseded_by_earlier_timestamp";

export type AppendResolution = "accepted" | "superseded" | "passthrough";

export interface GameplayAppendCallableResult {
  success: true;
  resolution: AppendResolution;
  appliedEventId?: string;
  rejectionEvent?: Record<string, unknown>;
  /**
   * FR-28h: true when the server stamped this accept as a late replay. Returned so the
   * FINDER'S OWN device learns the stamp — it has the event locally with the original
   * payload, and without this it would keep computing unfrozen competitive outcomes while
   * every other device sees the frozen ones.
   */
  lateReplay?: boolean;
}

/**
 * Payload keys the SERVER owns. They exist on a stored event but never on an incoming one,
 * so they must be excluded from the idempotency comparison — otherwise a retry of an
 * already-committed accept (a flaky network on the consent-resume drain, precisely the
 * cohort FR-28h serves) compares stripped-incoming against stamped-stored, mismatches, and
 * throws `already-exists`, which the client files as a permanent verdict.
 */
const SERVER_STAMPED_PAYLOAD_KEYS: readonly string[] = [PK.lateReplay, PK.serverCommittedAt];

/** Exported for tests: the idempotency comparison must ignore server-owned keys. */
export function withoutServerStampedKeys(payload: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(payload)) {
    if (SERVER_STAMPED_PAYLOAD_KEYS.includes(k)) continue;
    out[k] = v;
  }
  return out;
}

export interface WireEventInput {
  id: string;
  sessionId: string;
  kind: string;
  timestamp: number;
  actorId?: string | null;
  payload?: Record<string, unknown> | null;
  clientMetadata?: ClientMetadata | null;
}

function sessionRef(db: admin.firestore.Firestore, sessionId: string) {
  return db.collection("trip_sessions").doc(sessionId);
}

function tsToSeconds(value: admin.firestore.Timestamp | undefined | null): number {
  if (!value) return 0;
  return value.seconds + value.nanoseconds / 1e9;
}

function secondsToTimestamp(sec: number): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(Math.round(sec * 1000));
}

function stringifyPayload(p: Record<string, unknown> | null | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  if (!p || typeof p !== "object") return out;
  for (const [k, v] of Object.entries(p)) {
    if (v === null || v === undefined) continue;
    out[k] = typeof v === "string" ? v : String(v);
  }
  return out;
}

function setClientMetadataPrivateDoc(
  tx: admin.firestore.Transaction,
  parentRef: admin.firestore.DocumentReference,
  userId: string,
  clientMetadata: ClientMetadata | null | undefined
) {
  if (!clientMetadata) return;
  tx.set(
    parentRef.collection("private").doc("client_metadata"),
    {
      userId,
      clientMetadata,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

interface DiscoveryRow {
  id: string;
  gameInstanceId: string;
  participantId: string;
  targetId: string;
  discoveredAt: admin.firestore.Timestamp;
  inputMethod: string;
  /** Unix seconds from payload; 0 = legacy / missing (sorts last for tie-break). */
  serverCommittedAtSec: number;
  /** FR-28h: server-stamped late replay — excluded from competitive OUTCOME derivation. */
  isLateReplay: boolean;
}

function parseServerCommittedAtSec(payload: Record<string, string>): number {
  const s = payload[PK.serverCommittedAt];
  if (!s) return 0;
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? n : 0;
}

function bucketKey(gameInstanceId: string, regionId: string): string {
  return `${gameInstanceId}|${regionId}`;
}

function compareDiscovery(a: DiscoveryRow, b: DiscoveryRow): number {
  const as = a.discoveredAt.seconds + a.discoveredAt.nanoseconds / 1e9;
  const bs = b.discoveredAt.seconds + b.discoveredAt.nanoseconds / 1e9;
  if (as !== bs) return as - bs;
  const aSrv = a.serverCommittedAtSec > 0 ? a.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
  const bSrv = b.serverCommittedAtSec > 0 ? b.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
  if (aSrv !== bSrv) return aSrv - bSrv;
  if (a.targetId !== b.targetId) return a.targetId < b.targetId ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/** Negative if incoming wins (strictly earlier ordering). */
function compareIncomingVsIncumbent(
  incumbent: DiscoveryRow,
  incomingClientTsSec: number,
  incomingServerCommittedSec: number,
  incomingId: string
): number {
  const incCli = incumbent.discoveredAt.seconds + incumbent.discoveredAt.nanoseconds / 1e9;
  if (incomingClientTsSec !== incCli) return incomingClientTsSec - incCli;
  const incSrv =
    incumbent.serverCommittedAtSec > 0 ? incumbent.serverCommittedAtSec : Number.MAX_SAFE_INTEGER;
  const inSrv =
    incomingServerCommittedSec > 0 ? incomingServerCommittedSec : Number.MAX_SAFE_INTEGER;
  if (inSrv !== incSrv) return inSrv - incSrv;
  if (incomingId < incumbent.id) return -1;
  if (incomingId > incumbent.id) return 1;
  return 0;
}

/**
 * Replay region_found / region_removed / server supersede rejections into active discoveries (Swift parity).
 */
export function replayDiscoveriesFromDocs(
  docs: admin.firestore.QueryDocumentSnapshot[],
  gameInstanceFilter: string | undefined
): Map<string, DiscoveryRow[]> {
  const buckets = new Map<string, DiscoveryRow[]>();

  const rows = docs
    .map((d) => {
      const data = d.data();
      const kind = data.kind as string;
      if (
        kind !== KIND_REGION_FOUND &&
        kind !== KIND_REGION_REMOVED &&
        kind !== KIND_DISCOVERY_REJECTED
      ) {
        return null;
      }
      const ts = data.timestamp as admin.firestore.Timestamp | undefined;
      if (!ts) return null;
      const payload = stringifyPayload(data.payload as Record<string, unknown>);
      const regionId = payload[PK.regionId] || "";
      let gid = payload[PK.gameInstanceId];
      if (kind === KIND_DISCOVERY_REJECTED) {
        if (payload[PK.rejectionReason] !== REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP) return null;
        if (!payload[PK.supersededRegionFoundEventId] || !regionId) return null;
      } else if (!regionId) {
        return null;
      }
      if (!gid && gameInstanceFilter) gid = gameInstanceFilter;
      if (!gid) return null;
      if (gameInstanceFilter && gid !== gameInstanceFilter) return null;
      return {
        docId: d.id,
        kind,
        timestamp: ts,
        actorId: (data.actorId as string) || undefined,
        payload,
        gameInstanceId: gid,
        regionId,
      };
    })
    .filter((x): x is NonNullable<typeof x> => x !== null)
    .sort((a, b) => {
      const as = a.timestamp.seconds + a.timestamp.nanoseconds / 1e9;
      const bs = b.timestamp.seconds + b.timestamp.nanoseconds / 1e9;
      return as - bs;
    });

  for (const row of rows) {
    const key = bucketKey(row.gameInstanceId, row.regionId);
    if (row.kind === KIND_REGION_FOUND) {
      const participantId = row.payload[PK.participantId] || row.actorId || "";
      const inputMethod = row.payload[PK.inputMethod] || "list";
      const list = buckets.get(key) || [];
      list.push({
        id: row.docId,
        gameInstanceId: row.gameInstanceId,
        participantId,
        targetId: row.regionId,
        discoveredAt: row.timestamp,
        inputMethod,
        serverCommittedAtSec: parseServerCommittedAtSec(row.payload),
        isLateReplay: row.payload[PK.lateReplay] === "true",
      });
      buckets.set(key, list);
    } else if (row.kind === KIND_REGION_REMOVED) {
      const removedId = row.payload[PK.removedDiscoveryEventId];
      if (removedId) {
        const list = buckets.get(key);
        if (list) {
          const idx = list.findIndex((x) => x.id === removedId);
          if (idx >= 0) {
            list.splice(idx, 1);
            if (list.length === 0) buckets.delete(key);
            else buckets.set(key, list);
          }
        }
      } else {
        buckets.delete(key);
      }
    } else if (row.kind === KIND_DISCOVERY_REJECTED) {
      const voidId = row.payload[PK.supersededRegionFoundEventId];
      const list = buckets.get(key);
      if (list && voidId) {
        const idx = list.findIndex((x) => x.id === voidId);
        if (idx >= 0) {
          list.splice(idx, 1);
          if (list.length === 0) buckets.delete(key);
          else buckets.set(key, list);
        }
      }
    }
  }

  return buckets;
}

function tripModeFromRoster(participants: unknown[]): "solo" | "multiplayer" {
  const ids = new Set<string>();
  for (const p of participants) {
    if (p && typeof p === "object" && "userId" in p) {
      const uid = String((p as { userId: string }).userId);
      if (uid) ids.add(uid);
    }
  }
  return ids.size > 1 ? "multiplayer" : "solo";
}

/** Remove one user from Firestore `canonicalParticipants` array (wire shape uses `userId`). */
function filterCanonicalParticipantsRemoveUser(participants: unknown[], userId: string): unknown[] {
  return participants.filter((p) => {
    if (p && typeof p === "object" && "userId" in p) {
      return String((p as { userId: string }).userId) !== userId;
    }
    return true;
  });
}

type EvalOutcome =
  | "new_credit"
  | "shared_duplicate"
  | "personal_duplicate"
  | "rejected_duplicate"
  | "rejected_invalid_participant";

/** Exported for unit tests (parity with Swift DiscoveryRulesEngine). */
export function evaluateDiscoverySubmission(
  gameMode: "collaborative" | "competitive",
  tripMode: "solo" | "multiplayer",
  existingForTarget: DiscoveryRow[],
  candidateParticipantId: string
): EvalOutcome {
  if (existingForTarget.length === 0) return "new_credit";
  const same = existingForTarget.some((d) => d.participantId === candidateParticipantId);
  if (same) return "personal_duplicate";
  if (tripMode === "solo") return "rejected_invalid_participant";
  if (gameMode === "competitive") return "rejected_duplicate";
  return "shared_duplicate";
}

function canParticipantUnfind(
  mode: "collaborative" | "competitive",
  userId: string,
  discovery: DiscoveryRow,
  allForTarget: DiscoveryRow[]
): boolean {
  if (mode === "collaborative") {
    return allForTarget.some((d) => d.participantId === userId);
  }
  return discovery.participantId === userId;
}

/* ------------------------------------------------------------------ *
 * FR-28h — offline / consent replay acceptance
 * ------------------------------------------------------------------ */

/** Adult replay horizon after game end. Child accounts are unbounded (FR-28h). */
export const LATE_REPLAY_HORIZON_DAYS = 14;
const LATE_REPLAY_HORIZON_SECONDS = LATE_REPLAY_HORIZON_DAYS * 24 * 60 * 60;

/** Genuine pre-start edge only (lifecycle `created`). Client treats this as a HOLD, not a verdict. */
export const MESSAGE_GAME_NOT_STARTED = "game not started";
/** Permanent verdict: the find's own timestamp is not inside the game's played window. */
export const MESSAGE_REPLAY_OUT_OF_WINDOW = "replay outside game window";
/** Permanent verdict: in-window, but the replay arrived past the adult horizon. */
export const MESSAGE_REPLAY_HORIZON_EXPIRED = "replay horizon expired";

/**
 * The interval a find must fall inside to be replayable. `endSec === null` means the game
 * is closed but recorded no end marker anywhere — see `evaluateReplayAdmission`.
 */
export interface GameReplayWindow {
  startSec: number;
  endSec: number | null;
}

export type ReplayAdmission =
  | { accept: true; lateReplay: boolean }
  | { accept: false; message: string };

/**
 * Whether a `region_found` may be written, and whether it counts as a late replay.
 *
 * `started` is the ordinary path and is never a late replay. `created` is the genuine
 * pre-start edge and stays a hold. Anything else means the game has closed, which is
 * exactly the offline/consent-replay case FR-28h exists for: the find is accepted when it
 * happened inside the played window and arrived within the horizon.
 *
 * The horizon is waived for SOLO trips. Two things make that safe and sufficient: a solo
 * replay is pure self-data — there is no opponent whose outcome it could distort — and the
 * consent-delay case is always solo anyway, because an unconsented child cannot be in a
 * multiplayer trip (FR-38). So no child-specific carve-out is needed, and none exists:
 * multiplayer is bounded at 14 days for everyone. Ambiguous membership fails closed to the
 * bounded path.
 */
export function evaluateReplayAdmission(params: {
  lifecycleState: string;
  eventTimestampSec: number;
  window: GameReplayWindow;
  nowSec: number;
  /** Exactly one session member, who is the caller. Anything else (including unknown). */
  isSoloTrip: boolean;
  horizonSeconds?: number;
}): ReplayAdmission {
  const { lifecycleState, eventTimestampSec, window, nowSec, isSoloTrip } = params;
  const horizon = params.horizonSeconds ?? LATE_REPLAY_HORIZON_SECONDS;

  if (lifecycleState === "started") {
    return { accept: true, lateReplay: false };
  }
  if (lifecycleState === "created") {
    return { accept: false, message: MESSAGE_GAME_NOT_STARTED };
  }

  // Closed game (ended / completed / anything else non-created): replay path.
  //
  // A missing end marker (`endSec === null`) means the game is closed but nothing — game
  // doc, activity events, or the session's own end — recorded when. That leaves the
  // horizon with nothing to anchor to, and someone who can influence what gets published
  // could reach this state deliberately and buy an unbounded window. So on a MULTIPLAYER
  // trip it FAILS CLOSED. Solo trips are unbounded regardless, and are self-data, so
  // there is nothing to buy.
  const upperBound = window.endSec ?? nowSec;
  if (eventTimestampSec < window.startSec || eventTimestampSec > upperBound) {
    return { accept: false, message: MESSAGE_REPLAY_OUT_OF_WINDOW };
  }
  if (isSoloTrip) {
    return { accept: true, lateReplay: true };
  }
  if (window.endSec === null) {
    return { accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED };
  }
  if (nowSec - window.endSec > horizon) {
    return { accept: false, message: MESSAGE_REPLAY_HORIZON_EXPIRED };
  }
  return { accept: true, lateReplay: true };
}

/**
 * The game's played window, preferring the game document's own `startedAt` / `endedAt`.
 *
 * Those fields are written by `publishTripCanonicalState` and are the same client-supplied
 * facts the `game_started` / `game_ended` activity_events carry, but they are already in
 * hand (the resolver has fetched the game doc) and cannot be missing for a published game
 * — `startedAt` is required at publish. The activity_events are the fallback for the case
 * where a game doc predates or omits them.
 */
export function deriveGameReplayWindow(
  gameData: admin.firestore.DocumentData | undefined,
  eventDocs: admin.firestore.QueryDocumentSnapshot[],
  gameInstanceId: string,
  /** Last-resort end anchor: the session's own canonical end (FR-28h fail-closed, R7). */
  sessionCanonicalEndedAt?: admin.firestore.Timestamp | null
): GameReplayWindow {
  const docStart = gameData?.startedAt as admin.firestore.Timestamp | undefined;
  const docEnd = gameData?.endedAt as admin.firestore.Timestamp | undefined;

  let startSec = docStart ? tsToSeconds(docStart) : 0;
  let endSec = docEnd ? tsToSeconds(docEnd) : null;

  if (!docStart || !docEnd) {
    let markerStart: number | null = null;
    let markerEnd: number | null = null;
    for (const d of eventDocs) {
      const data = d.data();
      const k = data.kind as string;
      if (k !== KIND_GAME_STARTED && k !== KIND_GAME_ENDED && k !== KIND_GAME_COMPLETED) continue;
      const payload = stringifyPayload(data.payload as Record<string, unknown>);
      if ((payload[PK.gameInstanceId] || "") !== gameInstanceId) continue;
      const ts = data.timestamp as admin.firestore.Timestamp | undefined;
      if (!ts) continue;
      const sec = tsToSeconds(ts);
      if (k === KIND_GAME_STARTED) {
        markerStart = markerStart === null ? sec : Math.min(markerStart, sec);
      } else {
        markerEnd = markerEnd === null ? sec : Math.max(markerEnd, sec);
      }
    }
    if (!docStart && markerStart !== null) startSec = markerStart;
    if (!docEnd && markerEnd !== null) endSec = markerEnd;
  }

  // A trip that ended bounds every game inside it, so this rescues the legitimate
  // "game markers missing but the trip clearly closed" case before the fail-closed rule.
  if (endSec === null && sessionCanonicalEndedAt) {
    endSec = tsToSeconds(sessionCanonicalEndedAt);
  }

  return { startSec, endSec };
}

function parseCommonConfig(commonConfigDataBase64: string | undefined): { gameMode: string; lifecycleState: string } {
  if (!commonConfigDataBase64) {
    throw new Error("missing_common_config");
  }
  const json = Buffer.from(commonConfigDataBase64, "base64").toString("utf8");
  const o = JSON.parse(json) as { gameMode?: string; lifecycleState?: string };
  return {
    gameMode: o.gameMode === "competitive" ? "competitive" : "collaborative",
    lifecycleState: o.lifecycleState || "created",
  };
}

function eventWireFromDoc(
  id: string,
  sessionId: string,
  data: admin.firestore.DocumentData
): Record<string, unknown> {
  return {
    id,
    sessionId: data.sessionId,
    kind: data.kind,
    timestamp: tsToSeconds(data.timestamp as admin.firestore.Timestamp),
    actorId: data.actorId ?? null,
    payload: data.payload ?? null,
  };
}

function payloadsEqualStringMap(a: Record<string, string>, b: Record<string, string>): boolean {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    if ((a[k] || "") !== (b[k] || "")) return false;
  }
  return true;
}

function serverRejectionDocId(clientEventId: string): string {
  return `srvrej_${clientEventId}`;
}

/**
 * Runs resolver inside a Firestore transaction; performs writes and returns callable result.
 */
export async function resolveGameplayAppendTransaction(
  db: admin.firestore.Firestore,
  tripSessionId: string,
  userId: string,
  event: WireEventInput
): Promise<GameplayAppendCallableResult> {
  const ref = sessionRef(db, tripSessionId);
  const eventRef = ref.collection("activity_events").doc(event.id);
  const kind = event.kind;

  return db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(ref);
    if (!sessionSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Trip session not found");
    }

    const existingEventSnap = await tx.get(eventRef);
    const incomingTs = secondsToTimestamp(event.timestamp);
    const incomingPayload = stringifyPayload(event.payload || undefined);
    // Strip every SERVER-OWNED key from the incoming payload before it is evaluated,
    // compared for idempotency, or written. Both keys are forgeable levers otherwise:
    //
    //   `lateReplay`        — a client could exempt its own finds from competitive
    //                         outcomes, or force inclusion in them.
    //   `serverCommittedAt` — it is the supersede tie-break (`compareIncomingVsIncumbent`),
    //                         where LOWER wins and 0/absent sorts LAST. A client supplying
    //                         a small value could take a contested find from whoever
    //                         genuinely got there first.
    for (const key of SERVER_STAMPED_PAYLOAD_KEYS) {
      delete incomingPayload[key];
    }
    const normalizedActor = userId;

    // Idempotency before roster check so participant_left retries succeed after roster/members update.
    if (existingEventSnap.exists) {
      const ed = existingEventSnap.data()!;
      const sameKind = ed.kind === kind;
      const sameSession = ed.sessionId === tripSessionId;
      const existingPayload = stringifyPayload(ed.payload as Record<string, unknown>);
      const exSec = ed.timestamp ? tsToSeconds(ed.timestamp as admin.firestore.Timestamp) : -1;
      const tsEq = Math.abs(exSec - event.timestamp) < 0.001;
      // Compare only what the CLIENT authored. Server-stamped keys are on the stored copy
      // and never on the incoming one, so including them would make every retry of a
      // committed accept look like an id collision.
      if (
        sameKind &&
        sameSession &&
        tsEq &&
        payloadsEqualStringMap(
          withoutServerStampedKeys(incomingPayload),
          withoutServerStampedKeys(existingPayload)
        )
      ) {
        return {
          success: true,
          resolution: "accepted",
          appliedEventId: event.id,
          // Re-report the stamp so a retrying device still learns it.
          lateReplay: existingPayload[PK.lateReplay] === "true",
        };
      }
      if (sameKind && sameSession) {
        throw new functions.https.HttpsError("already-exists", "event id collision");
      }
    }

    if (CLIENT_FORBIDDEN_KINDS.has(kind)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "This event kind cannot be submitted by clients"
      );
    }

    const callerMemberSnap = await tx.get(ref.collection("members").doc(userId));
    if (!callerMemberSnap.exists) {
      throw new functions.https.HttpsError("permission-denied", "Not a member of this trip session");
    }

    const memSnap = await tx.get(ref.collection("members").limit(64));
    const participants: unknown[] = memSnap.docs.map((d) => {
      const data = d.data();
      const joinedAt = data.joinedAt as admin.firestore.Timestamp | undefined;
      return {
        userId: d.id,
        role: (data.role as string) || "member",
        joinedAt: joinedAt ? tsToSeconds(joinedAt) : 0,
        leftAt: null,
        teamId: (data.teamId as string) ?? null,
      };
    });
    const tripMode = tripModeFromRoster(participants);

    const eventsQuery = ref.collection("activity_events").orderBy("timestamp", "asc").limit(MAX_EVENTS_POLICY);
    const eventsSnap = await tx.get(eventsQuery);
    const eventDocs = eventsSnap.docs;

    const normalizeAndWrite = (payload: Record<string, string>) => {
      tx.set(
        eventRef,
        {
          sessionId: tripSessionId,
          kind,
          timestamp: incomingTs,
          actorId: normalizedActor,
          payload,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      setClientMetadataPrivateDoc(tx, eventRef, userId, event.clientMetadata);
      tx.update(ref, { updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    };

    if (kind === KIND_REGION_FOUND) {
      const gameInstanceId = incomingPayload[PK.gameInstanceId];
      const regionId = incomingPayload[PK.regionId];
      const participantId = incomingPayload[PK.participantId] || "";
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
      const gameData = gameSnap.data()!;
      let cfg: { gameMode: string; lifecycleState: string };
      try {
        cfg = parseCommonConfig(gameData.commonConfigDataBase64 as string | undefined);
      } catch {
        throw new functions.https.HttpsError("failed-precondition", "invalid game config");
      }
      // FR-28h: a find replayed after its game closed (offline play, or a child's queue
      // draining at consent) is accepted when it happened inside the played window and
      // arrived within the horizon. The previous started-only gate rejected every
      // offline-completed trip's discoveries as a permanent verdict.
      const admission = evaluateReplayAdmission({
        lifecycleState: cfg.lifecycleState,
        eventTimestampSec: event.timestamp,
        window: deriveGameReplayWindow(
          gameData,
          eventDocs,
          gameInstanceId,
          sessionSnap.data()?.canonicalEndedAt as admin.firestore.Timestamp | undefined
        ),
        nowSec: admin.firestore.Timestamp.now().seconds,
        // Exactly one member, and membership of the caller was asserted above — so that
        // one member IS the caller. An empty or unreadable roster is not solo, which is
        // the fail-closed direction.
        isSoloTrip: memSnap.size === 1,
      });
      if (!admission.accept) {
        throw new functions.https.HttpsError("failed-precondition", admission.message);
      }
      const isLateReplay = admission.lateReplay;
      const gameMode = cfg.gameMode as "collaborative" | "competitive";

      const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
      const key = bucketKey(gameInstanceId, regionId);
      const existingForTarget = buckets.get(key) || [];

      const outcome = evaluateDiscoverySubmission(gameMode, tripMode, existingForTarget, userId);

      // FR-28h outcome neutrality: a late replay never runs the supersede machinery. Its
      // timestamp may well be earlier than an on-time find's, which is exactly the case
      // that would displace a result the trip already closed on. It still records as a
      // find (or as an ordinary duplicate rejection below) — it just cannot change who won.
      if (!isLateReplay && outcome === "rejected_duplicate" && gameMode === "competitive" && tripMode === "multiplayer") {
        const others = existingForTarget.filter((d) => d.participantId !== userId);
        if (others.length > 0) {
          const nowTsEarly = admin.firestore.Timestamp.now();
          const nowSecEarly = nowTsEarly.seconds;
          const incomingCliSec = event.timestamp;
          const sortedOthers = [...others].sort(compareDiscovery);
          const bestIncumbent = sortedOthers[0];
          if (compareIncomingVsIncumbent(bestIncumbent, incomingCliSec, nowSecEarly, event.id) < 0) {
            for (const displaced of sortedOthers) {
              const supRejId = `srvrej_sup_${displaced.id}`;
              const supRef = ref.collection("activity_events").doc(supRejId);
              const existingSup = await tx.get(supRef);
              if (!existingSup.exists) {
                const discoveredSec = Math.floor(tsToSeconds(displaced.discoveredAt));
                const supPayload: Record<string, string> = {
                  [PK.regionId]: regionId,
                  [PK.gameInstanceId]: gameInstanceId,
                  [PK.participantId]: displaced.participantId,
                  [PK.supersededRegionFoundEventId]: displaced.id,
                  [PK.rejectionReason]: REJECTION_SUPERSEDED_BY_EARLIER_TIMESTAMP,
                  [PK.clientClaimedAt]: String(discoveredSec),
                  [PK.serverResolvedAt]: String(nowSecEarly),
                  [PK.firstFinderParticipantId]: userId,
                  [PK.firstFinderEventId]: event.id,
                  [PK.firstFinderDiscoveredAt]: String(Math.floor(event.timestamp)),
                  [PK.clientAttemptEventId]: displaced.id,
                };
                if (incomingPayload[PK.inputMethod]) {
                  supPayload[PK.inputMethod] = incomingPayload[PK.inputMethod]!;
                }
                supPayload[PK.gameMode] = gameMode;
                supPayload[PK.participantCount] = String(participants.length);
                tx.set(supRef, {
                  sessionId: tripSessionId,
                  kind: KIND_DISCOVERY_REJECTED,
                  timestamp: nowTsEarly,
                  actorId: displaced.participantId,
                  payload: supPayload,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                setClientMetadataPrivateDoc(tx, supRef, userId, event.clientMetadata);
              }
            }
            tx.update(ref, { updatedAt: admin.firestore.FieldValue.serverTimestamp() });
            const mergedPayload: Record<string, string> = {
              ...incomingPayload,
              [PK.participantId]: userId,
              [PK.serverCommittedAt]: String(nowSecEarly),
            };
            normalizeAndWrite(mergedPayload);
            return { success: true, resolution: "accepted", appliedEventId: event.id };
          }
        }
      }

      if (outcome === "rejected_duplicate" || outcome === "rejected_invalid_participant") {
        const rejId = serverRejectionDocId(event.id);
        const rejRef = ref.collection("activity_events").doc(rejId);
        const existingRej = await tx.get(rejRef);
        if (existingRej.exists) {
          const wire = eventWireFromDoc(rejId, tripSessionId, existingRej.data()!);
          return { success: true, resolution: "superseded", rejectionEvent: wire };
        }

        const sorted = [...existingForTarget].sort(compareDiscovery);
        const first = sorted[0];
        const nowTs = admin.firestore.Timestamp.now();
        const nowSec = nowTs.seconds;
        const reason =
          outcome === "rejected_duplicate" ? REJECTION_SERVER_LATE_COMPETITIVE : REJECTION_INVALID_PARTICIPANT;

        const rejPayload: Record<string, string> = {
          [PK.regionId]: regionId,
          [PK.gameInstanceId]: gameInstanceId,
          [PK.participantId]: userId,
          [PK.clientAttemptEventId]: event.id,
          [PK.rejectionReason]: reason,
          [PK.clientClaimedAt]: String(Math.floor(event.timestamp)),
          [PK.serverResolvedAt]: String(nowSec),
        };
        if (first) {
          rejPayload[PK.firstFinderParticipantId] = first.participantId;
          rejPayload[PK.firstFinderDiscoveredAt] = String(tsToSeconds(first.discoveredAt));
          rejPayload[PK.firstFinderEventId] = first.id;
        }
        if (incomingPayload[PK.inputMethod]) {
          rejPayload[PK.inputMethod] = incomingPayload[PK.inputMethod];
        }
        rejPayload[PK.gameMode] = gameMode;
        rejPayload[PK.participantCount] = String(participants.length);

        tx.set(rejRef, {
          sessionId: tripSessionId,
          kind: KIND_DISCOVERY_REJECTED,
          timestamp: nowTs,
          actorId: userId,
          payload: rejPayload,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        setClientMetadataPrivateDoc(tx, rejRef, userId, event.clientMetadata);
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

      const acceptedPayload: Record<string, string> = { ...incomingPayload, [PK.participantId]: userId };
      if (isLateReplay) {
        // Server stamp. Consumers (competitive winner / weighted points) read this to
        // exclude the find from OUTCOME computation only — it still counts for XP,
        // lifetime stats, and every "finds" surface.
        acceptedPayload[PK.lateReplay] = "true";
      }
      normalizeAndWrite(acceptedPayload);
      return {
        success: true,
        resolution: "accepted",
        appliedEventId: event.id,
        lateReplay: isLateReplay,
      };
    }

    if (kind === KIND_REGION_REMOVED) {
      const gameInstanceId = incomingPayload[PK.gameInstanceId];
      const regionId = incomingPayload[PK.regionId];
      if (!gameInstanceId || !regionId) {
        throw new functions.https.HttpsError("invalid-argument", "gameInstanceId and regionId required");
      }

      const gameRef = ref.collection("games").doc(gameInstanceId);
      const gameSnap = await tx.get(gameRef);
      if (!gameSnap.exists) {
        throw new functions.https.HttpsError("failed-precondition", "game not found");
      }
      let cfg: { gameMode: string; lifecycleState: string };
      try {
        cfg = parseCommonConfig(gameSnap.data()!.commonConfigDataBase64 as string | undefined);
      } catch {
        throw new functions.https.HttpsError("failed-precondition", "invalid game config");
      }
      const gameMode = cfg.gameMode as "collaborative" | "competitive";

      const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
      const key = bucketKey(gameInstanceId, regionId);
      const forTarget = buckets.get(key) || [];
      const removedDiscoveryEventId = incomingPayload[PK.removedDiscoveryEventId];

      if (removedDiscoveryEventId) {
        const discovery = forTarget.find((d) => d.id === removedDiscoveryEventId);
        if (!discovery) {
          throw new functions.https.HttpsError("failed-precondition", "discovery not found for removal");
        }
        if (!canParticipantUnfind(gameMode, userId, discovery, forTarget)) {
          throw new functions.https.HttpsError("permission-denied", "cannot remove this find");
        }
      } else {
        if (forTarget.length === 0) {
          throw new functions.https.HttpsError("failed-precondition", "no finds to remove");
        }
        if (gameMode === "competitive") {
          if (forTarget.length !== 1 || forTarget[0].participantId !== userId) {
            throw new functions.https.HttpsError("permission-denied", "legacy unfind not allowed");
          }
        } else {
          if (!forTarget.some((d) => d.participantId === userId)) {
            throw new functions.https.HttpsError("permission-denied", "cannot clear finds for this region");
          }
        }
      }

      normalizeAndWrite(incomingPayload);
      return { success: true, resolution: "accepted", appliedEventId: event.id };
    }

    if (kind === KIND_DISCOVERY_REJECTED) {
      const gameInstanceId = incomingPayload[PK.gameInstanceId];
      if (!gameInstanceId) {
        throw new functions.https.HttpsError("invalid-argument", "gameInstanceId required");
      }
      const gameSnap = await tx.get(ref.collection("games").doc(gameInstanceId));
      if (!gameSnap.exists) {
        throw new functions.https.HttpsError("failed-precondition", "game not found");
      }
      const pid = incomingPayload[PK.participantId] || "";
      if (pid !== userId) {
        throw new functions.https.HttpsError("permission-denied", "participantId must match caller");
      }
      const reason = incomingPayload[PK.rejectionReason] || "";
      if (!reason) {
        throw new functions.https.HttpsError("invalid-argument", "rejectionReason required");
      }
      if (reason === "rejected_duplicate") {
        const rid = incomingPayload[PK.regionId];
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

    if (kind === KIND_PARTICIPANT_LEFT) {
      const participantId = incomingPayload[PK.participantId] || "";
      if (participantId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "participantId must match caller");
      }

      const memberRef = ref.collection("members").doc(userId);
      const memberSnap = await tx.get(memberRef);
      if (!memberSnap.exists) {
        throw new functions.https.HttpsError("failed-precondition", "Member record missing for this trip");
      }
      const role = (memberSnap.data()?.role as string) || "member";
      if (role === "owner") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Driver cannot leave via participant_left; end or cancel the trip instead"
        );
      }

      const nextParticipants = filterCanonicalParticipantsRemoveUser(participants, userId);
      tx.update(ref, {
        canonicalParticipants: nextParticipants,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.delete(memberRef);

      const leavePayload = {
        ...incomingPayload,
        [PK.participantId]: userId,
        [PK.leaveReason]: incomingPayload[PK.leaveReason] || "voluntary",
      };
      normalizeAndWrite(leavePayload);
      return { success: true, resolution: "accepted", appliedEventId: event.id };
    }

    normalizeAndWrite(incomingPayload);
    return { success: true, resolution: "passthrough", appliedEventId: event.id };
  });
}

/**
 * Owner removes another member (kick). Writes `participant_left` with leaveReason=kicked (server-only).
 */
export async function runOwnerRemoveParticipantTransaction(
  db: admin.firestore.Firestore,
  tripSessionId: string,
  ownerUserId: string,
  removedUserId: string,
  clientMetadata: ClientMetadata | null = null
): Promise<{ success: true; appliedEventId: string }> {
  if (removedUserId === ownerUserId) {
    throw new functions.https.HttpsError("invalid-argument", "Cannot remove yourself via this API");
  }
  const ref = sessionRef(db, tripSessionId);
  const kickEventId = `kick_${removedUserId}`;
  return db.runTransaction(async (tx) => {
    const ownerSnap = await tx.get(ref.collection("members").doc(ownerUserId));
    if (!ownerSnap.exists) {
      throw new functions.https.HttpsError("permission-denied", "Not a trip member");
    }
    const ownerRole = (ownerSnap.data()?.role as string) || "member";
    if (ownerRole !== "owner") {
      throw new functions.https.HttpsError("permission-denied", "Only the Driver can remove participants");
    }
    const removedRef = ref.collection("members").doc(removedUserId);
    const removedSnap = await tx.get(removedRef);
    if (!removedSnap.exists) {
      return { success: true, appliedEventId: kickEventId };
    }
    const removedRole = (removedSnap.data()?.role as string) || "member";
    if (removedRole === "owner") {
      throw new functions.https.HttpsError("failed-precondition", "Cannot remove Driver");
    }
    const sessionSnap = await tx.get(ref);
    if (!sessionSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Trip session not found");
    }
    const memSnap = await tx.get(ref.collection("members").limit(64));
    const rosterFromMembers: unknown[] = memSnap.docs.map((d) => {
      const data = d.data();
      const joinedAt = data.joinedAt as admin.firestore.Timestamp | undefined;
      return {
        userId: d.id,
        role: (data.role as string) || "member",
        joinedAt: joinedAt ? tsToSeconds(joinedAt) : 0,
        leftAt: null,
        teamId: (data.teamId as string) ?? null,
      };
    });
    const nextParticipants = filterCanonicalParticipantsRemoveUser(rosterFromMembers, removedUserId);
    const eventRef = ref.collection("activity_events").doc(kickEventId);
    const existingKick = await tx.get(eventRef);
    const nowTs = admin.firestore.Timestamp.now();
    if (!existingKick.exists) {
      tx.set(eventRef, {
        sessionId: tripSessionId,
        kind: KIND_PARTICIPANT_LEFT,
        timestamp: nowTs,
        actorId: ownerUserId,
        payload: {
          [PK.participantId]: removedUserId,
          [PK.leaveReason]: "kicked",
          [PK.initiatedByUserId]: ownerUserId,
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      setClientMetadataPrivateDoc(tx, eventRef, ownerUserId, clientMetadata);
    }
    tx.update(ref, {
      canonicalParticipants: nextParticipants,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.delete(removedRef);
    return { success: true, appliedEventId: kickEventId };
  });
}
