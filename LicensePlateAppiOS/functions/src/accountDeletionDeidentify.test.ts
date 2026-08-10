import { describe, it, expect, beforeEach } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { deidentifyUserResidue } from "./accountDeletionDeidentify";
import {
  deletedUserTombstoneIdFor,
  LOCATION_PAYLOAD_KEYS,
} from "./accountDeletionDeidentifyCore";

const DELETED = "uid_deleted_0000000000000000";
const OTHER = "uid_other_00000000000000000";
// Per-user tombstone for the uid under test; existing assertions keep the old name.
const DELETED_USER_TOMBSTONE = deletedUserTombstoneIdFor(DELETED);

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

const LOCATION_PAYLOAD: Record<string, string> = {
  locationLatitude: "41.7658",
  locationLongitude: "-72.6734",
  locationAltitude: "18.2",
  locationHorizontalAccuracy: "5",
  locationVerticalAccuracy: "3",
  locationTimestamp: "1700000000",
};

/**
 * A realistic residue spread: a trip the deleted user owned and played in, a trip they were
 * only kicked from (payload-only residue), a trip reachable only through a pending invite,
 * plus the flat collections.
 */
function seedWorld(db: FakeFirestore): void {
  // --- s1: owned + played
  db.seed("trip_sessions/s1", {
    name: "Summer trip",
    createdBy: DELETED,
    canonicalEndedBy: DELETED,
    canonicalParticipants: [
      { userId: DELETED, role: "owner" },
      { userId: OTHER, role: "member" },
    ],
  });
  db.seed("trip_sessions/s1/members/" + DELETED, { role: "owner" });
  db.seed("trip_sessions/s1/members/" + OTHER, { role: "member" });
  db.seed("trip_sessions/s1/participant_prefs/" + DELETED, {
    userId: DELETED,
    saveLocationWhenMarkingPlates: true,
    source: "user_edit",
  });
  db.seed("trip_sessions/s1/participant_prefs/" + OTHER, {
    userId: OTHER,
    saveLocationWhenMarkingPlates: true,
    source: "user_edit",
  });
  db.seed("trip_sessions/s1/games/g1", { definitionId: "license_plate", sessionId: "s1" });
  db.seed("trip_sessions/s1/games/g1/fairness_ack_watermarks/" + DELETED, { lastAckAt: 1 });
  db.seed("trip_sessions/s1/games/g1/fairness_ack_watermarks/" + OTHER, { lastAckAt: 2 });
  db.seed("trip_sessions/s1/games/g1/private/client_metadata", {
    userId: DELETED,
    clientMetadata: { phoneModel: "iPhone 15" },
  });

  // Their own find, carrying precise location.
  db.seed("trip_sessions/s1/activity_events/e1", {
    sessionId: "s1",
    kind: "region_found",
    actorId: DELETED,
    payload: {
      gameInstanceId: "g1",
      regionId: "CA",
      participantId: DELETED,
      inputMethod: "list",
      ...LOCATION_PAYLOAD,
    },
  });
  db.seed("trip_sessions/s1/activity_events/e1/private/client_metadata", {
    userId: DELETED,
    clientMetadata: { phoneModel: "iPhone 15" },
  });

  // Another member's find — must survive untouched, location included.
  db.seed("trip_sessions/s1/activity_events/e2", {
    sessionId: "s1",
    kind: "region_found",
    actorId: OTHER,
    payload: {
      gameInstanceId: "g1",
      regionId: "NY",
      participantId: OTHER,
      inputMethod: "list",
      ...LOCATION_PAYLOAD,
    },
  });
  db.seed("trip_sessions/s1/activity_events/e2/private/client_metadata", {
    userId: OTHER,
    clientMetadata: { phoneModel: "Pixel" },
  });

  // A rejection naming the deleted user as the first finder.
  db.seed("trip_sessions/s1/activity_events/e3", {
    sessionId: "s1",
    kind: "discovery_rejected",
    actorId: OTHER,
    payload: {
      gameInstanceId: "g1",
      regionId: "CA",
      participantId: OTHER,
      firstFinderParticipantId: DELETED,
      rejectionReason: "server_rejected_late_competitive",
    },
  });

  // --- s2: they were kicked; only payload.participantId names them.
  db.seed("trip_sessions/s2", { name: "Old trip", createdBy: OTHER });
  db.seed("trip_sessions/s2/members/" + OTHER, { role: "owner" });
  db.seed("trip_sessions/s2/activity_events/k1", {
    sessionId: "s2",
    kind: "participant_left",
    actorId: OTHER,
    payload: {
      participantId: DELETED,
      leaveReason: "kicked",
      initiatedByUserId: OTHER,
    },
  });

  // --- s3: reachable only through the pending invite (member doc, no events of theirs).
  db.seed("trip_sessions/s3", { name: "Invited trip", createdBy: OTHER });
  db.seed("trip_sessions/s3/members/" + DELETED, { role: "member" });
  db.seed("trip_sessions/s3/members/" + OTHER, { role: "owner" });
  db.seed("trip_invites/ti1", {
    tripSessionId: "s3",
    fromUserId: OTHER,
    toUserId: DELETED,
    status: "pending",
  });

  // --- s4: still-live trip they OWN — deletion must end it or survivors are
  // stranded (ending is owner-gated; one-active-trip blocks starting another).
  db.seed("trip_sessions/s4", {
    name: "Active trip",
    createdBy: DELETED,
    canonicalStatus: "active",
    canonicalParticipants: [
      { userId: DELETED, role: "owner" },
      { userId: OTHER, role: "member" },
    ],
  });
  db.seed("trip_sessions/s4/members/" + DELETED, { role: "owner" });
  db.seed("trip_sessions/s4/members/" + OTHER, { role: "member" });
  db.seed("trip_sessions/s4/games/g4", { definitionId: "license_plate", sessionId: "s4" });

  // --- flat collections
  db.seed("invites/fi1", {
    type: "family",
    fromUserId: DELETED,
    toUserId: OTHER,
    familyId: "f1",
    status: "pending",
  });
  db.seed("invites/fi2", {
    type: "family",
    fromUserId: OTHER,
    toUserId: DELETED,
    familyId: "f1",
    status: "pending",
  });
  db.seed("invites/fi3", {
    type: "friend",
    fromUserId: OTHER,
    toUserId: "uid_third_0000000000000000",
    status: "pending",
  });
  db.seed("share_codes/c1", {
    type: "family",
    code: "ABC123",
    createdBy: DELETED,
    isRevoked: false,
  });
  db.seed("share_codes/c2", { type: "friend", code: "ZZZ999", createdBy: OTHER, isRevoked: false });
  db.seed("plate_found_notify_buffers/s1__" + DELETED, {
    sessionId: "s1",
    recipientUid: DELETED,
    flushAtMs: 1,
  });
  db.seed("plate_found_notify_buffers/s1__" + OTHER, {
    sessionId: "s1",
    recipientUid: OTHER,
    flushAtMs: 1,
  });
}

/** Every string leaf anywhere in a value. */
function stringLeaves(value: unknown, out: string[] = []): string[] {
  if (typeof value === "string") out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => stringLeaves(v, out));
  else if (value && typeof value === "object") {
    Object.values(value).forEach((v) => stringLeaves(v, out));
  }
  return out;
}

function residuePaths(db: FakeFirestore, uid: string): string[] {
  return db.docPathsMatching(
    (path, data) => path.includes(uid) || stringLeaves(data).includes(uid)
  );
}

function snapshot(db: FakeFirestore): string {
  return JSON.stringify([...db.store.entries()].sort((a, b) => a[0].localeCompare(b[0])));
}

describe("deidentifyUserResidue", () => {
  let db: FakeFirestore;

  beforeEach(async () => {
    db = new FakeFirestore();
    seedWorld(db);
    await deidentifyUserResidue(asFirestore(db), DELETED);
  });

  it("leaves no document anywhere naming the deleted uid", () => {
    expect(residuePaths(db, DELETED)).toEqual([]);
  });

  it("strips precise location from the deleted user's events only", () => {
    const theirs = db.store.get("trip_sessions/s1/activity_events/e1")!;
    const payload = theirs.payload as Record<string, string>;
    for (const key of LOCATION_PAYLOAD_KEYS) {
      expect(payload[key]).toBeUndefined();
    }

    const others = db.store.get("trip_sessions/s1/activity_events/e2")!;
    expect(others.payload).toEqual({
      gameInstanceId: "g1",
      regionId: "NY",
      participantId: OTHER,
      inputMethod: "list",
      ...LOCATION_PAYLOAD,
    });
  });

  it("tombstones the actor and uid payload fields while keeping gameplay meaning", () => {
    expect(db.store.get("trip_sessions/s1/activity_events/e1")).toEqual({
      sessionId: "s1",
      kind: "region_found",
      actorId: DELETED_USER_TOMBSTONE,
      payload: {
        gameInstanceId: "g1",
        regionId: "CA",
        participantId: DELETED_USER_TOMBSTONE,
        inputMethod: "list",
      },
    });
  });

  it("rewrites only the matching uid field when another member is the actor", () => {
    const rejection = db.store.get("trip_sessions/s1/activity_events/e3")!;
    expect(rejection.actorId).toBe(OTHER);
    expect(rejection.payload).toEqual({
      gameInstanceId: "g1",
      regionId: "CA",
      participantId: OTHER,
      firstFinderParticipantId: DELETED_USER_TOMBSTONE,
      rejectionReason: "server_rejected_late_competitive",
    });
  });

  it("reaches a session where only payload.participantId names them", () => {
    expect(db.store.get("trip_sessions/s2/activity_events/k1")!.payload).toEqual({
      participantId: DELETED_USER_TOMBSTONE,
      leaveReason: "kicked",
      initiatedByUserId: OTHER,
    });
  });

  it("reaches a session discoverable only through a pending invite", () => {
    expect(db.store.has("trip_sessions/s3/members/" + DELETED)).toBe(false);
    expect(db.store.has("trip_sessions/s3/members/" + OTHER)).toBe(true);
  });

  it("tombstones the session parent doc and the participant roster row", () => {
    expect(db.store.get("trip_sessions/s1")).toEqual({
      name: "Summer trip",
      createdBy: DELETED_USER_TOMBSTONE,
      canonicalEndedBy: DELETED_USER_TOMBSTONE,
      canonicalParticipants: [
        { userId: DELETED_USER_TOMBSTONE, role: "owner" },
        { userId: OTHER, role: "member" },
      ],
    });
  });

  it("leaves a shared tombstone member doc so roster hydration keeps its shape", () => {
    // fetchTripBootstrapForMember and canonicalParticipants rebuilds derive from
    // `members`; without this doc the trip visibly loses a participant.
    expect(db.store.get(`trip_sessions/s1/members/${DELETED_USER_TOMBSTONE}`)).toMatchObject({
      role: "member",
      tombstone: true,
    });
  });

  it("deletes their uid-keyed trip docs and client_metadata sidecars", () => {
    for (const path of [
      `trip_sessions/s1/members/${DELETED}`,
      `trip_sessions/s1/participant_prefs/${DELETED}`,
      `trip_sessions/s1/games/g1/fairness_ack_watermarks/${DELETED}`,
      "trip_sessions/s1/games/g1/private/client_metadata",
      "trip_sessions/s1/activity_events/e1/private/client_metadata",
      `plate_found_notify_buffers/s1__${DELETED}`,
      "invites/fi1",
      "invites/fi2",
      "trip_invites/ti1",
    ]) {
      expect(db.store.has(path), path).toBe(false);
    }
  });

  it("leaves other participants' docs untouched", () => {
    for (const path of [
      `trip_sessions/s1/members/${OTHER}`,
      `trip_sessions/s1/participant_prefs/${OTHER}`,
      `trip_sessions/s1/games/g1/fairness_ack_watermarks/${OTHER}`,
      "trip_sessions/s1/activity_events/e2/private/client_metadata",
      `plate_found_notify_buffers/s1__${OTHER}`,
      "invites/fi3",
      "share_codes/c2",
    ]) {
      expect(db.store.has(path), path).toBe(true);
    }
    expect(db.store.get("share_codes/c2")).toEqual({
      type: "friend",
      code: "ZZZ999",
      createdBy: OTHER,
      isRevoked: false,
    });
  });

  it("tombstones and revokes their share codes so redeeming cannot mint new residue", () => {
    expect(db.store.get("share_codes/c1")).toEqual({
      type: "family",
      code: "ABC123",
      createdBy: DELETED_USER_TOMBSTONE,
      isRevoked: true,
    });
  });

  it("ends a still-live trip the deleted user owned so survivors are not stranded", () => {
    expect(db.store.get("trip_sessions/s4")).toMatchObject({
      canonicalStatus: "ended",
      canonicalEndedBy: DELETED_USER_TOMBSTONE,
      createdBy: DELETED_USER_TOMBSTONE,
    });
    // Deterministic event id → idempotent re-runs; fires the members-notify trigger.
    expect(
      db.store.get(`trip_sessions/s4/activity_events/trip-ended-${DELETED_USER_TOMBSTONE}`)
    ).toMatchObject({
      kind: "trip_ended",
      actorId: DELETED_USER_TOMBSTONE,
      payload: { reason: "owner_account_deleted" },
    });
    // Open games get an end stamp so recaps read coherently.
    expect(db.store.get("trip_sessions/s4/games/g4")?.endedAt).toBeTruthy();
    // Live trips owned by OTHERS are never touched.
    expect(db.store.get("trip_sessions/s2")).toEqual({ name: "Old trip", createdBy: OTHER });
  });

  it("is a no-op on a second run", async () => {
    const before = snapshot(db);
    db.writeCount = 0;

    const summary = await deidentifyUserResidue(asFirestore(db), DELETED);

    expect(snapshot(db)).toBe(before);
    expect(db.writeCount).toBe(0);
    expect(summary).toEqual({
      sessionCount: 0,
      rewrittenEventCount: 0,
      removedMemberCount: 0,
      removedPrefsCount: 0,
      removedWatermarkCount: 0,
      removedClientMetadataCount: 0,
      removedInviteCount: 0,
      tombstonedShareCodeCount: 0,
      removedNotifyBufferCount: 0,
      endedOwnedSessionCount: 0,
    });
  });
});

describe("deidentifyUserResidue resumability", () => {
  it("completes after a mid-run failure", async () => {
    const db = new FakeFirestore();
    seedWorld(db);

    // Simulate a crash partway through: s1's cheap uid-keyed docs are already gone
    // (the pipeline clears those first) but its events still name the user.
    db.store.delete(`trip_sessions/s1/members/${DELETED}`);
    db.store.delete(`trip_sessions/s1/participant_prefs/${DELETED}`);
    db.store.delete(`trip_sessions/s1/games/g1/fairness_ack_watermarks/${DELETED}`);

    await deidentifyUserResidue(asFirestore(db), DELETED);

    expect(residuePaths(db, DELETED)).toEqual([]);
  });

  it("finishes a partially rewritten event set", async () => {
    const db = new FakeFirestore();
    seedWorld(db);
    await deidentifyUserResidue(asFirestore(db), DELETED);

    // Re-introduce one un-rewritten event, as if the batch containing it never committed.
    db.seed("trip_sessions/s1/activity_events/e1", {
      sessionId: "s1",
      kind: "region_found",
      actorId: DELETED,
      payload: { gameInstanceId: "g1", regionId: "CA", participantId: DELETED, ...LOCATION_PAYLOAD },
    });

    await deidentifyUserResidue(asFirestore(db), DELETED);

    expect(residuePaths(db, DELETED)).toEqual([]);
  });
});

describe("deidentifyUserResidue batching", () => {
  it("pages and batches a session larger than the Firestore write cap", async () => {
    const db = new FakeFirestore();
    db.seed("trip_sessions/big", { name: "Long haul", createdBy: DELETED });
    db.seed(`trip_sessions/big/members/${DELETED}`, { role: "owner" });

    const eventCount = 1000;
    for (let i = 0; i < eventCount; i += 1) {
      db.seed(`trip_sessions/big/activity_events/e${String(i).padStart(5, "0")}`, {
        sessionId: "big",
        kind: "region_found",
        actorId: DELETED,
        payload: { gameInstanceId: "g1", regionId: "CA", participantId: DELETED, ...LOCATION_PAYLOAD },
      });
    }

    // The fake throws if any single batch exceeds Firestore's 500-op cap.
    const summary = await deidentifyUserResidue(asFirestore(db), DELETED);

    expect(summary.rewrittenEventCount).toBe(eventCount);
    expect(residuePaths(db, DELETED)).toEqual([]);
  });
});
