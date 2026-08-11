/**
 * FR-13 / FR-24 / FR-38 (COPPA F-5b) — the `tripInvites.ts` wiring, run against the REAL
 * callables (`Runnable.run` is the raw handler in firebase-functions v1) with
 * `firebase-admin` replaced by a `FakeFirestore`.
 *
 * The rule itself is exhaustively covered in `tripChildParticipation.test.ts`; what this
 * file pins is the part a reviewer has to trust for privacy reasons — WHICH rejection each
 * case produces:
 *   - a child TARGET is refused with the verbatim privacy-opt-out wording, so a sender can
 *     never use trip invites as a child-detector;
 *   - a child already ON the roster (including a child sender) gets the explicit
 *     family-only reason, which discloses nothing the actor does not already know.
 * Plus FR-13's new `assertRegisteredAccount`, and that a decline is never blocked.
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
import { respondToTripInvite, sendTripInvite } from "./tripInvites";
import {
  CHILD_FAMILY_ONLY_TRIP_MESSAGE,
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
} from "./childAccountCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string, provider = "password"): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: provider } } } };
}

function send(data: Record<string, unknown>, uid: string, provider?: string) {
  return (sendTripInvite as unknown as Runnable).run(data, context(uid, provider));
}

function respond(data: Record<string, unknown>, uid: string) {
  return (respondToTripInvite as unknown as Runnable).run(data, context(uid));
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;

  db().seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });
  db().seed("users/kid", {
    userName: "Kid",
    isChildAccount: true,
    activeFamilyId: "fam1",
  });
  db().seed("families/fam1/members/parent", { role: "creator" });
  db().seed("families/fam1/members/kid", { role: "scout", isChild: true });

  db().seed("users/stranger", { userName: "Stranger" });

  db().seed("trip_sessions/s1", { name: "Trip", createdBy: "parent" });
  db().seed("trip_sessions/s1/members/parent", { role: "owner" });
});

const BASE = { tripSessionId: "s1", tripName: "Trip" };

describe("FR-13: sendTripInvite requires a registered account", () => {
  it("rejects anonymous senders (previously accepted a bare context.auth)", async () => {
    await expect(
      send({ ...BASE, toUserId: "stranger" }, "anon", "anonymous")
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: expect.stringMatching(/registered account/i),
    });
  });

  it("still rejects unauthenticated callers", async () => {
    await expect(
      (sendTripInvite as unknown as Runnable).run(
        { ...BASE, toUserId: "stranger" },
        {}
      )
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("FR-13/FR-38: child as the invite target", () => {
  it("refuses a stranger with the verbatim privacy-opt-out wording (non-disclosing)", async () => {
    db().seed("trip_sessions/s1/members/stranger", { role: "member" });
    await expect(send({ ...BASE, toUserId: "kid" }, "stranger")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
    expect(db().docPathsMatching((path) => path.startsWith("trip_invites/"))).toEqual([]);
  });

  it("refuses a family sender when a non-family participant is already aboard", async () => {
    db().seed("trip_sessions/s1/members/stranger", { role: "member" });
    await expect(send({ ...BASE, toUserId: "kid" }, "parent")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
  });

  it("allows a family sender inviting the child into an all-family trip", async () => {
    const result = (await send({ ...BASE, toUserId: "kid" }, "parent")) as {
      inviteId: string;
    };
    expect(result.inviteId).toBeTruthy();
    expect(db().store.get(`trip_invites/${result.inviteId}`)).toMatchObject({
      toUserId: "kid",
      status: "pending",
    });
  });
});

describe("FR-38: the other direction, and the child as sender", () => {
  beforeEach(() => {
    db().seed("trip_sessions/s1/members/kid", { role: "member" });
  });

  it("refuses pulling a non-family user into a child-containing trip, explicitly", async () => {
    await expect(
      send({ ...BASE, toUserId: "stranger" }, "parent")
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: CHILD_FAMILY_ONLY_TRIP_MESSAGE,
    });
  });

  it("FR-24: refuses a child sender inviting outside their family, explicitly", async () => {
    await expect(
      send({ ...BASE, toUserId: "stranger" }, "kid")
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: CHILD_FAMILY_ONLY_TRIP_MESSAGE,
    });
  });
});

describe("FR-38: accept-path re-verification", () => {
  beforeEach(() => {
    db().seed("trip_invites/inv1", {
      tripSessionId: "s1",
      tripName: "Trip",
      fromUserId: "parent",
      toUserId: "stranger",
      status: "pending",
      method: "search",
    });
  });

  it("rejects acceptance once a child has joined the trip", async () => {
    db().seed("trip_sessions/s1/members/kid", { role: "member" });
    await expect(
      respond({ inviteId: "inv1", response: "accept" }, "stranger")
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: CHILD_FAMILY_ONLY_TRIP_MESSAGE,
    });
    // The invite is left pending rather than silently consumed.
    expect(db().store.get("trip_invites/inv1")).toMatchObject({ status: "pending" });
    expect(db().store.has("trip_sessions/s1/members/stranger")).toBe(false);
  });

  it("never blocks a DECLINE — refusing is always safe", async () => {
    db().seed("trip_sessions/s1/members/kid", { role: "member" });
    await expect(
      respond({ inviteId: "inv1", response: "decline" }, "stranger")
    ).resolves.toMatchObject({ success: true });
    expect(db().store.get("trip_invites/inv1")).toMatchObject({ status: "declined" });
  });
});
