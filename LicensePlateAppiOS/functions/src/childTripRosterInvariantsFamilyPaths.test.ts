/**
 * FR-69(b) at its real call sites — `removeFamilyMember` and `inactivateFamily`.
 *
 * `childTripRosterInvariants.test.ts` pins the sweep itself; this file pins that the two
 * family callables actually run it, through the real callable bodies (firebase-admin mocked
 * onto `FakeFirestore`, the pattern `familyPendingRequestStamp.test.ts` established). The
 * property: after a membership exit COMMITS, no live trip is left holding a child alongside
 * someone who is no longer family to them.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  deletedAuthUsers: [] as string[],
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
    increment: (n: number) => ({ __increment__: n }),
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  const auth: any = () => ({
    deleteUser: async (uid: string) => {
      holder.deletedAuthUsers.push(uid);
    },
  });
  const messaging: any = () => ({ send: async () => "sent" });
  return { default: { firestore, auth, messaging }, firestore, auth, messaging };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { inactivateFamily, removeFamilyMember } from "./family";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const run = {
  removeFamilyMember: (uid: string, familyId: string, memberId: string) =>
    (removeFamilyMember as unknown as Runnable).run({ familyId, memberId }, context(uid)),
  inactivateFamily: (uid: string, familyId: string) =>
    (inactivateFamily as unknown as Runnable).run({ familyId }, context(uid)),
};

const PARENT = "parent";
const AUNT = "aunt";
const KID = "kid";

function seedFamilyAndTrip(tripOwner: string, tripMembers: string[]): void {
  const store = db();
  store.seed("families/fam1", { name: "Testers", creatorId: PARENT, status: "active" });
  store.seed(`families/fam1/members/${PARENT}`, { role: "creator" });
  store.seed(`families/fam1/members/${AUNT}`, { role: "captain" });
  store.seed(`families/fam1/members/${KID}`, { role: "scout", isChild: true });
  store.seed(`users/${PARENT}`, { activeFamilyId: "fam1", userName: "Parent" });
  store.seed(`users/${AUNT}`, { activeFamilyId: "fam1", userName: "Aunt" });
  store.seed(`users/${KID}`, {
    activeFamilyId: "fam1",
    userName: "KidUser",
    isChildAccount: true,
  });

  const roster = [tripOwner, ...tripMembers.filter((id) => id !== tripOwner)];
  store.seed("trip_sessions/t1", {
    name: "Road trip",
    createdBy: tripOwner,
    canonicalStatus: "active",
    canonicalParticipants: roster.map((userId) => ({
      userId,
      role: userId === tripOwner ? "owner" : "member",
      joinedAt: 1,
      leftAt: null,
      teamId: null,
    })),
  });
  for (const userId of roster) {
    store.seed(`trip_sessions/t1/members/${userId}`, {
      role: userId === tripOwner ? "owner" : "member",
      joinedAt: 1,
    });
    store.seed(`trip_sessions/t1/activity_events/join-${userId}`, {
      sessionId: "t1",
      kind: "participant_joined",
      actorId: userId,
      payload: {},
    });
  }
}

function rosterIds(): string[] {
  const prefix = "trip_sessions/t1/members/";
  return db()
    .docPathsMatching((path) => path.startsWith(prefix))
    .map((path) => path.slice(prefix.length));
}

describe("removeFamilyMember runs the FR-69(b) sweep", () => {
  beforeEach(() => {
    db().store.clear();
    db().writeCount = 0;
  });

  it("pulls the removed adult off a live trip that still holds the family's child", async () => {
    seedFamilyAndTrip(PARENT, [KID, AUNT]);

    await run.removeFamilyMember(PARENT, "fam1", AUNT);

    expect(rosterIds()).toEqual([KID, PARENT]);
    expect(
      db().store.get(
        `trip_sessions/t1/activity_events/coppa-left-family_membership_ended-${AUNT}`
      )
    ).toMatchObject({
      kind: "participant_left",
      payload: { participantId: AUNT, leaveReason: "family_membership_ended" },
    });
    // The child keeps playing with the family that is still theirs.
    expect(db().store.get("trip_sessions/t1")?.canonicalStatus).toBe("active");
  });

  it("pulls the CHILD off when it is the child's own membership that ends", async () => {
    seedFamilyAndTrip(PARENT, [KID, AUNT]);

    await run.removeFamilyMember(PARENT, "fam1", KID);

    expect(rosterIds()).toEqual([AUNT, PARENT]);
    expect(
      db().store.get(
        `trip_sessions/t1/activity_events/coppa-left-family_membership_ended-${KID}`
      )
    ).toBeTruthy();
    // FR-6 is untouched: the revocation record is still written.
    const revoked = db()
      .docPathsMatching(
        (path, data) =>
          path.startsWith("audit_logs/") &&
          data.eventType === "AUDIT_PARENTAL_CONSENT_REVOKED"
      );
    expect(revoked).toHaveLength(1);
  });

  it("leaves the trip alone when the departure breaks nothing", async () => {
    // No child on this roster: the ex-member is nobody's problem.
    seedFamilyAndTrip(PARENT, [AUNT]);

    await run.removeFamilyMember(PARENT, "fam1", AUNT);

    expect(rosterIds()).toEqual([AUNT, PARENT]);
  });
});

describe("inactivateFamily runs the FR-69(b) sweep", () => {
  beforeEach(() => {
    db().store.clear();
    db().writeCount = 0;
  });

  it("takes the child off the live trip — their family no longer exists", async () => {
    seedFamilyAndTrip(PARENT, [KID]);

    await run.inactivateFamily(PARENT, "fam1");

    // Children are swept first: once the child is off, the adults' rosters are lawful and
    // nobody else's trip is disturbed.
    expect(rosterIds()).toEqual([PARENT]);
    expect(db().store.get("trip_sessions/t1")?.canonicalStatus).toBe("active");
    expect(
      db().store.get(
        `trip_sessions/t1/activity_events/coppa-left-family_membership_ended-${KID}`
      )
    ).toBeTruthy();
  });

  it("ends the trip when the child owned it", async () => {
    seedFamilyAndTrip(KID, [PARENT]);

    await run.inactivateFamily(PARENT, "fam1");

    expect(db().store.get("trip_sessions/t1")).toMatchObject({
      canonicalStatus: "ended",
      canonicalEndedBy: KID,
    });
    expect(
      db().store.get(
        `trip_sessions/t1/activity_events/trip-ended-family_membership_ended-${KID}`
      )
    ).toMatchObject({ kind: "trip_ended" });
  });
});
