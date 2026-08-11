/**
 * FR-14 / FR-24 (COPPA F-5b) — the `friends.ts` wiring, run against the REAL callables with
 * `firebase-admin` replaced by a `FakeFirestore`.
 *
 * The acceptance cases are the point of this file. `sendFriendInvite` is not the only way an
 * `invites` row of type "friend" comes into existence — `redeemShareCode` mints one too, and
 * FR-24 requires children to keep calling it. So the edge-creating step is gated as well,
 * and these tests pin the two routes that would otherwise produce a child friend edge.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({ db: undefined as any }));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ toMillis: () => ms }),
    fromDate: (date: Date) => ({ toMillis: () => date.getTime() }),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { respondToFriendInvite, sendFriendInvite } from "./friends";
import {
  CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
} from "./childAccountCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

function send(fromUserId: string, toUserId: string) {
  return (sendFriendInvite as unknown as Runnable).run(
    { toUserId },
    context(fromUserId)
  );
}

function respond(inviteId: string, uid: string, response: string) {
  return (respondToFriendInvite as unknown as Runnable).run(
    { inviteId, response },
    context(uid)
  );
}

function friendEdges(): string[] {
  return db().docPathsMatching((path) => path.startsWith("friends/"));
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  db().seed("users/adult", { userName: "Grown" });
  db().seed("users/stranger", { userName: "Stranger" });
  db().seed("users/famkid", {
    userName: "FamKid",
    isChildAccount: true,
    activeFamilyId: "fam1",
  });
  db().seed("users/lonekid", { userName: "LoneKid", isChildAccount: true });
});

describe("FR-14: sendFriendInvite and children", () => {
  it("rejects a child target with the verbatim privacy-opt-out wording", async () => {
    for (const target of ["famkid", "lonekid"]) {
      await expect(send("adult", target)).rejects.toMatchObject({
        code: "permission-denied",
        message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
      });
    }
    expect(db().docPathsMatching((path) => path.startsWith("invites/"))).toEqual([]);
  });

  it("FR-24: rejects a child sender, consented or not", async () => {
    for (const sender of ["famkid", "lonekid"]) {
      await expect(send(sender, "adult")).rejects.toMatchObject({
        code: "permission-denied",
        message: CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
        details: { reason: "child_account" },
      });
    }
  });

  it("regression: adult to adult still works", async () => {
    const result = (await send("adult", "stranger")) as { inviteId: string };
    expect(db().store.get(`invites/${result.inviteId}`)).toMatchObject({
      type: "friend",
      fromUserId: "adult",
      toUserId: "stranger",
      status: "pending",
    });
  });
});

describe("FR-14: accepting cannot create a child friend edge", () => {
  it("blocks the share-code route — a friend code redeemed BY a child", async () => {
    // Exactly the row `redeemShareCode` writes: creator -> redeemer.
    db().seed("invites/viaCode", {
      type: "friend",
      fromUserId: "stranger",
      toUserId: "famkid",
      status: "pending",
      method: "code",
    });

    await expect(respond("viaCode", "famkid", "accept")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
    expect(friendEdges()).toEqual([]);
    expect(db().store.get("invites/viaCode")).toMatchObject({ status: "pending" });
  });

  it("blocks the share-code route — a code the child created before being flagged", async () => {
    db().seed("invites/viaKidCode", {
      type: "friend",
      fromUserId: "famkid",
      toUserId: "stranger",
      status: "pending",
      method: "code",
    });

    await expect(respond("viaKidCode", "stranger", "accept")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(friendEdges()).toEqual([]);
  });

  it("blocks a stale in-family invite that predates the flag (FR-36 spares those)", async () => {
    db().seed("invites/inFamily", {
      type: "friend",
      fromUserId: "adult",
      toUserId: "famkid",
      status: "pending",
      method: "search",
    });

    await expect(respond("inFamily", "famkid", "accept")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(friendEdges()).toEqual([]);
  });

  it("never blocks a DECLINE — refusing contact is always protective", async () => {
    db().seed("invites/viaCode", {
      type: "friend",
      fromUserId: "stranger",
      toUserId: "famkid",
      status: "pending",
      method: "code",
    });

    await expect(respond("viaCode", "famkid", "decline")).resolves.toMatchObject({
      success: true,
    });
    expect(db().store.get("invites/viaCode")).toMatchObject({ status: "declined" });
    expect(friendEdges()).toEqual([]);
  });

  it("regression: an adult pair still forms an edge and bumps both friendCounts", async () => {
    db().seed("invites/adultPair", {
      type: "friend",
      fromUserId: "adult",
      toUserId: "stranger",
      status: "pending",
      method: "search",
    });

    await expect(respond("adultPair", "stranger", "accept")).resolves.toMatchObject({
      success: true,
    });
    expect(friendEdges()).toEqual(["friends/adult_stranger"]);
    expect(db().store.get("users/adult")).toMatchObject({ friendCount: 1 });
    expect(db().store.get("users/stranger")).toMatchObject({ friendCount: 1 });
  });
});
