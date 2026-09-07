/**
 * FR-69 (F-25, audit H-9) — the two standing-invariant sweeps.
 *
 * The property under test is the FR-38 rule stated as a STANDING one: for every child on a
 * LIVE trip roster, every other member of that roster is in that child's active family —
 * held continuously, not only at invite send/accept. Each test drives a real state change
 * (a flag set, a membership exit) against `fakeFirestore` and asserts the roster the app
 * would render afterwards.
 */

import { describe, it, expect, beforeEach } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  CHILD_TRIP_LEAVE_REASON_FAMILY_EXIT,
  CHILD_TRIP_LEAVE_REASON_FLAG_SET,
  sweepChildTripsAfterFlagSet,
  sweepLiveTripsAfterFamilyMembershipExit,
} from "./childTripRosterInvariants";
import { applyChildProtectionsAfterFlagSet } from "./familyChildStatusFlows";
import { deletedUserTombstoneIdFor } from "./accountDeletionDeidentifyCore";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

const KID = "kid";
const PARENT = "parent";
const AUNT = "aunt";
const STRANGER = "stranger";

/** `parent` + `aunt` + the child `kid` in family `fam1`; `stranger` belongs to nobody. */
function seedFamily(db: FakeFirestore): void {
  db.seed("families/fam1", { name: "Testers", creatorId: PARENT, status: "active" });
  db.seed(`families/fam1/members/${PARENT}`, { role: "creator" });
  db.seed(`families/fam1/members/${AUNT}`, { role: "captain" });
  db.seed(`families/fam1/members/${KID}`, { role: "scout", isChild: true });

  db.seed(`users/${PARENT}`, { activeFamilyId: "fam1", userName: "Parent" });
  db.seed(`users/${AUNT}`, { activeFamilyId: "fam1", userName: "Aunt" });
  db.seed(`users/${KID}`, {
    activeFamilyId: "fam1",
    userName: "KidUser",
    isChildAccount: true,
  });
  db.seed(`users/${STRANGER}`, { userName: "Stranger" });
}

interface TripSeed {
  id: string;
  owner: string;
  members: string[];
  status?: string;
  openGameId?: string;
}

/**
 * A trip as the server actually holds one: parent doc + `members` rows + the
 * `canonicalParticipants` projection + the `participant_joined` events that make each
 * member discoverable (`discoverAffectedSessionIds` finds sessions by event actor).
 */
function seedTrip(db: FakeFirestore, trip: TripSeed): void {
  const roster = [trip.owner, ...trip.members.filter((id) => id !== trip.owner)];
  db.seed(`trip_sessions/${trip.id}`, {
    name: trip.id,
    createdBy: trip.owner,
    canonicalStatus: trip.status ?? "active",
    canonicalParticipants: roster.map((userId) => ({
      userId,
      role: userId === trip.owner ? "owner" : "member",
      joinedAt: 1,
      leftAt: null,
      teamId: null,
    })),
  });
  for (const userId of roster) {
    db.seed(`trip_sessions/${trip.id}/members/${userId}`, {
      role: userId === trip.owner ? "owner" : "member",
      joinedAt: 1,
    });
    db.seed(`trip_sessions/${trip.id}/activity_events/join-${userId}`, {
      sessionId: trip.id,
      kind: "participant_joined",
      actorId: userId,
      payload: {},
    });
  }
  if (trip.openGameId) {
    db.seed(`trip_sessions/${trip.id}/games/${trip.openGameId}`, {
      definitionId: "license_plate",
      sessionId: trip.id,
    });
  }
}

function rosterIds(db: FakeFirestore, tripId: string): string[] {
  const prefix = `trip_sessions/${tripId}/members/`;
  return db
    .docPathsMatching((path) => path.startsWith(prefix))
    .map((path) => path.slice(prefix.length));
}

function canonicalParticipantIds(db: FakeFirestore, tripId: string): string[] {
  const participants = db.store.get(`trip_sessions/${tripId}`)?.canonicalParticipants;
  return Array.isArray(participants)
    ? participants.map((p) => String((p as { userId: unknown }).userId))
    : [];
}

// ---------------------------------------------------------------------------
// FR-69(a) — flag-set
// ---------------------------------------------------------------------------

describe("FR-69(a): flagging a child mid-trip", () => {
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
    seedFamily(db);
  });

  it("takes the child off a live roster that holds a non-family participant", async () => {
    seedTrip(db, { id: "mixed", owner: PARENT, members: [KID, STRANGER] });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result).toEqual({
      scannedLiveSessionCount: 1,
      removedFromSessionCount: 1,
      endedSessionCount: 0,
    });
    // Live participation ends: the member row IS the access grant (isTripSessionMember).
    expect(rosterIds(db, "mixed")).toEqual([PARENT, STRANGER]);
    expect(canonicalParticipantIds(db, "mixed")).toEqual([PARENT, STRANGER]);
    // The trip itself continues for everyone else.
    expect(db.store.get("trip_sessions/mixed")?.canonicalStatus).toBe("active");
    // The departure is recorded, with the FR's reason.
    expect(
      db.store.get(`trip_sessions/mixed/activity_events/coppa-left-child_flag_set-${KID}`)
    ).toMatchObject({
      kind: "participant_left",
      actorId: KID,
      payload: { participantId: KID, leaveReason: CHILD_TRIP_LEAVE_REASON_FLAG_SET },
    });
    // Their own history stays attributed to them — de-identification is deletion's job.
    expect(db.store.get(`trip_sessions/mixed/activity_events/join-${KID}`)?.actorId).toBe(
      KID
    );
  });

  it("ends the trip instead when the child owns it", async () => {
    seedTrip(db, {
      id: "kidowned",
      owner: KID,
      members: [STRANGER],
      openGameId: "g1",
    });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result.endedSessionCount).toBe(1);
    expect(result.removedFromSessionCount).toBe(0);
    expect(db.store.get("trip_sessions/kidowned")).toMatchObject({
      canonicalStatus: "ended",
      canonicalEndedBy: KID,
    });
    expect(
      db.store.get(
        `trip_sessions/kidowned/activity_events/trip-ended-child_flag_set-${KID}`
      )
    ).toMatchObject({
      kind: "trip_ended",
      actorId: KID,
      payload: { reason: CHILD_TRIP_LEAVE_REASON_FLAG_SET },
    });
    // Open games get an end stamp so the recap reads coherently.
    expect(db.store.get("trip_sessions/kidowned/games/g1")?.endedAt).toBeTruthy();
    // Ending is the disposition — the owner is not also pulled off their own roster.
    expect(rosterIds(db, "kidowned")).toEqual([KID, STRANGER]);
  });

  it("leaves family-only and solo live trips exactly as they are", async () => {
    seedTrip(db, { id: "familyonly", owner: PARENT, members: [KID, AUNT] });
    seedTrip(db, { id: "solo", owner: KID, members: [] });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result).toEqual({
      scannedLiveSessionCount: 2,
      removedFromSessionCount: 0,
      endedSessionCount: 0,
    });
    expect(rosterIds(db, "familyonly")).toEqual([AUNT, KID, PARENT]);
    expect(rosterIds(db, "solo")).toEqual([KID]);
    expect(db.store.get("trip_sessions/solo")?.canonicalStatus).toBe("active");
  });

  it("never touches an ended trip — historical rosters are out of scope", async () => {
    seedTrip(db, {
      id: "history",
      owner: STRANGER,
      members: [KID],
      status: "ended",
    });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result).toEqual({
      scannedLiveSessionCount: 0,
      removedFromSessionCount: 0,
      endedSessionCount: 0,
    });
    expect(rosterIds(db, "history")).toEqual([KID, STRANGER]);
  });

  it("does not read a deleted-user tombstone row as a non-family participant", async () => {
    const tombstone = deletedUserTombstoneIdFor("uid_departed_000000000000000");
    seedTrip(db, { id: "memorial", owner: PARENT, members: [KID] });
    // FR-50 leaves this row behind so the recap keeps its participant count. It matches no
    // auth uid and has no users/ doc — there is nobody there for the child to be exposed to.
    db.seed(`trip_sessions/memorial/members/${tombstone}`, {
      role: "member",
      tombstone: true,
    });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result.removedFromSessionCount).toBe(0);
    expect(result.endedSessionCount).toBe(0);
    expect(rosterIds(db, "memorial")).toContain(KID);
  });

  it("treats a roster id that has no account but is NOT a tombstone as an outsider", async () => {
    seedTrip(db, { id: "ghost", owner: PARENT, members: [KID, "uid_no_user_doc"] });

    const result = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(result.removedFromSessionCount).toBe(1);
    expect(rosterIds(db, "ghost")).not.toContain(KID);
  });

  it("is a no-op on a second run", async () => {
    seedTrip(db, { id: "mixed", owner: PARENT, members: [KID, STRANGER] });
    seedTrip(db, { id: "kidowned", owner: KID, members: [STRANGER], openGameId: "g1" });
    await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    const before = JSON.stringify([...db.store.entries()].sort());
    db.writeCount = 0;

    const second = await sweepChildTripsAfterFlagSet(asFirestore(db), KID);

    expect(JSON.stringify([...db.store.entries()].sort())).toBe(before);
    expect(db.writeCount).toBe(0);
    // Both actions are self-clearing: the removal took the child off the roster, and the
    // ended trip is no longer live — so the second pass has nothing left to look at.
    expect(second).toEqual({
      scannedLiveSessionCount: 0,
      removedFromSessionCount: 0,
      endedSessionCount: 0,
    });
  });
});

// ---------------------------------------------------------------------------
// FR-69(b) — family-membership exit
// ---------------------------------------------------------------------------

describe("FR-69(b): a family membership ends under a live trip", () => {
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
    seedFamily(db);
  });

  /** What `removeFamilyMember` / `inactivateFamily` commit before calling the sweep. */
  function commitMembershipExit(db: FakeFirestore, userId: string): void {
    db.store.delete(`families/fam1/members/${userId}`);
    const user = { ...db.store.get(`users/${userId}`)! };
    delete user.activeFamilyId;
    user.wasEverInFamily = true;
    db.store.set(`users/${userId}`, user);
  }

  it("removes the ex-member and leaves the child playing with the family", async () => {
    seedTrip(db, { id: "trip", owner: AUNT, members: [KID, PARENT] });
    commitMembershipExit(db, PARENT);

    const result = await sweepLiveTripsAfterFamilyMembershipExit(asFirestore(db), PARENT);

    expect(result.removedFromSessionCount).toBe(1);
    expect(rosterIds(db, "trip")).toEqual([AUNT, KID]);
    expect(canonicalParticipantIds(db, "trip")).toEqual([AUNT, KID]);
    expect(db.store.get("trip_sessions/trip")?.canonicalStatus).toBe("active");
    expect(
      db.store.get(
        `trip_sessions/trip/activity_events/coppa-left-family_membership_ended-${PARENT}`
      )
    ).toMatchObject({
      payload: { participantId: PARENT, leaveReason: CHILD_TRIP_LEAVE_REASON_FAMILY_EXIT },
    });
  });

  it("ends the trip when the ex-member owns it — the owner cannot merely be pulled", async () => {
    seedTrip(db, { id: "owned", owner: PARENT, members: [KID], openGameId: "g1" });
    commitMembershipExit(db, PARENT);

    const result = await sweepLiveTripsAfterFamilyMembershipExit(asFirestore(db), PARENT);

    expect(result.endedSessionCount).toBe(1);
    expect(db.store.get("trip_sessions/owned")).toMatchObject({
      canonicalStatus: "ended",
      canonicalEndedBy: PARENT,
    });
    expect(db.store.get("trip_sessions/owned/games/g1")?.endedAt).toBeTruthy();
  });

  it("removes the CHILD when the membership that ended was the child's own", async () => {
    seedTrip(db, { id: "trip", owner: PARENT, members: [KID, AUNT] });
    commitMembershipExit(db, KID);

    const result = await sweepLiveTripsAfterFamilyMembershipExit(asFirestore(db), KID);

    // No family left ⇒ every multi-party roster holding them is illegal (FR-28 in trip terms).
    expect(result.removedFromSessionCount).toBe(1);
    expect(rosterIds(db, "trip")).toEqual([AUNT, PARENT]);
    expect(
      db.store.get(
        `trip_sessions/trip/activity_events/coppa-left-family_membership_ended-${KID}`
      )
    ).toBeTruthy();
  });

  it("leaves an adults-only live trip alone", async () => {
    seedTrip(db, { id: "adults", owner: AUNT, members: [PARENT, STRANGER] });
    commitMembershipExit(db, PARENT);

    const result = await sweepLiveTripsAfterFamilyMembershipExit(asFirestore(db), PARENT);

    expect(result).toEqual({
      scannedLiveSessionCount: 1,
      removedFromSessionCount: 0,
      endedSessionCount: 0,
    });
    expect(rosterIds(db, "adults")).toEqual([AUNT, PARENT, STRANGER]);
  });

  it("does not touch a live trip the ex-member is no longer on", async () => {
    seedTrip(db, { id: "left", owner: AUNT, members: [KID] });
    // A discoverable footprint without a roster row: they were kicked earlier.
    db.seed("trip_sessions/left/activity_events/old-find", {
      sessionId: "left",
      kind: "region_found",
      actorId: PARENT,
      payload: { participantId: PARENT, regionId: "CA", gameInstanceId: "g1" },
    });
    commitMembershipExit(db, PARENT);

    const result = await sweepLiveTripsAfterFamilyMembershipExit(asFirestore(db), PARENT);

    expect(result.scannedLiveSessionCount).toBe(0);
    expect(rosterIds(db, "left")).toEqual([AUNT, KID]);
  });
});

// ---------------------------------------------------------------------------
// Hook: the flag-set follow-on block
// ---------------------------------------------------------------------------

describe("applyChildProtectionsAfterFlagSet runs the FR-69(a) sweep", () => {
  it("sweeps live trips alongside the search, invite and friend-edge follow-ons", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    seedTrip(db, { id: "mixed", owner: PARENT, members: [KID, STRANGER] });

    const result = await applyChildProtectionsAfterFlagSet(
      asFirestore(db),
      {
        childUserId: KID,
        familyMemberIds: [PARENT, AUNT, KID],
        childUserData: db.store.get(`users/${KID}`)!,
      },
      { clearSearchIndexes: async () => undefined }
    );

    expect(result.tripSweep).toEqual({
      scannedLiveSessionCount: 1,
      removedFromSessionCount: 1,
      endedSessionCount: 0,
    });
    expect(rosterIds(db, "mixed")).toEqual([PARENT, STRANGER]);
  });
});
