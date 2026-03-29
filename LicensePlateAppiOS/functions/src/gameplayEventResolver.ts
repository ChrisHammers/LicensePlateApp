/**
 * Step 13 — Server-side validation for score-sensitive TripActivityEvents.
 * Parity with DiscoveryRulesEngine + TripActivityEventDiscoveryReplay (Swift).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

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
} as const;

export const KIND_REGION_FOUND = "region_found";
export const KIND_REGION_REMOVED = "region_removed";
export const KIND_PARTICIPANT_LEFT = "participant_left";
const KIND_DISCOVERY_REJECTED = "discovery_rejected";

const REJECTION_SERVER_LATE_COMPETITIVE = "server_rejected_late_competitive";
const REJECTION_INVALID_PARTICIPANT = "rejected_invalid_participant";

export type AppendResolution = "accepted" | "superseded" | "passthrough";

export interface GameplayAppendCallableResult {
  success: true;
  resolution: AppendResolution;
  appliedEventId?: string;
  rejectionEvent?: Record<string, unknown>;
}

export interface WireEventInput {
  id: string;
  sessionId: string;
  kind: string;
  timestamp: number;
  actorId?: string | null;
  payload?: Record<string, unknown> | null;
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

interface DiscoveryRow {
  id: string;
  gameInstanceId: string;
  participantId: string;
  targetId: string;
  discoveredAt: admin.firestore.Timestamp;
  inputMethod: string;
}

function bucketKey(gameInstanceId: string, regionId: string): string {
  return `${gameInstanceId}|${regionId}`;
}

function compareDiscovery(a: DiscoveryRow, b: DiscoveryRow): number {
  const as = a.discoveredAt.seconds + a.discoveredAt.nanoseconds / 1e9;
  const bs = b.discoveredAt.seconds + b.discoveredAt.nanoseconds / 1e9;
  if (as !== bs) return as - bs;
  if (a.targetId !== b.targetId) return a.targetId < b.targetId ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/**
 * Replay region_found / region_removed into active discoveries (Swift parity).
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
      if (kind !== KIND_REGION_FOUND && kind !== KIND_REGION_REMOVED) return null;
      const ts = data.timestamp as admin.firestore.Timestamp | undefined;
      if (!ts) return null;
      const payload = stringifyPayload(data.payload as Record<string, unknown>);
      const regionId = payload[PK.regionId];
      if (!regionId) return null;
      let gid = payload[PK.gameInstanceId];
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
      });
      buckets.set(key, list);
    } else {
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

function rosterHasUser(participants: unknown[], userId: string): boolean {
  for (const p of participants) {
    if (p && typeof p === "object" && "userId" in p && String((p as { userId: string }).userId) === userId) {
      return true;
    }
  }
  return false;
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
    const sessionData = sessionSnap.data()!;

    const existingEventSnap = await tx.get(eventRef);
    const incomingTs = secondsToTimestamp(event.timestamp);
    const incomingPayload = stringifyPayload(event.payload || undefined);
    const normalizedActor = userId;

    // Idempotency before roster check so participant_left retries succeed after roster/members update.
    if (existingEventSnap.exists) {
      const ed = existingEventSnap.data()!;
      const sameKind = ed.kind === kind;
      const sameSession = ed.sessionId === tripSessionId;
      const existingPayload = stringifyPayload(ed.payload as Record<string, unknown>);
      const exSec = ed.timestamp ? tsToSeconds(ed.timestamp as admin.firestore.Timestamp) : -1;
      const tsEq = Math.abs(exSec - event.timestamp) < 0.001;
      if (sameKind && sameSession && tsEq && payloadsEqualStringMap(incomingPayload, existingPayload)) {
        return { success: true, resolution: "accepted", appliedEventId: event.id };
      }
      if (sameKind && sameSession) {
        throw new functions.https.HttpsError("already-exists", "event id collision");
      }
    }

    const participants = Array.isArray(sessionData.canonicalParticipants) ? sessionData.canonicalParticipants : [];
    if (!rosterHasUser(participants, userId)) {
      throw new functions.https.HttpsError("permission-denied", "Not a member of this trip session");
    }
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
      if (cfg.lifecycleState !== "started") {
        throw new functions.https.HttpsError("failed-precondition", "game not started");
      }
      const gameMode = cfg.gameMode as "collaborative" | "competitive";

      const buckets = replayDiscoveriesFromDocs(eventDocs, gameInstanceId);
      const key = bucketKey(gameInstanceId, regionId);
      const existingForTarget = buckets.get(key) || [];

      const outcome = evaluateDiscoverySubmission(gameMode, tripMode, existingForTarget, userId);

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

      normalizeAndWrite({ ...incomingPayload, [PK.participantId]: userId });
      return { success: true, resolution: "accepted", appliedEventId: event.id };
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
          "Trip owner cannot leave via participant_left; end or cancel the trip instead"
        );
      }

      const nextParticipants = filterCanonicalParticipantsRemoveUser(participants, userId);
      tx.update(ref, {
        canonicalParticipants: nextParticipants,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.delete(memberRef);

      normalizeAndWrite({ ...incomingPayload, [PK.participantId]: userId });
      return { success: true, resolution: "accepted", appliedEventId: event.id };
    }

    normalizeAndWrite(incomingPayload);
    return { success: true, resolution: "passthrough", appliedEventId: event.id };
  });
}
