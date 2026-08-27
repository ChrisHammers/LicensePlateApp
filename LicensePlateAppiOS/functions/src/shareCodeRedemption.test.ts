/**
 * FR-67 (COPPA F-23) — `redeemShareCode` / `createShareCode`, run against the REAL callables
 * with `firebase-admin` replaced by a `FakeFirestore` (same shape as `inviteHardening.test.ts`).
 *
 * Four properties are pinned here, and the last two are the ones a reviewer has to trust:
 *
 *  1. THROTTLE — 10 redemptions per uid per hour, and the not-found path spends budget too.
 *     A brute-force search over the 6-character code space lives entirely on "not found"; a
 *     limiter that skipped it would be decorative.
 *  2. TYPE CHECK — a friend code fed to the join-a-family screen (and vice versa) is refused,
 *     and a child may not redeem a friend code at all. Redemption used to mint the
 *     stranger→child friend invite and leave it to be blocked at accept.
 *  3. INDISTINGUISHABILITY (FR-24) — those two refusals are byte-identical to each other and
 *     to the child-target rejection. A share code is a bearer token: if "you are a child"
 *     and "wrong code type" read differently, handing one friend code around and diffing the
 *     replies classifies accounts as children. Same oracle FR-24 closes elsewhere, rebuilt
 *     from the other side.
 *  4. THE EXIT STAYS OPEN — a child can still redeem a FAMILY code, and a child refused on a
 *     friend code spends NO budget, so they cannot be locked out of the family code that is
 *     their actual route to consent. That is the FR-24/FR-26 designated exit.
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
  // Raw millis, not a Timestamp-shaped object: `FakeFirestore` JSON-clones every write, so
  // a `{ toMillis() }` object would arrive back as `{}`. The production readers go through
  // `timestampToMillis`, which accepts millis directly.
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { createShareCode, redeemShareCode } from "./shareCodes";
import { CHILD_TARGET_NOT_SEARCHABLE_MESSAGE } from "./childAccountCore";
import { assertTripInviteRelationship } from "./inviteRelationshipGate";
import {
  INVITE_RATE_LIMITED_MESSAGE,
  INVITE_RATE_LIMIT_COLLECTION,
  SHARE_REDEEM_MAX_PER_WINDOW,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

function redeem(uid: string, code: string, expectedType?: string) {
  return (redeemShareCode as unknown as Runnable).run(
    { code, ...(expectedType === undefined ? {} : { expectedType }) },
    context(uid)
  );
}

function mintCode(uid: string, type: string, familyId?: string) {
  return (createShareCode as unknown as Runnable).run(
    { type, ...(familyId ? { familyId } : {}) },
    context(uid)
  );
}

/**
 * Seed a live code directly. `FakeFirestore` JSON-clones, so a Firestore `Timestamp` object
 * would lose its methods — the callable's tolerant `timestampToMillis` read accepts raw
 * millis, which is what survives the clone.
 */
function seedCode(
  id: string,
  fields: { code: string; type: string; createdBy: string; familyId?: string }
) {
  db().seed(`share_codes/${id}`, {
    ...fields,
    expiresAt: Date.now() + 15 * 60 * 1000,
    isRevoked: false,
  });
}

function redeemCounter(uid: string) {
  return db().store.get(
    `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("share_redeem", uid)}`
  );
}

function invitePaths(): string[] {
  return db().docPathsMatching((path) => path.startsWith("invites/"));
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;

  db().seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });
  db().seed("users/outsider", { userName: "Outsider" });
  db().seed("users/kid", { userName: "Kid", isChildAccount: true });

  db().seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
  db().seed("families/fam1/members/parent", { role: "creator" });

  seedCode("famcode", { code: "FAM111", type: "family", createdBy: "parent", familyId: "fam1" });
  seedCode("friendcode", { code: "FRD222", type: "friend", createdBy: "parent" });
});

afterEach(() => {
  vi.useRealTimers();
});

// ---------------------------------------------------------------------------
// FR-67 — throttle
// ---------------------------------------------------------------------------

describe("FR-67: redeemShareCode is rate limited", () => {
  it("allows the configured number of attempts and refuses the next one", async () => {
    for (let i = 0; i < SHARE_REDEEM_MAX_PER_WINDOW; i += 1) {
      await expect(redeem("outsider", "NOPE00", "family")).rejects.toMatchObject({
        code: "not-found",
      });
    }
    expect(redeemCounter("outsider")?.count).toBe(SHARE_REDEEM_MAX_PER_WINDOW);

    await expect(redeem("outsider", "NOPE00", "family")).rejects.toMatchObject({
      code: "resource-exhausted",
      message: INVITE_RATE_LIMITED_MESSAGE,
    });
  });

  /**
   * The load-bearing half. Brute-forcing a code produces "not found" every time; if that
   * path were free, scoping the read rule would have moved the enumeration surface rather
   * than closing it.
   */
  it("spends budget on the not-found path, which is where brute force lives", async () => {
    await expect(redeem("outsider", "GUESS1", "family")).rejects.toMatchObject({
      code: "not-found",
    });
    expect(redeemCounter("outsider")?.count).toBe(1);
  });

  it("spends budget on a successful redemption too", async () => {
    await redeem("outsider", "FAM111", "family");
    expect(redeemCounter("outsider")?.count).toBe(1);
  });

  it("counts per redeemer, not globally", async () => {
    await expect(redeem("outsider", "GUESS1", "family")).rejects.toMatchObject({
      code: "not-found",
    });
    expect(redeemCounter("outsider")?.count).toBe(1);
    expect(redeemCounter("kid")).toBeUndefined();
  });

  it("refuses a limit-exhausted caller before touching the code at all", async () => {
    for (let i = 0; i < SHARE_REDEEM_MAX_PER_WINDOW; i += 1) {
      await expect(redeem("outsider", "NOPE00", "family")).rejects.toMatchObject({
        code: "not-found",
      });
    }
    // A valid code presented over budget is still refused, and mints nothing.
    await expect(redeem("outsider", "FAM111", "family")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(invitePaths()).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// FR-67 — type check
// ---------------------------------------------------------------------------

describe("FR-67: share codes are type-checked against the redeeming surface", () => {
  it("redeems a family code on the family surface", async () => {
    const result = (await redeem("outsider", "FAM111", "family")) as {
      inviteId: string;
      type: string;
      familyId: string;
    };
    expect(result.type).toBe("family");
    expect(result.familyId).toBe("fam1");
    expect(invitePaths()).toHaveLength(1);
  });

  it("redeems a friend code on the friend surface", async () => {
    const result = (await redeem("outsider", "FRD222", "friend")) as { type: string };
    expect(result.type).toBe("friend");
  });

  it("refuses a friend code presented to the family surface", async () => {
    await expect(redeem("outsider", "FRD222", "family")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(invitePaths()).toEqual([]);
  });

  it("refuses a family code presented to the friend surface", async () => {
    await expect(redeem("outsider", "FAM111", "friend")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(invitePaths()).toEqual([]);
  });

  it("requires expectedType, so the check cannot be skipped by omitting it", async () => {
    await expect(redeem("outsider", "FRD222")).rejects.toMatchObject({
      code: "invalid-argument",
    });
    await expect(redeem("outsider", "FRD222", "whatever")).rejects.toMatchObject({
      code: "invalid-argument",
    });
    expect(invitePaths()).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// FR-67 — children
// ---------------------------------------------------------------------------

describe("FR-67: a child may not redeem a friend code", () => {
  it("refuses the child, and mints no stranger-to-child friend invite", async () => {
    await expect(redeem("kid", "FRD222", "friend")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(invitePaths()).toEqual([]);
  });

  /** FR-24/FR-26: redemption is a designated exit to consent and must stay open. */
  it("REGRESSION: a child can still redeem a FAMILY code", async () => {
    const result = (await redeem("kid", "FAM111", "family")) as { familyId: string };
    expect(result.familyId).toBe("fam1");
    expect(invitePaths()).toHaveLength(1);
  });

  /**
   * Child checks run BEFORE the budget. Otherwise a child could exhaust their hourly
   * allowance on friend codes and be locked out of the family code that is their route back
   * into consented play — the "unrecoverable protected state" direction of §2.4.
   */
  it("spends no budget refusing a child, so the exit stays reachable", async () => {
    for (let i = 0; i < SHARE_REDEEM_MAX_PER_WINDOW + 5; i += 1) {
      await expect(redeem("kid", "FRD222", "friend")).rejects.toMatchObject({
        code: "permission-denied",
      });
    }
    expect(redeemCounter("kid")).toBeUndefined();

    const result = (await redeem("kid", "FAM111", "family")) as { familyId: string };
    expect(result.familyId).toBe("fam1");
  });
});

// ---------------------------------------------------------------------------
// FR-24 — indistinguishability, pinned field by field
// ---------------------------------------------------------------------------

describe("FR-24: the new redemption rejections are indistinguishable", () => {
  it("child-on-friend-code and wrong-code-type are byte-identical", async () => {
    const childError = await redeem("kid", "FRD222", "friend").catch((e) => e);
    const typeError = await redeem("outsider", "FRD222", "family").catch((e) => e);

    expect(childError.code).toBe(typeError.code);
    expect(childError.message).toBe(typeError.message);
    expect(childError.details).toBe(typeError.details);
  });

  it("both match the established child-target rejection exactly", async () => {
    const reference = await assertTripInviteRelationship(
      db() as never,
      "outsider",
      "parent"
    ).catch((e) => e);

    for (const error of [
      await redeem("kid", "FRD222", "friend").catch((e) => e),
      await redeem("outsider", "FRD222", "family").catch((e) => e),
      await redeem("outsider", "FAM111", "friend").catch((e) => e),
    ]) {
      expect(error.code).toBe("permission-denied");
      expect(error.message).toBe(CHILD_TARGET_NOT_SEARCHABLE_MESSAGE);
      expect(error.message).toBe(reference.message);
      // `details` is the same channel by another name — a `reason` here would leak
      // exactly what the shared wording exists to hide.
      expect(error.details).toBeUndefined();
    }
  });

  it("an adult and a child presenting the same friend code to the family surface agree", async () => {
    // The realistic probe: hand one code to two people and diff the replies.
    const adultError = await redeem("outsider", "FRD222", "family").catch((e) => e);
    const childError = await redeem("kid", "FRD222", "family").catch((e) => e);
    expect(adultError.code).toBe(childError.code);
    expect(adultError.message).toBe(childError.message);
    expect(adultError.details).toBe(childError.details);
    // ...and neither spent budget, so the counter cannot be used as a side channel either.
    expect(redeemCounter("outsider")).toBeUndefined();
    expect(redeemCounter("kid")).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// FR-66(d) — createShareCode must belong to the family it names
// ---------------------------------------------------------------------------

describe("FR-66(d): createShareCode is bound to the caller's own family", () => {
  it("lets a member mint a code for their family", async () => {
    const result = (await mintCode("parent", "family", "fam1")) as { code: string };
    expect(result.code).toHaveLength(6);
  });

  it("refuses a non-member minting a code for a family they merely named", async () => {
    // `activeFamilyId` is readable on peer user docs, so familyIds are harvestable — this
    // was an adult-reachable forgery, not a child-specific one.
    await expect(mintCode("outsider", "family", "fam1")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(db().docPathsMatching((p) => p.startsWith("share_codes/auto"))).toEqual([]);
  });

  it("still refuses a child outright (FR-24, unchanged)", async () => {
    db().seed("families/fam1/members/kid", { role: "scout", isChild: true });
    await expect(mintCode("kid", "family", "fam1")).rejects.toMatchObject({
      code: "permission-denied",
    });
  });

  it("leaves friend codes (no familyId) alone", async () => {
    const result = (await mintCode("outsider", "friend")) as { code: string };
    expect(result.code).toHaveLength(6);
  });
});

// ---------------------------------------------------------------------------
// FR-86 extended to invites (device pass 2026-08-26) — the invitee's identity is
// stamped onto the invite doc at redemption, because the captain's "Waiting for
// response" row renders the invitee and FR-12 denies the captain the users/{uid}
// read. Same pinned two-field pair as the pending row (§312.5(c)(1)).
// ---------------------------------------------------------------------------

describe("FR-86: redemption stamps the invitee onto the family invite", () => {
  it("stamps userName and avatarId from the redeemer's profile", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
    });

    const { inviteId } = (await redeem("kid", "FAM111", "family")) as {
      inviteId: string;
    };
    const invite = db().store.get(`invites/${inviteId}`)!;
    expect(invite.userName).toBe("Speedy");
    expect(invite.avatarId).toBe("scout_otter");
  });

  it("carries NO contact field — exhaustive keys, same boundary as the pending row", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      email: "kid@example.com",
      phoneNumber: "+15555550123",
      fcmToken: "device-token",
      searchableEmail: "kid@example.com",
    });

    const { inviteId } = (await redeem("kid", "FAM111", "family")) as {
      inviteId: string;
    };
    const invite = db().store.get(`invites/${inviteId}`)!;
    expect(Object.keys(invite).sort()).toEqual(
      [
        "avatarId",
        "codeId",
        "createdAt",
        "expiresAt",
        "familyId",
        "familyName",
        "fromUserId",
        "method",
        "status",
        "toUserId",
        "type",
        "userName",
      ].sort()
    );
  });

  it("re-stamps current values on the F-44 reuse-refresh path", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
    });

    const first = (await redeem("kid", "FAM111", "family")) as { inviteId: string };

    db().seed("users/kid", {
      ...db().store.get("users/kid")!,
      userName: "Speedy2",
      avatarId: "navigator_raccoon",
    });

    const second = (await redeem("kid", "FAM111", "family")) as { inviteId: string };
    expect(second.inviteId).toBe(first.inviteId);
    expect(invitePaths()).toHaveLength(1);

    const invite = db().store.get(`invites/${first.inviteId}`)!;
    expect(invite.userName).toBe("Speedy2");
    expect(invite.avatarId).toBe("navigator_raccoon");
  });

  it("omits absent fields so the client keeps its Pending User fallback", async () => {
    db().seed("users/kid", { isChildAccount: true });

    const { inviteId } = (await redeem("kid", "FAM111", "family")) as {
      inviteId: string;
    };
    const invite = db().store.get(`invites/${inviteId}`)!;
    expect("userName" in invite).toBe(false);
    expect("avatarId" in invite).toBe(false);
  });

  it("does not stamp friend invites — no read, no fields", async () => {
    const { inviteId } = (await redeem("outsider", "FRD222", "friend")) as {
      inviteId: string;
    };
    const invite = db().store.get(`invites/${inviteId}`)!;
    expect("userName" in invite).toBe(false);
    expect("avatarId" in invite).toBe(false);
  });
});
