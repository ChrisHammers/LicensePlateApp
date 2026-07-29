/**
 * Trip session canonical sync — server-authoritative writes (Step 12.5).
 * Clients read games/activity_events when trip_sessions member; all writes via these callables.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import {
  resolveGameplayAppendTransaction,
  runOwnerRemoveParticipantTransaction,
  type WireEventInput,
} from "./gameplayEventResolver";
import { mergeFairnessAckSeconds } from "./fairnessWatermarkMerge";
import { clientMetadataWrite, normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";

const db = admin.firestore();

const MAX_BOOTSTRAP_EVENTS = 2500;

function tsToSeconds(value: admin.firestore.Timestamp | undefined | null): number {
  if (!value) {
    return 0;
  }
  return value.seconds + value.nanoseconds / 1e9;
}

function secondsToTimestamp(sec: number | undefined | null): admin.firestore.Timestamp | null {
  if (sec == null || typeof sec !== "number" || Number.isNaN(sec)) {
    return null;
  }
  return admin.firestore.Timestamp.fromMillis(Math.round(sec * 1000));
}

function sessionRef(sessionId: string) {
  return db.collection("trip_sessions").doc(sessionId);
}

function setClientMetadataPrivateDoc(
  batch: admin.firestore.WriteBatch,
  parentRef: admin.firestore.DocumentReference,
  userId: string,
  clientMetadata: ReturnType<typeof normalizeClientMetadata>
) {
  if (!clientMetadata) return 0;
  batch.set(
    parentRef.collection("private").doc("client_metadata"),
    {
      userId,
      clientMetadata,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return 1;
}

/**
 * Combined setup may call `publishTripCanonicalState` before `sendTripInvite` creates `members/{owner}`.
 * When the publish payload's `createdBy` matches the authenticated uid, seed the owner member row.
 */
async function ensureOwnerMemberIfCreatorPayload(
  tripSessionId: string,
  userId: string,
  session: Record<string, unknown>
): Promise<void> {
  const createdBy = session.createdBy as string | undefined;
  if (!createdBy || createdBy !== userId) {
    return;
  }
  const memberRef = sessionRef(tripSessionId).collection("members").doc(userId);
  if ((await memberRef.get()).exists) {
    return;
  }
  await memberRef.set(
    {
      role: "owner",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * If the trip doc already has `createdBy` (e.g. after an invite) but `members/{uid}` is missing,
 * allow the creator to be seeded so `appendTripActivityEvent` can proceed (client/sync race).
 */
async function ensureOwnerMemberIfTripDocCreatedByMatches(
  tripSessionId: string,
  userId: string
): Promise<void> {
  const ref = sessionRef(tripSessionId);
  const memberRef = ref.collection("members").doc(userId);
  if ((await memberRef.get()).exists) {
    return;
  }
  const parent = await ref.get();
  if (!parent.exists) {
    return;
  }
  const createdBy = parent.data()?.createdBy as string | undefined;
  if (!createdBy || createdBy !== userId) {
    return;
  }
  await memberRef.set(
    {
      role: "owner",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function assertTripMember(sessionId: string, userId: string): Promise<void> {
  const memberRef = sessionRef(sessionId).collection("members").doc(userId);
  const snap = await memberRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not a member of this trip session"
    );
  }
}

async function assertTripOwner(sessionId: string, userId: string): Promise<void> {
  const memberRef = sessionRef(sessionId).collection("members").doc(userId);
  const snap = await memberRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not a member of this trip session"
    );
  }
  const role = (snap.data()?.role as string) || "member";
  if (role !== "owner") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the Driver can publish canonical state"
    );
  }
}

function gameDocToWire(id: string, d: admin.firestore.DocumentData): Record<string, unknown> {
  return {
    id,
    definitionId: d.definitionId,
    sessionId: d.sessionId,
    startedAt: tsToSeconds(d.startedAt),
    endedAt: d.endedAt ? tsToSeconds(d.endedAt) : null,
    ruleSetDataBase64: d.ruleSetDataBase64 ?? null,
    commonConfigDataBase64: d.commonConfigDataBase64 ?? null,
    gameSpecificPayloadType: d.gameSpecificPayloadType ?? null,
    gameSpecificPayloadVersion: d.gameSpecificPayloadVersion ?? null,
    gameSpecificPayloadDataBase64: d.gameSpecificPayloadDataBase64 ?? null,
    teamsDataBase64: d.teamsDataBase64 ?? null,
  };
}

function eventDocToWire(id: string, d: admin.firestore.DocumentData): Record<string, unknown> {
  return {
    id,
    sessionId: d.sessionId,
    kind: d.kind,
    timestamp: tsToSeconds(d.timestamp),
    actorId: d.actorId ?? null,
    payload: d.payload ?? null,
  };
}

/** Wire participant rows matching iOS `TripParticipantWireItem` (authoritative source: `members`). */
function wireParticipantsFromMemberDocs(docs: admin.firestore.QueryDocumentSnapshot[]): unknown[] {
  return docs
    .map((d) => {
      const data = d.data();
      const joinedAt = data.joinedAt as admin.firestore.Timestamp | undefined;
      return {
        userId: d.id,
        role: (data.role as string) || "member",
        joinedAt: joinedAt ? tsToSeconds(joinedAt) : 0,
        leftAt: null,
        teamId: (data.teamId as string) ?? null,
      };
    })
    .sort((a, b) => String(a.userId).localeCompare(String(b.userId)));
}

/**
 * Rebuild `canonicalParticipants` on the session doc from `members` (server-only; avoids client clobber).
 */
export async function syncCanonicalParticipantsFromMembers(tripSessionId: string): Promise<void> {
  const ref = sessionRef(tripSessionId);
  const membersSnap = await ref.collection("members").get();
  const participants = wireParticipantsFromMemberDocs(membersSnap.docs);
  await ref.set(
    {
      canonicalParticipants: participants,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Publish full session + games snapshot (owner only).
 */
export const publishTripCanonicalState = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const session = data?.session as Record<string, unknown> | undefined;
  const games = data?.games as Record<string, unknown>[] | undefined;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (!tripSessionId || typeof tripSessionId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
  }
  if (!session || typeof session !== "object") {
    throw new functions.https.HttpsError("invalid-argument", "session is required");
  }
  if (!Array.isArray(games)) {
    throw new functions.https.HttpsError("invalid-argument", "games array is required");
  }

  const sessionIdFromPayload = session.id as string;
  if (sessionIdFromPayload !== tripSessionId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "session.id must match tripSessionId"
    );
  }

  await ensureOwnerMemberIfCreatorPayload(tripSessionId, userId, session);
  await assertTripOwner(tripSessionId, userId);

  const ref = sessionRef(tripSessionId);
  const gamesCol = ref.collection("games");

  const existingGames = await gamesCol.get();
  const incomingIds = new Set(games.map((g) => String(g.id)));

  let batch = db.batch();
  let ops = 0;

  const commitIfNeeded = async () => {
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };

  for (const doc of existingGames.docs) {
    if (!incomingIds.has(doc.id)) {
      batch.delete(doc.ref.collection("private").doc("client_metadata"));
      batch.delete(doc.ref);
      ops += 2;
      await commitIfNeeded();
    }
  }

  const canonicalCreatedAt = secondsToTimestamp(session.createdAt as number);
  if (!canonicalCreatedAt) {
    throw new functions.https.HttpsError("invalid-argument", "session.createdAt is required");
  }
  const canonicalStartedAt = secondsToTimestamp(session.startedAt as number | undefined);
  const canonicalEndedAt = secondsToTimestamp(session.endedAt as number | undefined);

  const parentFields: Record<string, unknown> = {
    name: session.name,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    syncVersion: admin.firestore.FieldValue.increment(1),
    canonicalStatus: session.status,
    canonicalCreatedAt,
    canonicalStartedAt,
    canonicalEndedAt,
    canonicalEndedBy: session.endedBy ?? null,
  };
  const createdByWire = session.createdBy as string | undefined;
  if (typeof createdByWire === "string" && createdByWire.length > 0) {
    parentFields.createdBy = createdByWire;
  }

  batch.set(ref, parentFields, { merge: true });
  ops += 1;
  await commitIfNeeded();

  for (const g of games) {
    const gid = String(g.id);
    const gameRef = gamesCol.doc(gid);
    const startedAt = secondsToTimestamp(g.startedAt as number);
    if (!startedAt) {
      throw new functions.https.HttpsError("invalid-argument", "each game.startedAt is required");
    }
    const endedAt = secondsToTimestamp(g.endedAt as number | undefined);

    batch.set(gameRef, {
      definitionId: g.definitionId,
      sessionId: g.sessionId,
      startedAt,
      endedAt,
      ruleSetDataBase64: g.ruleSetDataBase64 ?? null,
      commonConfigDataBase64: g.commonConfigDataBase64 ?? null,
      gameSpecificPayloadType: g.gameSpecificPayloadType ?? null,
      gameSpecificPayloadVersion: g.gameSpecificPayloadVersion ?? null,
      gameSpecificPayloadDataBase64: g.gameSpecificPayloadDataBase64 ?? null,
      teamsDataBase64: g.teamsDataBase64 ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    ops += 1;
    ops += setClientMetadataPrivateDoc(batch, gameRef, userId, clientMetadata);
    await commitIfNeeded();
  }

  if (ops > 0) {
    await batch.commit();
  }

  const membersAfterPublish = await ref.collection("members").get();
  if (membersAfterPublish.empty) {
    const fromClient = Array.isArray(session.participants) ? session.participants : [];
    await ref.set(
      {
        canonicalParticipants: fromClient,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } else {
    await syncCanonicalParticipantsFromMembers(tripSessionId);
  }

  const parent = await ref.get();
  const syncVersion = (parent.data()?.syncVersion as number) ?? 0;

  await writeAuditLog({
    eventType: "AUDIT_TRIP_CANONICAL_PUBLISHED",
    actorId: userId,
    subjectType: "trip_session",
    subjectId: tripSessionId,
    metadata: { gameCount: games.length, syncVersion },
    clientMetadata,
  });

  return { success: true, syncVersion };
});

/**
 * Append one activity event (idempotent set). Any trip member may call.
 */
export const appendTripActivityEvent = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const event = data?.event as Record<string, unknown> | undefined;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (!tripSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
  }
  if (!event || typeof event !== "object") {
    throw new functions.https.HttpsError("invalid-argument", "event is required");
  }

  await ensureOwnerMemberIfTripDocCreatedByMatches(tripSessionId, userId);
  await assertTripMember(tripSessionId, userId);

  const eventId = event.id as string;
  const sessionIdInEvent = event.sessionId as string;
  if (!eventId || !sessionIdInEvent) {
    throw new functions.https.HttpsError("invalid-argument", "event.id and event.sessionId required");
  }
  if (sessionIdInEvent !== tripSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "event.sessionId must match tripSessionId");
  }
  const kind = event.kind as string;
  if (!kind) {
    throw new functions.https.HttpsError("invalid-argument", "event.kind is required");
  }

  const ts = secondsToTimestamp(event.timestamp as number);
  if (!ts) {
    throw new functions.https.HttpsError("invalid-argument", "event.timestamp is required");
  }

  const wire: WireEventInput = {
    id: eventId,
    sessionId: sessionIdInEvent,
    kind,
    timestamp: event.timestamp as number,
    actorId: (event.actorId as string) ?? null,
    payload: (event.payload as Record<string, unknown>) ?? null,
    clientMetadata,
  };

  const result = await resolveGameplayAppendTransaction(db, tripSessionId, userId, wire);

  return {
    success: true,
    resolution: result.resolution,
    appliedEventId: result.appliedEventId,
    rejectionEvent: result.rejectionEvent,
  };
});

/**
 * Per-user fairness UI watermark (Step 13.2): max lastAckAt in Unix seconds.
 * Stored under games/{gameId}/fairness_ack_watermarks/{userId} so publishTripCanonicalState does not clobber it.
 */
export const updateFairnessAckWatermark = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const gameInstanceId = data?.gameInstanceId as string | undefined;
  const lastAckAtSeconds = data?.lastAckAtSeconds as number | undefined;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (!tripSessionId || !gameInstanceId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "tripSessionId and gameInstanceId are required"
    );
  }
  if (lastAckAtSeconds == null || typeof lastAckAtSeconds !== "number" || Number.isNaN(lastAckAtSeconds)) {
    throw new functions.https.HttpsError("invalid-argument", "lastAckAtSeconds is required");
  }

  await assertTripMember(tripSessionId, userId);

  const ref = sessionRef(tripSessionId)
    .collection("games")
    .doc(gameInstanceId)
    .collection("fairness_ack_watermarks")
    .doc(userId);

  const mergedSeconds = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existingTs = snap.exists ? (snap.data()?.lastAckAt as admin.firestore.Timestamp | undefined) : undefined;
    const existingSec = existingTs ? tsToSeconds(existingTs) : 0;
    const next = mergeFairnessAckSeconds(existingSec, lastAckAtSeconds);
    tx.set(
      ref,
      {
        lastAckAt: secondsToTimestamp(next),
        ...clientMetadataWrite(clientMetadata),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return next;
  });

  return { success: true, lastAckAtSeconds: mergedSeconds };
});

/**
 * Full read for a member: session wire + games + events (capped).
 */
export const fetchTripBootstrapForMember = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  if (!tripSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
  }

  await assertTripMember(tripSessionId, userId);

  const ref = sessionRef(tripSessionId);
  const parentSnap = await ref.get();
  if (!parentSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Trip session not found");
  }

  const p = parentSnap.data()!;

  const membersSnap = await ref.collection("members").get();
  const participantsWire = !membersSnap.empty
    ? wireParticipantsFromMemberDocs(membersSnap.docs)
    : Array.isArray(p.canonicalParticipants)
      ? p.canonicalParticipants
      : [];

  const sessionWire: Record<string, unknown> = {
    id: tripSessionId,
    name: p.name ?? "",
    status: (p.canonicalStatus as string) ?? "created",
    createdAt: tsToSeconds(p.canonicalCreatedAt),
    createdBy: p.createdBy ?? null,
    startedAt: p.canonicalStartedAt ? tsToSeconds(p.canonicalStartedAt) : null,
    endedAt: p.canonicalEndedAt ? tsToSeconds(p.canonicalEndedAt) : null,
    endedBy: p.canonicalEndedBy ?? null,
    participants: participantsWire,
  };

  const gamesSnap = await ref.collection("games").get();
  const games = gamesSnap.docs.map((doc) => gameDocToWire(doc.id, doc.data()));

  const eventsQ = await ref
    .collection("activity_events")
    .orderBy("timestamp", "asc")
    .limit(MAX_BOOTSTRAP_EVENTS + 1)
    .get();

  let nextEventCursor: string | null = null;
  const eventDocs = eventsQ.docs;
  const limited = eventDocs.length > MAX_BOOTSTRAP_EVENTS ? eventDocs.slice(0, MAX_BOOTSTRAP_EVENTS) : eventDocs;
  if (eventDocs.length > MAX_BOOTSTRAP_EVENTS) {
    nextEventCursor = limited[limited.length - 1].id;
  }

  const events = limited.map((doc) => eventDocToWire(doc.id, doc.data()));

  const syncVersion = (p.syncVersion as number) ?? 0;

  return {
    session: sessionWire,
    games,
    events,
    syncVersion,
    nextEventCursor,
  };
});

/**
 * Owner removes another participant (kick). Writes `participant_left` with leaveReason=kicked.
 */
export const removeTripParticipantAsOwner = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const removedUserId = data?.removedUserId as string | undefined;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  if (!tripSessionId || typeof tripSessionId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
  }
  if (!removedUserId || typeof removedUserId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "removedUserId is required");
  }

  await assertTripOwner(tripSessionId, userId);
  await runOwnerRemoveParticipantTransaction(db, tripSessionId, userId, removedUserId, clientMetadata);

  await writeAuditLog({
    eventType: "AUDIT_TRIP_PARTICIPANT_REMOVED",
    actorId: userId,
    subjectType: "trip_session",
    subjectId: tripSessionId,
    metadata: { removedUserId },
    clientMetadata,
  });

  return { success: true };
});

/** Owner: mark remote cancelled and remove games/events for joiner convergence. */
export const markTripCancelledRemote = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }
  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  if (!tripSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "tripSessionId is required");
  }

  await assertTripOwner(tripSessionId, userId);

  const ref = sessionRef(tripSessionId);

  const deleteInBatches = async (coll: admin.firestore.CollectionReference) => {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const snap = await coll.limit(400).get();
      if (snap.empty) {
        break;
      }
      let b = db.batch();
      let c = 0;
      for (const doc of snap.docs) {
        b.delete(doc.ref.collection("private").doc("client_metadata"));
        c += 1;
        b.delete(doc.ref);
        c += 1;
        if (c >= 400) {
          await b.commit();
          b = db.batch();
          c = 0;
        }
      }
      if (c > 0) {
        await b.commit();
      }
    }
  };

  await deleteInBatches(ref.collection("games"));
  await deleteInBatches(ref.collection("activity_events"));

  await ref.set(
    {
      canonicalStatus: "cancelled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncVersion: admin.firestore.FieldValue.increment(1),
    },
    { merge: true }
  );

  await writeAuditLog({
    eventType: "AUDIT_TRIP_CANCELLED_REMOTE",
    actorId: userId,
    subjectType: "trip_session",
    subjectId: tripSessionId,
    metadata: {},
    clientMetadata,
  });

  return { success: true };
});
