/**
 * FR-15 / FR-24 (COPPA F-5b) — the `family.ts` wiring, run against the REAL callables with
 * `firebase-admin` replaced by a `FakeFirestore`.
 *
 * What the guard unit tests cannot show, and this file pins:
 *  - FR-15 fires on the `search` method too, not just email/phone (the pre-existing privacy
 *    gate only ran for contact modalities);
 *  - it fires BEFORE `canAddMemberToFamily`, so a child in another family gets the generic
 *    "not searchable" answer instead of the family-revealing "already in another active
 *    family" one;
 *  - an UNCONSENTED child is still invitable — the path back to consented play.
 *
 * FR-71 (F-27, COPPA v3) extends this file: `sendFamilyInvite` gains the same
 * `consumeInviteRateLimit` primitive `sendTripInvite`/`sendFriendInvite` already carry
 * (`inviteHardening.test.ts`), scope `family_invite`. Pinned here, same shape as that file:
 * exhaustion, per-sender isolation, offline-replay idempotence, and FR-24 precedence (the
 * child-caller gate above ran first and must keep deciding even when budget remains).
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
import { createFamily, sendFamilyInvite } from "./family";
import {
  CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
} from "./childAccountCore";
import {
  FAMILY_INVITE_MAX_PER_WINDOW,
  INVITE_RATE_LIMITED_MESSAGE,
  INVITE_RATE_LIMITED_REASON,
  INVITE_RATE_LIMIT_COLLECTION,
  INVITE_RATE_LIMIT_WINDOW_MS,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

function invite(uid: string, toUserId: string, method?: string) {
  return (sendFamilyInvite as unknown as Runnable).run(
    { toUserId, familyId: "fam1", ...(method ? { method } : {}) },
    context(uid)
  );
}

function familyInvitePaths(): string[] {
  return db().docPathsMatching(
    (path, data) => path.startsWith("invites/") && (data as { type?: string }).type === "family"
  );
}

function counter(scope: "family_invite", uid: string) {
  return db().store.get(
    `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId(scope, uid)}`
  );
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;

  db().seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
  db().seed("families/fam1/members/parent", { role: "creator" });
  db().seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });

  // A child already managed by another family.
  db().seed("users/otherkid", {
    userName: "OtherKid",
    isChildAccount: true,
    activeFamilyId: "fam2",
    privacy: { emailSearchable: true, phoneSearchable: true },
  });
  // A provisional / post-revocation child with no family.
  db().seed("users/lonekid", { userName: "LoneKid", isChildAccount: true });
  db().seed("users/adult", { userName: "Grown" });
});

afterEach(() => {
  vi.useRealTimers();
});

describe("FR-15: family invites aimed at a child", () => {
  it("rejects a child who already has a family — on the default `search` method", async () => {
    await expect(invite("parent", "otherkid")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
  });

  it("rejects on the email and phone methods too", async () => {
    for (const method of ["email", "phone"]) {
      await expect(invite("parent", "otherkid", method)).rejects.toMatchObject({
        code: "permission-denied",
        message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
      });
    }
  });

  it("answers before canAddMemberToFamily, so the other family is never revealed", async () => {
    // The adult twin of this case still gets the family-revealing legacy message; the
    // child must not, which is exactly why FR-15 is checked first.
    db().seed("users/otheradult", { userName: "OA", activeFamilyId: "fam2" });
    await expect(invite("parent", "otheradult")).rejects.toMatchObject({
      message: expect.stringMatching(/already in another active family/i),
    });
    await expect(invite("parent", "otherkid")).rejects.toMatchObject({
      message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
    });
  });

  it("still allows inviting an UNCONSENTED child into a family", async () => {
    const result = (await invite("parent", "lonekid")) as { inviteId: string };
    expect(db().store.get(`invites/${result.inviteId}`)).toMatchObject({
      type: "family",
      toUserId: "lonekid",
      familyId: "fam1",
      status: "pending",
    });
  });

  it("regression: an ordinary adult invite still works", async () => {
    const result = (await invite("parent", "adult")) as { inviteId: string };
    expect(result.inviteId).toBeTruthy();
  });

  /**
   * FR-86 extended to invites (2026-08-26): the invitee's identity rides the invite doc so
   * the family's "Waiting for response" row can render a child whose users/{uid} the
   * members cannot read (FR-12). `targetUserData` is already in hand for the FR-15 gate —
   * the stamp adds no read.
   */
  it("stamps the invitee's userName and avatarId onto the invite doc", async () => {
    db().seed("users/lonekid", {
      userName: "LoneKid",
      avatarId: "scout_otter",
      isChildAccount: true,
    });
    const result = (await invite("parent", "lonekid")) as { inviteId: string };
    expect(db().store.get(`invites/${result.inviteId}`)).toMatchObject({
      userName: "LoneKid",
      avatarId: "scout_otter",
    });
  });
});

describe("FR-24: children cannot send family invites or found families", () => {
  beforeEach(() => {
    db().seed("families/fam1/members/famkid", { role: "scout", isChild: true });
    db().seed("users/famkid", {
      userName: "FamKid",
      isChildAccount: true,
      activeFamilyId: "fam1",
    });
  });

  it("rejects a child sender before any role check", async () => {
    await expect(invite("famkid", "adult")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
      details: { reason: "child_account" },
    });
  });

  /**
   * FR-71 (F-27) precedence, same shape as `inviteHardening.test.ts`'s equivalent for
   * `sendTripInvite`: the FR-24 child-caller guard runs BEFORE `consumeInviteRateLimit`, so
   * a child's own rate-limit state can never leak through the reply. If the ordering ever
   * regressed, an over-budget child would see `resource-exhausted` instead of the FR-24
   * shape — itself a tell, since it implies the caller had spendable budget to begin with.
   */
  it("the child-caller rejection still wins even when the sender is OVER their rate limit", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("family_invite", "famkid")}`,
      {
        userId: "famkid",
        scope: "family_invite",
        windowStartAtMs: Date.now(),
        count: FAMILY_INVITE_MAX_PER_WINDOW,
      }
    );
    await expect(invite("famkid", "adult")).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
    });
  });

  it("rejects createFamily for an orphaned child (no self-managed consent)", async () => {
    await expect(
      (createFamily as unknown as Runnable).run(
        { name: "Kid's Crew" },
        context("lonekid")
      )
    ).rejects.toMatchObject({
      code: "permission-denied",
      details: { reason: "child_account" },
    });
    expect(db().docPathsMatching((path) => path.startsWith("families/auto"))).toEqual([]);
  });

  it("regression: an adult can still create a family", async () => {
    const result = (await (createFamily as unknown as Runnable).run(
      { name: "Grown Crew" },
      context("adult")
    )) as { familyId: string };
    expect(db().store.get(`families/${result.familyId}`)).toMatchObject({
      name: "Grown Crew",
      creatorId: "adult",
    });
  });
});

// ---------------------------------------------------------------------------
// FR-71 (F-27): sendFamilyInvite rate limiting
// ---------------------------------------------------------------------------

describe("FR-71: sendFamilyInvite rate limiting", () => {
  function seedTargets(count: number): string[] {
    const ids: string[] = [];
    for (let i = 0; i < count; i += 1) {
      const id = `famtarget${String(i).padStart(3, "0")}`;
      db().seed(`users/${id}`, { userName: id });
      ids.push(id);
    }
    return ids;
  }

  it("allows exactly the configured number of invites, then refuses", async () => {
    const targets = seedTargets(FAMILY_INVITE_MAX_PER_WINDOW + 1);

    for (let i = 0; i < FAMILY_INVITE_MAX_PER_WINDOW; i += 1) {
      await expect(invite("parent", targets[i])).resolves.toMatchObject({
        inviteId: expect.any(String),
      });
    }
    expect(counter("family_invite", "parent")).toMatchObject({
      count: FAMILY_INVITE_MAX_PER_WINDOW,
    });

    const error = await invite(
      "parent",
      targets[FAMILY_INVITE_MAX_PER_WINDOW]
    ).catch((e) => e);
    expect(error.code).toBe("resource-exhausted");
    expect(error.message).toBe(INVITE_RATE_LIMITED_MESSAGE);
    expect(error.details).toMatchObject({ reason: INVITE_RATE_LIMITED_REASON });

    // The refused invite was not created, and the counter did not creep past the limit.
    expect(familyInvitePaths()).toHaveLength(FAMILY_INVITE_MAX_PER_WINDOW);
    expect(counter("family_invite", "parent")).toMatchObject({
      count: FAMILY_INVITE_MAX_PER_WINDOW,
    });
  });

  it("is per-sender: exhausting one captain does not block a captain of another family", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("family_invite", "parent")}`,
      {
        userId: "parent",
        scope: "family_invite",
        windowStartAtMs: Date.now(),
        count: FAMILY_INVITE_MAX_PER_WINDOW,
      }
    );
    await expect(invite("parent", "adult")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    db().seed("families/fam2", { name: "Fam2", creatorId: "otherparent", status: "active" });
    db().seed("families/fam2/members/otherparent", { role: "creator" });
    db().seed("users/otherparent", { userName: "OtherParent", activeFamilyId: "fam2" });
    await expect(
      (sendFamilyInvite as unknown as Runnable).run(
        { toUserId: "adult", familyId: "fam2" },
        context("otherparent")
      )
    ).resolves.toMatchObject({ inviteId: expect.any(String) });
  });

  it("spends a budget scoped to family_invite only — no cross-scope doc is touched", async () => {
    const result = (await invite("parent", "adult")) as { inviteId: string };
    expect(result.inviteId).toBeTruthy();
    expect(counter("family_invite", "parent")).toMatchObject({ count: 1 });
    expect(
      db().store.has(`${INVITE_RATE_LIMIT_COLLECTION}/friend_invite__parent`)
    ).toBe(false);
    expect(
      db().store.has(`${INVITE_RATE_LIMIT_COLLECTION}/trip_invite__parent`)
    ).toBe(false);
  });

  it("recovers once the window lapses", async () => {
    vi.useFakeTimers();
    const start = new Date("2026-08-13T12:00:00Z");
    vi.setSystemTime(start);

    const targets = seedTargets(FAMILY_INVITE_MAX_PER_WINDOW + 1);
    for (let i = 0; i < FAMILY_INVITE_MAX_PER_WINDOW; i += 1) {
      await invite("parent", targets[i]);
    }
    await expect(
      invite("parent", targets[FAMILY_INVITE_MAX_PER_WINDOW])
    ).rejects.toMatchObject({ code: "resource-exhausted" });

    vi.setSystemTime(new Date(start.getTime() + INVITE_RATE_LIMIT_WINDOW_MS));
    await expect(
      invite("parent", targets[FAMILY_INVITE_MAX_PER_WINDOW])
    ).resolves.toMatchObject({ inviteId: expect.any(String) });
    expect(counter("family_invite", "parent")).toMatchObject({ count: 1 });
  });

  it("a replayed invite short-circuits and does not spend budget twice (offline retry)", async () => {
    const first = (await invite("parent", "adult")) as { inviteId: string };
    expect(counter("family_invite", "parent")).toMatchObject({ count: 1 });

    const replay = await invite("parent", "adult").catch((e) => e);
    expect(replay.code).toBe("already-exists");
    expect(counter("family_invite", "parent")).toMatchObject({ count: 1 });
    expect(familyInvitePaths()).toHaveLength(1);
    expect(first.inviteId).toBeTruthy();
  });
});
