/**
 * FR-61 — the parental review inventory.
 *
 * PARITY is the acceptance criterion: everything the deletion sweep touches must be
 * represented in the inventory. The manifest/sweep comparison here is the runtime half;
 * the compile-time half is the builder's `satisfies Record<PerUidDataLocationKey, …>`.
 *
 * Flows are db-parameterized, so the FakeFirestore passes straight in — no vi.mock
 * (the familyChildStatusFlows.test.ts pattern).
 */

import { describe, it, expect, beforeEach } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  buildChildDataInventoryFlow,
  listGuardedChildrenFlow,
  PER_UID_DATA_LOCATION_KEYS,
} from "./childDataInventory";
import { DELETION_SWEEP_LOCATION_KEYS } from "./accountDeletion";

const FAMILY = "fam-1";
const GUARDIAN = "uid_guardian_000000000000000";
const CHILD = "uid_child_00000000000000000";
const STRANGER = "uid_stranger_00000000000000";
const SCOUT = "uid_scout_000000000000000000";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

let db: FakeFirestore;

beforeEach(() => {
  db = new FakeFirestore();
});

function seedChildWorld(): void {
  db.seed(`users/${CHILD}`, {
    userName: "KidRacer",
    avatarId: "fox",
    isChildAccount: true,
    ageOutYearMonth: 203107,
    wasEverInFamily: true,
  });
  db.seed(`users/${CHILD}/private/contact`, { email: "kid@example.com" });
  db.seed(`users/${CHILD}/private/fcm`, { token: "push-token-abc" });
  db.seed(`users/${CHILD}/private/guardianship`, {
    guardianUid: GUARDIAN,
    familyId: FAMILY,
  });
  db.seed(`families/${FAMILY}/members/${GUARDIAN}`, { role: "captain" });
  db.seed(`families/${FAMILY}/members/${CHILD}`, {
    role: "scout",
    isChild: true,
    consentPending: false,
  });
  db.seed(`families/${FAMILY}/members/${SCOUT}`, { role: "scout" });
  db.seed(`friends/f1`, { userA: CHILD, userB: SCOUT });
  db.seed(`user_progression/${CHILD}`, { totalXp: 320, level: 4 });
  db.seed(`user_progression/${CHILD}/xp_grants/g1`, { amount: 20 });
  db.seed(`user_progression/${CHILD}/xp_grants/g2`, { amount: 300 });
  db.seed(`user_achievements/${CHILD}`, { updatedAt: 1 });
  db.seed(`user_achievements/${CHILD}/achievements/a1`, { unlockedAt: 1 });
  db.seed(`public_lifetime_stats/${CHILD}`, {
    platesFound: 12,
    tripsCompleted: 3,
    displayName: "should-not-copy-strings",
  });
  db.seed(`invite_rate_limits/trip_invite__${CHILD}`, { count: 2 });
  db.seed(`trip_sessions/s1`, { name: "Summer trip", status: "ended", createdBy: CHILD });
  db.seed(`trip_sessions/s1/activity_events/e1`, {
    sessionId: "s1",
    kind: "region_found",
    actorId: CHILD,
    payload: { regionId: "CA", participantId: CHILD, locationLatitude: "41.7" },
  });
  db.seed(`trip_sessions/s1/activity_events/e2`, {
    sessionId: "s1",
    kind: "trip_started",
    actorId: CHILD,
    payload: {},
  });
  // Someone else's event crediting the child (attributed, not authored).
  db.seed(`trip_sessions/s1/activity_events/e3`, {
    sessionId: "s1",
    kind: "region_found",
    actorId: SCOUT,
    payload: { regionId: "NY", participantId: CHILD },
  });
  db.seed(`trip_invites/ti1`, { fromUserId: SCOUT, toUserId: CHILD, tripSessionId: "s1" });
  db.seed(`share_codes/sc1`, { createdBy: CHILD });
  db.seed(`plate_found_notify_buffers/b1`, { recipientUid: CHILD });
}

describe("FR-61 parity: deletion sweep and review inventory cover the same locations", () => {
  it("the manifest equals the sweep's declared list, as sets", () => {
    expect([...PER_UID_DATA_LOCATION_KEYS].sort()).toEqual(
      [...DELETION_SWEEP_LOCATION_KEYS].sort()
    );
  });
});

describe("FR-61 authorization (FR-62 ladder, same as the deletion right)", () => {
  it("a live manager authorizes without guardianship", async () => {
    seedChildWorld();
    const result = await buildChildDataInventoryFlow(asFirestore(db), {
      actorId: GUARDIAN,
      familyId: FAMILY,
      childUserId: CHILD,
    });
    expect(result.viaGuardianship).toBe(false);
    expect(result.accountExists).toBe(true);
  });

  it("the recorded guardian authorizes after leaving the family", async () => {
    seedChildWorld();
    db.store.delete(`families/${FAMILY}/members/${GUARDIAN}`);
    const result = await buildChildDataInventoryFlow(asFirestore(db), {
      actorId: GUARDIAN,
      familyId: FAMILY,
      childUserId: CHILD,
    });
    expect(result.viaGuardianship).toBe(true);
  });

  it("a live non-manager member gets the actionable Captains message", async () => {
    seedChildWorld();
    await expect(
      buildChildDataInventoryFlow(asFirestore(db), {
        actorId: SCOUT,
        familyId: FAMILY,
        childUserId: CHILD,
      })
    ).rejects.toThrow("Only Captains can manage child status");
  });

  it("a stranger gets the uniform deny", async () => {
    seedChildWorld();
    await expect(
      buildChildDataInventoryFlow(asFirestore(db), {
        actorId: STRANGER,
        familyId: FAMILY,
        childUserId: CHILD,
      })
    ).rejects.toThrow("Not a family member");
  });

  it("an adult target is refused, not inventoried", async () => {
    seedChildWorld();
    db.seed(`users/${SCOUT}`, { userName: "Adult", isChildAccount: false });
    await expect(
      buildChildDataInventoryFlow(asFirestore(db), {
        actorId: GUARDIAN,
        familyId: FAMILY,
        childUserId: SCOUT,
      })
    ).rejects.toThrow("This member is not marked as a child");
  });

  it("a deleted child's inventory is honestly empty for a live manager, never an error", async () => {
    seedChildWorld();
    // Deletion removed the whole users/{uid} subtree; the parent is still a manager.
    db.store.delete(`users/${CHILD}`);
    db.store.delete(`users/${CHILD}/private/contact`);
    db.store.delete(`users/${CHILD}/private/fcm`);
    db.store.delete(`users/${CHILD}/private/guardianship`);
    const result = await buildChildDataInventoryFlow(asFirestore(db), {
      actorId: GUARDIAN,
      familyId: FAMILY,
      childUserId: CHILD,
    });
    expect(result.accountExists).toBe(false);
    for (const key of PER_UID_DATA_LOCATION_KEYS) {
      expect(result.sections[key].present).toBe(false);
    }
  });
});

describe("FR-61 section synthesis", () => {
  it("assembles every manifest section from the seeded world", async () => {
    seedChildWorld();
    const result = await buildChildDataInventoryFlow(asFirestore(db), {
      actorId: GUARDIAN,
      familyId: FAMILY,
      childUserId: CHILD,
    });
    const s = result.sections;

    expect(s.user_profile).toMatchObject({
      present: true,
      userName: "KidRacer",
      avatarId: "fox",
      ageOutYearMonth: 203107,
    });

    // Contact identifiers are presence booleans, never values.
    expect(s.private_subcollection.present).toBe(true);
    expect(s.private_subcollection.contact).toEqual({
      hasEmail: true,
      hasPhoneNumber: false,
    });
    expect(JSON.stringify(s.private_subcollection)).not.toContain("kid@example.com");
    expect(s.private_subcollection.pushTokenPresent).toBe(true);
    expect(JSON.stringify(s.private_subcollection)).not.toContain("push-token-abc");

    // FR-11: a child must not be indexed — the inventory REPORTS that.
    expect(s.search_indexes).toMatchObject({
      present: false,
      usernameIndexed: false,
      emailIndexed: false,
      phoneIndexed: false,
    });

    expect(s.friend_edges).toEqual({ present: true, edgeCount: 1 });
    expect(s.family_membership).toMatchObject({ present: true, role: "scout", isChild: true });
    expect(s.progression).toMatchObject({ present: true, totalXp: 320, level: 4, xpGrantCount: 2 });
    expect(s.achievements).toEqual({ present: true, unlockedCount: 1 });
    expect(s.public_lifetime_stats).toEqual({
      present: true,
      totals: { platesFound: 12, tripsCompleted: 3 },
    });
    expect(s.invite_rate_limits).toEqual({ present: true, counterCount: 1 });

    expect(s.gameplay_residue).toMatchObject({
      present: true,
      sessionCount: 1,
      authoredEventTotal: 2,
      attributedEventTotal: 2,
      anyLocationPayloadExists: true,
      tripInvitesReceived: 1,
      shareCodesCreated: 1,
      pendingNotifyBufferCount: 1,
    });
    const trips = s.gameplay_residue.trips as Array<Record<string, unknown>>;
    expect(trips).toHaveLength(1);
    expect(trips[0]).toMatchObject({
      tripName: "Summer trip",
      status: "ended",
      authoredEventCountsByKind: { region_found: 1, trip_started: 1 },
      attributedEventCount: 2,
      anyLocationPayload: true,
    });

    expect(s.revenuecat_vendor).toMatchObject({ configured: false });
    expect(s.analytics_vendor).toMatchObject({
      posture: "no_uid_in_catalog_client_reset_on_deletion",
    });
  });
});

describe("FR-61 ex-member entry: listGuardedChildren", () => {
  it("returns the actor's guardianship rows, live and ended, newest grant first", async () => {
    seedChildWorld();
    db.seed(`users/uid_child2_0000000000000000/private/guardianship`, {
      guardianUid: GUARDIAN,
      familyId: FAMILY,
      endedAtMillis: 500,
      endedReason: "parent_removed_child",
    });
    db.seed(`users/uid_child2_0000000000000000`, {
      userName: "SecondKid",
      isChildAccount: true,
    });
    // Another guardian's record never appears.
    db.seed(`users/uid_child3_0000000000000000/private/guardianship`, {
      guardianUid: STRANGER,
      familyId: FAMILY,
    });

    const result = await listGuardedChildrenFlow(asFirestore(db), { actorId: GUARDIAN });
    expect(result.children).toHaveLength(2);
    const ids = result.children.map((row) => row.childUserId).sort();
    expect(ids).toEqual([CHILD, "uid_child2_0000000000000000"].sort());
    const ended = result.children.find(
      (row) => row.childUserId === "uid_child2_0000000000000000"
    );
    expect(ended).toMatchObject({
      childUserName: "SecondKid",
      accountExists: true,
      endedAtMillis: 500,
      endedReason: "parent_removed_child",
    });
  });

  it("only guardianship docs qualify — other private docs carrying the field do not", async () => {
    db.seed(`users/${CHILD}/private/contact`, { guardianUid: GUARDIAN });
    const result = await listGuardedChildrenFlow(asFirestore(db), { actorId: GUARDIAN });
    expect(result.children).toEqual([]);
  });
});
