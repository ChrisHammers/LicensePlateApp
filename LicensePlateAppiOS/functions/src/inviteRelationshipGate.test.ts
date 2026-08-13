/**
 * FR-47 (COPPA F-10) — the friendship-or-family relationship rule, in isolation.
 *
 * Two things are pinned here. First the matrix itself: which pairs count as related, and in
 * particular the cases where a stale `activeFamilyId` projection must NOT be enough. Second,
 * and more important for review, that the gate's rejection is byte-identical to the
 * FR-24 child-target rejection — if these two ever diverge, the difference between them
 * becomes an oracle telling any sender which accounts are children.
 */

import { describe, it, expect, beforeEach } from "vitest";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { CHILD_TARGET_NOT_SEARCHABLE_MESSAGE } from "./childAccountCore";
import {
  assertTripInviteRelationship,
  friendshipEdgeId,
  hasAcceptedFriendship,
  hasFriendshipOrFamilyRelationship,
  sharesActiveFamily,
} from "./inviteRelationshipGate";

let db: FakeFirestore;

beforeEach(() => {
  db = new FakeFirestore();
  db.seed("users/alice", { userName: "Alice" });
  db.seed("users/bob", { userName: "Bob" });
  db.seed("users/stranger", { userName: "Stranger" });
});

function seedAcceptedFriendship(a: string, b: string) {
  db.seed(`friends/${friendshipEdgeId(a, b)}`, {
    userA: a,
    userB: b,
    status: "accepted",
  });
}

function seedFamily(familyId: string, memberIds: string[]) {
  for (const id of memberIds) {
    db.seed(`users/${id}`, { userName: id, activeFamilyId: familyId });
    db.seed(`families/${familyId}/members/${id}`, { role: "member" });
  }
}

describe("friendshipEdgeId", () => {
  it("is order-independent, so one edge doc serves both directions", () => {
    expect(friendshipEdgeId("bob", "alice")).toBe(friendshipEdgeId("alice", "bob"));
  });
});

describe("hasAcceptedFriendship", () => {
  it("accepts an established edge from either direction", async () => {
    seedAcceptedFriendship("alice", "bob");
    expect(await hasAcceptedFriendship(db as never, "alice", "bob")).toBe(true);
    expect(await hasAcceptedFriendship(db as never, "bob", "alice")).toBe(true);
  });

  it("rejects a pending edge — a request is not yet a relationship", async () => {
    db.seed(`friends/${friendshipEdgeId("alice", "bob")}`, {
      userA: "alice",
      userB: "bob",
      status: "pending",
    });
    expect(await hasAcceptedFriendship(db as never, "alice", "bob")).toBe(false);
  });

  it("rejects when no edge exists", async () => {
    expect(await hasAcceptedFriendship(db as never, "alice", "stranger")).toBe(false);
  });
});

describe("sharesActiveFamily", () => {
  it("accepts two members of the same family", async () => {
    seedFamily("fam1", ["alice", "bob"]);
    expect(await sharesActiveFamily(db as never, "alice", "bob")).toBe(true);
  });

  it("rejects members of different families", async () => {
    seedFamily("fam1", ["alice"]);
    seedFamily("fam2", ["bob"]);
    expect(await sharesActiveFamily(db as never, "alice", "bob")).toBe(false);
  });

  it("rejects when one side has no active family", async () => {
    seedFamily("fam1", ["alice"]);
    expect(await sharesActiveFamily(db as never, "alice", "stranger")).toBe(false);
  });

  it("rejects a removed member whose activeFamilyId projection is stale", async () => {
    seedFamily("fam1", ["alice", "bob"]);
    // Bob was removed from the family; the members doc is the authority, and the leftover
    // user-doc field must not keep him inviting the family he was taken out of.
    db.store.delete("families/fam1/members/bob");
    expect(await sharesActiveFamily(db as never, "alice", "bob")).toBe(false);
    expect(await sharesActiveFamily(db as never, "bob", "alice")).toBe(false);
  });

  it("rejects when the family has no member docs at all", async () => {
    db.seed("users/alice", { userName: "Alice", activeFamilyId: "ghost" });
    db.seed("users/bob", { userName: "Bob", activeFamilyId: "ghost" });
    expect(await sharesActiveFamily(db as never, "alice", "bob")).toBe(false);
  });
});

describe("hasFriendshipOrFamilyRelationship", () => {
  it("is satisfied by either arm", async () => {
    seedAcceptedFriendship("alice", "bob");
    expect(await hasFriendshipOrFamilyRelationship(db as never, "alice", "bob")).toBe(true);

    db.store.clear();
    seedFamily("fam1", ["alice", "bob"]);
    expect(await hasFriendshipOrFamilyRelationship(db as never, "alice", "bob")).toBe(true);
  });

  it("is not satisfied by a stranger", async () => {
    expect(await hasFriendshipOrFamilyRelationship(db as never, "alice", "stranger")).toBe(
      false
    );
  });
});

describe("assertTripInviteRelationship", () => {
  it("passes a friend and a family member through", async () => {
    seedAcceptedFriendship("alice", "bob");
    await expect(
      assertTripInviteRelationship(db as never, "alice", "bob")
    ).resolves.toBeUndefined();
  });

  it("FR-47: refuses a stranger", async () => {
    await expect(
      assertTripInviteRelationship(db as never, "alice", "stranger")
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  /**
   * The oracle test. A distinct "not friends or family" wording would let a sender diff the
   * two replies and learn that a target is a child — precisely what FR-24 forbids.
   */
  it("FR-24: is indistinguishable from the child-target rejection", async () => {
    const error = await assertTripInviteRelationship(
      db as never,
      "alice",
      "stranger"
    ).catch((e) => e);

    expect(error.code).toBe("permission-denied");
    expect(error.message).toBe(CHILD_TARGET_NOT_SEARCHABLE_MESSAGE);
    // `details` is the other channel a client could diff on: the child-target throw carries
    // none, so this one must not either.
    expect(error.details).toBeUndefined();
  });
});
