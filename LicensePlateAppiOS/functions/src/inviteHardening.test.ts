/**
 * FR-47 (COPPA F-10) — the `sendTripInvite` / `sendFriendInvite` wiring, run against the
 * REAL callables with `firebase-admin` replaced by a `FakeFirestore`, in the same shape as
 * `tripInvitesChildGates.test.ts`.
 *
 * This is the acceptance file named by FR-47: stranger rejection and rate-limit
 * enforcement. It also pins the two properties a reviewer has to trust and that the unit
 * suites cannot show on their own:
 *
 *  1. PRECEDENCE — the FR-13/24/38 child rules still decide first. A child target is
 *     refused even when the sender is a family member (relationship satisfied) and well
 *     inside their budget, and a child rejection still wins when the sender is OVER their
 *     budget. Neither new gate can be used to escape a child rule.
 *  2. IDEMPOTENCE — a replayed invite (the offline-first client's retry) short-circuits on
 *     the existing pending row and does NOT spend budget a second time.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

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
import { sendTripInvite } from "./tripInvites";
import { sendFriendInvite } from "./friends";
import {
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
  CHILD_FAMILY_ONLY_TRIP_MESSAGE,
} from "./childAccountCore";
import {
  FRIEND_INVITE_MAX_PER_WINDOW,
  INVITE_RATE_LIMITED_MESSAGE,
  INVITE_RATE_LIMITED_REASON,
  INVITE_RATE_LIMIT_COLLECTION,
  INVITE_RATE_LIMIT_WINDOW_MS,
  TRIP_INVITE_MAX_PER_WINDOW,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";
import { friendshipEdgeId } from "./inviteRelationshipGate";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const BASE = { tripSessionId: "s1", tripName: "Trip" };

function sendTrip(toUserId: string, fromUserId: string) {
  return (sendTripInvite as unknown as Runnable).run(
    { ...BASE, toUserId },
    context(fromUserId)
  );
}

function sendFriend(fromUserId: string, toUserId: string) {
  return (sendFriendInvite as unknown as Runnable).run(
    { toUserId },
    context(fromUserId)
  );
}

function seedAcceptedFriendship(a: string, b: string) {
  db().seed(`friends/${friendshipEdgeId(a, b)}`, {
    userA: a,
    userB: b,
    status: "accepted",
  });
}

function tripInvitePaths(): string[] {
  return db().docPathsMatching((path) => path.startsWith("trip_invites/"));
}

function friendInvitePaths(): string[] {
  return db().docPathsMatching((path) => path.startsWith("invites/"));
}

function counter(scope: "trip_invite" | "friend_invite", uid: string) {
  return db().store.get(
    `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId(scope, uid)}`
  );
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;

  // parent + kid share fam1; friend is an accepted friend of parent; stranger is neither.
  db().seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });
  db().seed("users/kid", {
    userName: "Kid",
    isChildAccount: true,
    activeFamilyId: "fam1",
  });
  db().seed("families/fam1/members/parent", { role: "creator" });
  db().seed("families/fam1/members/kid", { role: "scout", isChild: true });

  db().seed("users/friend", { userName: "Friend" });
  seedAcceptedFriendship("parent", "friend");

  db().seed("users/stranger", { userName: "Stranger" });

  db().seed("trip_sessions/s1", { name: "Trip", createdBy: "parent" });
  db().seed("trip_sessions/s1/members/parent", { role: "owner" });
});

afterEach(() => {
  vi.useRealTimers();
});

// ---------------------------------------------------------------------------
// FR-47 acceptance: stranger rejection
// ---------------------------------------------------------------------------

describe("FR-47: sendTripInvite relationship gate", () => {
  it("rejects a stranger and writes no invite", async () => {
    await expect(sendTrip("stranger", "parent")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
    expect(tripInvitePaths()).toEqual([]);
  });

  it("allows an accepted friend", async () => {
    const result = (await sendTrip("friend", "parent")) as { inviteId: string };
    expect(db().store.get(`trip_invites/${result.inviteId}`)).toMatchObject({
      toUserId: "friend",
      status: "pending",
    });
  });

  it("allows a family member", async () => {
    const result = (await sendTrip("kid", "parent")) as { inviteId: string };
    expect(db().store.get(`trip_invites/${result.inviteId}`)).toMatchObject({
      toUserId: "kid",
    });
  });

  it("rejects once a friendship is only pending, not accepted", async () => {
    db().seed(`friends/${friendshipEdgeId("parent", "stranger")}`, {
      userA: "parent",
      userB: "stranger",
      status: "pending",
    });
    await expect(sendTrip("stranger", "parent")).rejects.toMatchObject({
      code: "permission-denied",
    });
  });

  /**
   * The oracle check at callable level: refusing a stranger who is an adult and refusing a
   * stranger who is a child must be the same reply, or trip invites become a child-detector.
   */
  it("FR-24: an adult stranger and a child stranger are refused identically", async () => {
    db().seed("users/otherkid", {
      userName: "OtherKid",
      isChildAccount: true,
      activeFamilyId: "fam2",
    });
    db().seed("families/fam2/members/otherkid", { role: "scout", isChild: true });

    const adultError = await sendTrip("stranger", "parent").catch((e) => e);
    const childError = await sendTrip("otherkid", "parent").catch((e) => e);

    expect(adultError.code).toBe(childError.code);
    expect(adultError.message).toBe(childError.message);
    expect(adultError.details).toEqual(childError.details);
  });
});

// ---------------------------------------------------------------------------
// FR-13 / FR-24 / FR-38 precedence over the new FR-47 gates
// ---------------------------------------------------------------------------

describe("FR-13/24/38 keep precedence over the FR-47 gates", () => {
  it("refuses a child target even though the sender is family AND inside their budget", async () => {
    // A non-family participant is aboard, so FR-38 forbids the child joining. The sender
    // satisfies the FR-47 relationship gate (same family) and has spent no budget.
    db().seed("trip_sessions/s1/members/stranger", { role: "member" });
    expect(counter("trip_invite", "parent")).toBeUndefined();

    await expect(sendTrip("kid", "parent")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });

    // The child rule decided, and a refusal spends nothing.
    expect(counter("trip_invite", "parent")).toBeUndefined();
    expect(tripInvitePaths()).toEqual([]);
  });

  it("FR-24: refuses a child SENDER inviting outside the family, budget untouched", async () => {
    db().seed("trip_sessions/s1/members/kid", { role: "member" });
    await expect(sendTrip("stranger", "kid")).rejects.toMatchObject({
      code: "failed-precondition",
      message: CHILD_FAMILY_ONLY_TRIP_MESSAGE,
    });
    expect(counter("trip_invite", "kid")).toBeUndefined();
  });

  it("the child rejection still wins when the sender is OVER their rate limit", async () => {
    // Exhaust the sender's budget first.
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("trip_invite", "parent")}`,
      {
        userId: "parent",
        scope: "trip_invite",
        windowStartAtMs: Date.now(),
        count: TRIP_INVITE_MAX_PER_WINDOW,
      }
    );
    db().seed("trip_sessions/s1/members/stranger", { role: "member" });

    // FR-13/24/38 runs first, so the reply is the child rejection — never
    // "resource-exhausted", which would tell the sender their budget is the only obstacle.
    await expect(sendTrip("kid", "parent")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
  });

  it("sendFriendInvite: a child target is refused without spending budget", async () => {
    await expect(sendFriend("parent", "kid")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
    expect(counter("friend_invite", "parent")).toBeUndefined();
  });

  it("sendFriendInvite: a child CALLER is refused even with budget available", async () => {
    await expect(sendFriend("kid", "stranger")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(counter("friend_invite", "kid")).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// FR-47 acceptance: rate-limit enforcement
// ---------------------------------------------------------------------------

describe("FR-47: sendTripInvite rate limiting", () => {
  function seedFriendTargets(count: number): string[] {
    const ids: string[] = [];
    for (let i = 0; i < count; i += 1) {
      const id = `pal${String(i).padStart(3, "0")}`;
      db().seed(`users/${id}`, { userName: id });
      seedAcceptedFriendship("parent", id);
      ids.push(id);
    }
    return ids;
  }

  it("allows exactly the configured number of invites, then refuses", async () => {
    const targets = seedFriendTargets(TRIP_INVITE_MAX_PER_WINDOW + 1);

    for (let i = 0; i < TRIP_INVITE_MAX_PER_WINDOW; i += 1) {
      await expect(sendTrip(targets[i], "parent")).resolves.toMatchObject({
        inviteId: expect.any(String),
      });
    }
    expect(counter("trip_invite", "parent")).toMatchObject({
      count: TRIP_INVITE_MAX_PER_WINDOW,
    });

    const error = await sendTrip(
      targets[TRIP_INVITE_MAX_PER_WINDOW],
      "parent"
    ).catch((e) => e);
    expect(error.code).toBe("resource-exhausted");
    expect(error.message).toBe(INVITE_RATE_LIMITED_MESSAGE);
    expect(error.details).toMatchObject({ reason: INVITE_RATE_LIMITED_REASON });

    // The refused invite was not created, and the counter did not creep past the limit.
    expect(tripInvitePaths()).toHaveLength(TRIP_INVITE_MAX_PER_WINDOW);
    expect(counter("trip_invite", "parent")).toMatchObject({
      count: TRIP_INVITE_MAX_PER_WINDOW,
    });
  });

  it("is per-sender: exhausting one user does not block another", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("trip_invite", "parent")}`,
      {
        userId: "parent",
        scope: "trip_invite",
        windowStartAtMs: Date.now(),
        count: TRIP_INVITE_MAX_PER_WINDOW,
      }
    );
    await expect(sendTrip("friend", "parent")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    // `friend` owns a different trip and invites their own friend.
    db().seed("trip_sessions/s2", { name: "Other", createdBy: "friend" });
    db().seed("trip_sessions/s2/members/friend", { role: "owner" });
    await expect(
      (sendTripInvite as unknown as Runnable).run(
        { tripSessionId: "s2", tripName: "Other", toUserId: "parent" },
        context("friend")
      )
    ).resolves.toMatchObject({ inviteId: expect.any(String) });
  });

  it("recovers once the window lapses", async () => {
    vi.useFakeTimers();
    const start = new Date("2026-08-13T12:00:00Z");
    vi.setSystemTime(start);

    const targets = seedFriendTargets(TRIP_INVITE_MAX_PER_WINDOW + 1);
    for (let i = 0; i < TRIP_INVITE_MAX_PER_WINDOW; i += 1) {
      await sendTrip(targets[i], "parent");
    }
    await expect(
      sendTrip(targets[TRIP_INVITE_MAX_PER_WINDOW], "parent")
    ).rejects.toMatchObject({ code: "resource-exhausted" });

    vi.setSystemTime(new Date(start.getTime() + INVITE_RATE_LIMIT_WINDOW_MS));
    await expect(
      sendTrip(targets[TRIP_INVITE_MAX_PER_WINDOW], "parent")
    ).resolves.toMatchObject({ inviteId: expect.any(String) });
    expect(counter("trip_invite", "parent")).toMatchObject({ count: 1 });
  });

  it("a replayed invite short-circuits and does not spend budget twice (offline retry)", async () => {
    const first = (await sendTrip("friend", "parent")) as { inviteId: string };
    expect(counter("trip_invite", "parent")).toMatchObject({ count: 1 });

    const replay = (await sendTrip("friend", "parent")) as { inviteId: string };
    expect(replay.inviteId).toBe(first.inviteId);
    expect(counter("trip_invite", "parent")).toMatchObject({ count: 1 });
    expect(tripInvitePaths()).toHaveLength(1);
  });
});

describe("FR-47: sendFriendInvite rate limiting", () => {
  it("allows exactly the configured number of invites, then refuses", async () => {
    const targets: string[] = [];
    for (let i = 0; i < FRIEND_INVITE_MAX_PER_WINDOW + 1; i += 1) {
      const id = `cand${String(i).padStart(3, "0")}`;
      db().seed(`users/${id}`, { userName: id });
      targets.push(id);
    }

    for (let i = 0; i < FRIEND_INVITE_MAX_PER_WINDOW; i += 1) {
      await expect(sendFriend("parent", targets[i])).resolves.toMatchObject({
        inviteId: expect.any(String),
      });
    }

    const error = await sendFriend(
      "parent",
      targets[FRIEND_INVITE_MAX_PER_WINDOW]
    ).catch((e) => e);
    expect(error.code).toBe("resource-exhausted");
    expect(error.message).toBe(INVITE_RATE_LIMITED_MESSAGE);
    expect(friendInvitePaths()).toHaveLength(FRIEND_INVITE_MAX_PER_WINDOW);
  });

  it("uses a budget separate from trip invites", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("friend_invite", "parent")}`,
      {
        userId: "parent",
        scope: "friend_invite",
        windowStartAtMs: Date.now(),
        count: FRIEND_INVITE_MAX_PER_WINDOW,
      }
    );
    await expect(sendFriend("parent", "stranger")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    // The trip-invite budget is untouched.
    await expect(sendTrip("friend", "parent")).resolves.toMatchObject({
      inviteId: expect.any(String),
    });
  });

  it("a duplicate pending invite short-circuits without spending budget", async () => {
    await sendFriend("parent", "stranger");
    expect(counter("friend_invite", "parent")).toMatchObject({ count: 1 });

    await expect(sendFriend("parent", "stranger")).rejects.toMatchObject({
      code: "already-exists",
    });
    expect(counter("friend_invite", "parent")).toMatchObject({ count: 1 });
  });
});
