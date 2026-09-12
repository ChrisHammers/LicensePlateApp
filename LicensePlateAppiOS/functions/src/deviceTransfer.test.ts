/**
 * FR-84 (F-41) — parent-initiated device transfer, run against the REAL callables with
 * `firebase-admin` replaced by a `FakeFirestore` plus a spy `auth()` (same shape as
 * `shareCodeRedemption.test.ts`, extended because this feature is the first thing in the
 * codebase to touch Firebase Auth's admin surface).
 *
 * Six properties are pinned, and the last three are the ones a reviewer has to trust:
 *
 *  1. WHO MAY MINT — the FR-62 guardianship ladder and nothing else: a live creator/captain,
 *     or the recorded guardian of that child. A stranger, a plain member, a captain of a
 *     DIFFERENT family, and any child caller are all refused.
 *  2. WHAT MAY BE TARGETED — FR-84's own words, "a child currently consented in that family":
 *     flag + `activeFamilyId` + a server-written member doc, re-checked at redemption so a
 *     revocation between mint and redemption voids a live code.
 *  3. SINGLE USE, SHORT TTL, THROTTLED — the second redemption loses, an expired or revoked
 *     code is dead, and the `share_redeem` budget is spent even on the not-found path,
 *     because "not found" is the reply a brute-force search over the code space lives on.
 *  4. INDISTINGUISHABILITY (FR-24, applied harder than `redeemShareCode` applies it) — unknown
 *     code, expired, revoked, already-redeemed and target-no-longer-eligible are ONE reply,
 *     byte for byte, with no `details`. A transfer code names a specific child, so a caller
 *     who could diff those replies could learn a named child's consent state from the shape
 *     of a rejection.
 *  5. TRANSFER IS NOT A CONSENT EVENT (FR-84 future-item (iv)) — the guardianship record is
 *     untouched, no `AUDIT_PARENTAL_CONSENT_*` row appears, and the retention markers
 *     (`childDeclaredAt`, `ageOutYearMonth`) are not restamped. This is asserted as an
 *     invariant rather than left as an omission, because "we didn't write that" is exactly
 *     the kind of fact a later refactor breaks silently.
 *  6. THE CUSTOM TOKEN DOES NOT PROMOTE THE CHILD — a `custom` provider session is
 *     uncredentialed like an anonymous one, so a transferred child cannot mint the next
 *     transfer code (or anything else gated on registration).
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  createCustomToken: undefined as any,
  revokeRefreshTokens: undefined as any,
  deleteUser: undefined as any,
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion: values }),
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
  };
  const auth = () => ({
    createCustomToken: holder.createCustomToken,
    revokeRefreshTokens: holder.revokeRefreshTokens,
    deleteUser: holder.deleteUser,
  });
  return { default: { firestore, auth }, firestore, auth };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { createDeviceTransferCode, redeemDeviceTransferCode } from "./deviceTransfer";
import {
  AUDIT_CHILD_DEVICE_TRANSFER_ISSUED,
  AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED,
  DEVICE_TRANSFER_CODE_COLLECTION,
  DEVICE_TRANSFER_CODE_TTL_MS,
  DEVICE_TRANSFER_SIGNING_FAILED_MESSAGE,
  DEVICE_TRANSFER_UNAVAILABLE_MESSAGE,
} from "./deviceTransferCore";
import { CHILD_CONSENT_EVENT_TYPES } from "./childAccountCore";
import {
  INVITE_RATE_LIMIT_COLLECTION,
  SHARE_REDEEM_MAX_PER_WINDOW,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string, provider = "password"): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: provider } } } };
}

function mint(actor: string, childUserId: string, familyId: string, provider = "password") {
  return (createDeviceTransferCode as unknown as Runnable).run(
    { childUserId, familyId },
    context(actor, provider)
  );
}

function redeem(uid: string, code: string, provider = "password") {
  return (redeemDeviceTransferCode as unknown as Runnable).run(
    { code },
    context(uid, provider)
  );
}

function codeDocs(): { path: string; data: Record<string, unknown> }[] {
  return db()
    .docPathsMatching((path) => path.startsWith(`${DEVICE_TRANSFER_CODE_COLLECTION}/`))
    .map((path) => ({ path, data: db().store.get(path)! }));
}

function auditRows(): Record<string, unknown>[] {
  return db()
    .docPathsMatching((path) => path.startsWith("audit_logs/"))
    .map((path) => db().store.get(path)!);
}

function auditRowsOfType(eventType: string): Record<string, unknown>[] {
  return auditRows().filter((row) => row.eventType === eventType);
}

/** Seed a live, claimable code directly, bypassing the mint callable's authorization. */
function seedCode(
  id: string,
  fields: {
    code: string;
    childUserId: string;
    familyId: string;
    createdBy: string;
    expiresAtMillis?: number;
    isRevoked?: boolean;
    redeemedAtMillis?: number;
  }
): void {
  db().seed(`${DEVICE_TRANSFER_CODE_COLLECTION}/${id}`, {
    isRevoked: false,
    expiresAtMillis: Date.now() + DEVICE_TRANSFER_CODE_TTL_MS,
    ...fields,
  });
}

async function refusal(promise: Promise<unknown>): Promise<any> {
  try {
    await promise;
    throw new Error("expected a rejection");
  } catch (error) {
    return error;
  }
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.createCustomToken = vi.fn(async (uid: string) => `custom-token-for-${uid}`);
  holder.revokeRefreshTokens = vi.fn(async () => undefined);
  holder.deleteUser = vi.fn(async () => undefined);

  // fam1: parent (creator), captain, plainAdult (member), kid (consented child).
  db().seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });
  db().seed("users/captain", { userName: "Captain", activeFamilyId: "fam1" });
  db().seed("users/plainAdult", { userName: "Plain", activeFamilyId: "fam1" });
  db().seed("users/stranger", { userName: "Stranger" });
  db().seed("users/kid", {
    userName: "Kid",
    isChildAccount: true,
    activeFamilyId: "fam1",
    childDeclaredAt: 1000,
    ageOutYearMonth: 203703,
  });
  db().seed("users/kid/private/guardianship", {
    guardianUid: "parent",
    familyId: "fam1",
    method: "email_plus",
    grantedAt: 1000,
  });

  db().seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
  db().seed("families/fam1/members/parent", { role: "creator" });
  db().seed("families/fam1/members/captain", { role: "captain" });
  db().seed("families/fam1/members/plainAdult", { role: "member" });
  db().seed("families/fam1/members/kid", { role: "member", isChild: true });

  // fam2: an unrelated family with its own creator.
  db().seed("users/otherParent", { userName: "Other", activeFamilyId: "fam2" });
  db().seed("families/fam2", { name: "Other Fam", creatorId: "otherParent", status: "active" });
  db().seed("families/fam2/members/otherParent", { role: "creator" });

  // The new device's provisional session: declared child, no family (FR-60 mint→bind→declare).
  db().seed("users/newDevice", { isChildAccount: true });
});

// ---------------------------------------------------------------------------
// 1. Who may mint — the FR-62 ladder
// ---------------------------------------------------------------------------

describe("FR-84 mint authorization", () => {
  it("lets the family creator mint for a consented child in their family", async () => {
    const result = (await mint("parent", "kid", "fam1")) as any;
    expect(result.code).toMatch(/^[A-Z0-9]{6}$/);
    expect(result.childUserId).toBe("kid");
    expect(codeDocs()).toHaveLength(1);
    expect(codeDocs()[0].data).toMatchObject({
      childUserId: "kid",
      familyId: "fam1",
      createdBy: "parent",
      isRevoked: false,
    });
  });

  it("lets a captain mint (CHILD_STATUS_MANAGER_ROLES, not creator-only)", async () => {
    await expect(mint("captain", "kid", "fam1")).resolves.toBeTruthy();
  });

  /**
   * FR-62: the recorded guardian keeps authority after their own membership ends. The child
   * is still a live consented member — it is the ACTOR who left — so the transfer is exactly
   * the "parent still has rights over their child's account" case FR-62 built the ladder for.
   */
  it("lets the recorded guardian mint after their own membership ended", async () => {
    db().store.delete("families/fam1/members/parent");
    await expect(mint("parent", "kid", "fam1")).resolves.toBeTruthy();
  });

  it("refuses a plain member (live member, insufficient role)", async () => {
    const error = await refusal(mint("plainAdult", "kid", "fam1"));
    expect(error.code).toBe("permission-denied");
  });

  it("refuses a stranger and a captain of another family", async () => {
    expect((await refusal(mint("stranger", "kid", "fam1"))).code).toBe("permission-denied");
    expect((await refusal(mint("otherParent", "kid", "fam1"))).code).toBe("permission-denied");
    expect(codeDocs()).toHaveLength(0);
  });

  /**
   * FR-24 / FR-66 (CB-7): role alone is not proof of adulthood anywhere else in this codebase
   * and is not here either — the "captain" authorizing a child action can be the child's own
   * second account.
   */
  it("refuses a CHILD caller even when they hold a manager role", async () => {
    db().seed("users/kidCaptain", {
      userName: "KidCaptain",
      isChildAccount: true,
      activeFamilyId: "fam1",
    });
    db().seed("families/fam1/members/kidCaptain", { role: "captain", isChild: true });
    const error = await refusal(mint("kidCaptain", "kid", "fam1"));
    expect(error.code).toBe("permission-denied");
    expect(codeDocs()).toHaveLength(0);
  });

  it("refuses an anonymous caller and a CUSTOM-TOKEN caller (no transfer chaining)", async () => {
    expect((await refusal(mint("parent", "kid", "fam1", "anonymous"))).code).toBe(
      "failed-precondition"
    );
    // FR-84's own output must not be an input to itself: a transferred child holds a custom
    // token, and `isUncredentialedCaller` is what stops that reading as a registered account.
    expect((await refusal(mint("kid", "kid", "fam1", "custom"))).code).toBe(
      "failed-precondition"
    );
  });
});

// ---------------------------------------------------------------------------
// 2. What may be targeted
// ---------------------------------------------------------------------------

describe("FR-84 target eligibility", () => {
  it("refuses a target who is not flagged as a child", async () => {
    const error = await refusal(mint("parent", "plainAdult", "fam1"));
    expect(error.code).toBe("failed-precondition");
  });

  it("refuses a child whose activeFamilyId names a different family", async () => {
    db().seed("users/kid", { userName: "Kid", isChildAccount: true, activeFamilyId: "fam2" });
    expect((await refusal(mint("parent", "kid", "fam1"))).code).toBe("failed-precondition");
  });

  /**
   * The member doc is the authority, `activeFamilyId` only the index: it is client-writable
   * on one's own user doc, so a revoked child who forged the field back must still be refused.
   */
  it("refuses a revoked child who forged activeFamilyId back (no member doc)", async () => {
    db().store.delete("families/fam1/members/kid");
    expect((await refusal(mint("parent", "kid", "fam1"))).code).toBe("failed-precondition");
    expect(codeDocs()).toHaveLength(0);
  });

  it("refuses a code aimed at the caller themselves", async () => {
    expect((await refusal(mint("parent", "parent", "fam1"))).code).toBe("invalid-argument");
  });
});

// ---------------------------------------------------------------------------
// 3. One live code per child
// ---------------------------------------------------------------------------

describe("FR-84 future-item (iii): one live bearer credential per child", () => {
  it("supersedes a prior live code when a second is minted", async () => {
    const first = (await mint("parent", "kid", "fam1")) as any;
    const second = (await mint("parent", "kid", "fam1")) as any;

    const rows = codeDocs();
    expect(rows).toHaveLength(2);
    const firstRow = rows.find((r) => r.data.code === first.code)!;
    const secondRow = rows.find((r) => r.data.code === second.code)!;
    expect(firstRow.data.isRevoked).toBe(true);
    expect(secondRow.data.isRevoked).toBe(false);

    const dead = await refusal(redeem("newDevice", first.code, "anonymous"));
    expect(dead.message).toBe(DEVICE_TRANSFER_UNAVAILABLE_MESSAGE);
  });

  it("does not supersede a live code belonging to a DIFFERENT child", async () => {
    db().seed("users/kid2", { userName: "Kid2", isChildAccount: true, activeFamilyId: "fam1" });
    db().seed("families/fam1/members/kid2", { role: "member", isChild: true });
    const kidCode = (await mint("parent", "kid", "fam1")) as any;
    await mint("parent", "kid2", "fam1");

    const kidRow = codeDocs().find((r) => r.data.code === kidCode.code)!;
    expect(kidRow.data.isRevoked).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 4. Redemption — happy path
// ---------------------------------------------------------------------------

describe("FR-84 redemption", () => {
  it("hands the new device a custom token for the child's EXISTING uid", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });

    const result = (await redeem("newDevice", "TRN111", "anonymous")) as any;

    expect(result.customToken).toBe("custom-token-for-kid");
    expect(result.childUserId).toBe("kid");
    expect(result.familyId).toBe("fam1");
    expect(holder.createCustomToken).toHaveBeenCalledWith("kid");
  });

  it("accepts a lowercase entry (owner device-testing tolerance, as redeemShareCode does)", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await expect(redeem("newDevice", "  trn111 ", "anonymous")).resolves.toBeTruthy();
  });

  it("invalidates the OLD device by revoking the child's refresh tokens", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");
    expect(holder.revokeRefreshTokens).toHaveBeenCalledWith("kid");
  });

  it("stamps a server-written transfer epoch on the child's user doc", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");
    const kid = db().store.get("users/kid")!;
    expect(typeof kid.deviceTransferEpochMillis).toBe("number");
    expect(kid.lastDeviceTransferAtMillis).toBe(kid.deviceTransferEpochMillis);
  });

  it("marks the code spent", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");
    const row = db().store.get(`${DEVICE_TRANSFER_CODE_COLLECTION}/c1`)!;
    expect(row.isRevoked).toBe(true);
    expect(row.redeemedByUserId).toBe("newDevice");
    expect(typeof row.redeemedAtMillis).toBe("number");
  });

  it("lets a REGISTERED adult redeem — the parent often sets the new device up themselves", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await expect(redeem("plainAdult", "TRN111")).resolves.toBeTruthy();
  });

  /** The FR-60 carve-out is what lets the new device call at all; a stranger still cannot. */
  it("refuses a plain anonymous caller who is not a declared child", async () => {
    db().seed("users/anon", { userName: "Anon" });
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    const error = await refusal(redeem("anon", "TRN111", "anonymous"));
    expect(error.code).toBe("failed-precondition");
    expect(holder.createCustomToken).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// 5. Single use, TTL, and the uniform refusal
// ---------------------------------------------------------------------------

describe("FR-84 single-use, expiry, and FR-24 indistinguishability", () => {
  it("refuses the SECOND redemption of the same code", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");

    db().seed("users/newDevice2", { isChildAccount: true });
    const error = await refusal(redeem("newDevice2", "TRN111", "anonymous"));
    expect(error.message).toBe(DEVICE_TRANSFER_UNAVAILABLE_MESSAGE);
    expect(holder.createCustomToken).toHaveBeenCalledTimes(1);
  });

  it("refuses an expired code", async () => {
    seedCode("c1", {
      code: "TRN111",
      childUserId: "kid",
      familyId: "fam1",
      createdBy: "parent",
      expiresAtMillis: Date.now() - 1,
    });
    expect((await refusal(redeem("newDevice", "TRN111", "anonymous"))).message).toBe(
      DEVICE_TRANSFER_UNAVAILABLE_MESSAGE
    );
  });

  /**
   * A revocation between mint and redemption voids a live code. Without this re-check, a
   * parent who revoked consent five minutes after minting would still have handed out a
   * working credential for the account they just restricted.
   */
  it("refuses when the target stopped being a consented member after the mint", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    db().store.delete("families/fam1/members/kid");

    const error = await refusal(redeem("newDevice", "TRN111", "anonymous"));
    expect(error.message).toBe(DEVICE_TRANSFER_UNAVAILABLE_MESSAGE);
    expect(holder.createCustomToken).not.toHaveBeenCalled();
    // The code is NOT consumed: nothing was handed over, so nothing was spent.
    expect(db().store.get(`${DEVICE_TRANSFER_CODE_COLLECTION}/c1`)!.isRevoked).toBe(false);
  });

  /**
   * The property the whole rejection design exists for. A transfer code names a specific
   * child, so if these read differently a caller could learn a named child's consent state,
   * or sift the code space, from the SHAPE of a rejection rather than its content.
   */
  it("makes every negative outcome byte-identical, with no details payload", async () => {
    seedCode("expired", {
      code: "EXP111",
      childUserId: "kid",
      familyId: "fam1",
      createdBy: "parent",
      expiresAtMillis: Date.now() - 1,
    });
    seedCode("revoked", {
      code: "REV111",
      childUserId: "kid",
      familyId: "fam1",
      createdBy: "parent",
      isRevoked: true,
    });
    seedCode("spent", {
      code: "SPN111",
      childUserId: "kid",
      familyId: "fam1",
      createdBy: "parent",
      redeemedAtMillis: Date.now() - 5,
    });
    seedCode("ineligible", {
      code: "INE111",
      childUserId: "orphanKid",
      familyId: "fam1",
      createdBy: "parent",
    });

    const errors = [];
    for (const code of ["NOSUCH", "EXP111", "REV111", "SPN111", "INE111"]) {
      errors.push(await refusal(redeem("newDevice", code, "anonymous")));
    }

    for (const error of errors) {
      expect(error.code).toBe("not-found");
      expect(error.message).toBe(DEVICE_TRANSFER_UNAVAILABLE_MESSAGE);
      expect(error.details).toBeUndefined();
    }
    expect(new Set(errors.map((e) => `${e.code}|${e.message}`)).size).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// 6. Throttle
// ---------------------------------------------------------------------------

describe("FR-84 redemption throttle (share_redeem scope, FR-67/OD-4)", () => {
  it("spends budget on the NOT-FOUND path — that is where brute force lives", async () => {
    await refusal(redeem("newDevice", "NOSUCH", "anonymous"));
    const counter = db().store.get(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("share_redeem", "newDevice")}`
    );
    expect(counter?.count).toBe(1);
  });

  it("refuses the attempt after the hourly limit", async () => {
    for (let i = 0; i < SHARE_REDEEM_MAX_PER_WINDOW; i += 1) {
      await refusal(redeem("newDevice", "NOSUCH", "anonymous"));
    }
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    const error = await refusal(redeem("newDevice", "TRN111", "anonymous"));
    expect(error.code).toBe("resource-exhausted");
    expect(holder.createCustomToken).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// 7. Residue cleanup
// ---------------------------------------------------------------------------

describe("FR-84 provisional-account residue (FR-60 / FR-77)", () => {
  it("discards the throwaway uid the new device minted just to make the call", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");

    expect(db().store.get("users/newDevice")).toBeUndefined();
    expect(holder.deleteUser).toHaveBeenCalledWith("newDevice");
  });

  it("never touches a registered adult's own account", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("plainAdult", "TRN111");

    expect(db().store.get("users/plainAdult")).toBeDefined();
    expect(holder.deleteUser).not.toHaveBeenCalled();
  });

  /**
   * The dangerous near-miss: a CONSENTED child redeeming a sibling's code. Their account is
   * live, parent-approved, and holds exactly the history FR-84 exists to preserve — deleting
   * it as "residue" would destroy the wrong child's account.
   */
  it("never deletes a CONSENTED child's account, even when they are the redeemer", async () => {
    db().seed("users/kid2", { userName: "Kid2", isChildAccount: true, activeFamilyId: "fam1" });
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });

    await redeem("kid2", "TRN111", "anonymous");

    expect(db().store.get("users/kid2")).toBeDefined();
    expect(holder.deleteUser).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// 8. Audit rows, and what a transfer must NOT be
// ---------------------------------------------------------------------------

describe("FR-84 audit rows are uid-only and are not consent events", () => {
  it("writes an ISSUED row naming only uids", async () => {
    const result = (await mint("parent", "kid", "fam1")) as any;
    const rows = auditRowsOfType(AUDIT_CHILD_DEVICE_TRANSFER_ISSUED);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ actorId: "parent", subjectType: "user", subjectId: "kid" });
    expect(rows[0].metadata).toMatchObject({
      childUserId: "kid",
      familyId: "fam1",
      actorRole: "creator",
      codeId: result.codeId,
      method: "parent_issued_code",
    });
    const values = Object.values(rows[0].metadata as Record<string, unknown>);
    expect(values.some((v) => typeof v === "string" && v.includes("@"))).toBe(false);
    expect(JSON.stringify(rows[0].metadata)).not.toContain("Kid");
  });

  it("writes a REDEEMED row naming only uids", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN111", "anonymous");

    const rows = auditRowsOfType(AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED);
    expect(rows).toHaveLength(1);
    expect(rows[0].metadata).toMatchObject({
      childUserId: "kid",
      redeemedByUserId: "newDevice",
      discardedProvisionalAccount: true,
    });
  });

  /**
   * FR-84 future-item (iv), pinned as an invariant rather than left as an omission: a
   * transferred account keeps its guardianship record (FR-62) and its retention markers
   * (FR-77). Transfer is not a consent event and must not reset either.
   */
  it("leaves guardianship, consent history and retention markers untouched", async () => {
    const guardianshipBefore = JSON.stringify(db().store.get("users/kid/private/guardianship"));
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });

    await mint("parent", "kid", "fam1");
    seedCode("c2", { code: "TRN222", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    await redeem("newDevice", "TRN222", "anonymous");

    expect(JSON.stringify(db().store.get("users/kid/private/guardianship"))).toBe(
      guardianshipBefore
    );
    const kid = db().store.get("users/kid")!;
    expect(kid.childDeclaredAt).toBe(1000);
    expect(kid.ageOutYearMonth).toBe(203703);
    expect(kid.isChildAccount).toBe(true);
    expect(kid.activeFamilyId).toBe("fam1");

    for (const row of auditRows()) {
      expect(CHILD_CONSENT_EVENT_TYPES).not.toContain(row.eventType);
    }
  });

  it("keeps the transfer event types OUT of the consent-history vocabulary", () => {
    expect(CHILD_CONSENT_EVENT_TYPES).not.toContain(AUDIT_CHILD_DEVICE_TRANSFER_ISSUED);
    expect(CHILD_CONSENT_EVENT_TYPES).not.toContain(AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED);
  });
});

// ---------------------------------------------------------------------------
// 9. The redeemer is already the target (owner device test 2026-09-10)
// ---------------------------------------------------------------------------

describe("FR-84 redeemer is already the target", () => {
  it("refuses the child who already IS the target, leaving the code live and their tokens alone", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });

    const error = await refusal(redeem("kid", "TRN111", "custom"));

    expect(error.code).toBe("not-found");
    expect(error.message).toBe(DEVICE_TRANSFER_UNAVAILABLE_MESSAGE);
    expect(holder.revokeRefreshTokens).not.toHaveBeenCalled();
    expect(holder.createCustomToken).not.toHaveBeenCalled();
    const stored = db().store.get(`${DEVICE_TRANSFER_CODE_COLLECTION}/c1`)!;
    expect(stored.redeemedAtMillis ?? null).toBeNull();
    expect(stored.isRevoked).toBe(false);

    // The genuine new device can still use the same code afterwards.
    await expect(redeem("newDevice", "TRN111", "anonymous")).resolves.toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// 10. Signing fails (runtime SA without Token Creator) — owner device test 2026-09-10
// ---------------------------------------------------------------------------

describe("FR-84 custom-token signing failure", () => {
  it("leaves the code live and the child's tokens alone, and says so as an operational error", async () => {
    seedCode("c1", { code: "TRN111", childUserId: "kid", familyId: "fam1", createdBy: "parent" });
    holder.createCustomToken = vi.fn(async () => {
      throw new Error("Permission 'iam.serviceAccounts.signBlob' denied on resource");
    });

    const error = await refusal(redeem("newDevice", "TRN111", "anonymous"));

    expect(error.code).toBe("internal");
    expect(error.message).toBe(DEVICE_TRANSFER_SIGNING_FAILED_MESSAGE);
    expect(holder.revokeRefreshTokens).not.toHaveBeenCalled();
    const stored = db().store.get(`${DEVICE_TRANSFER_CODE_COLLECTION}/c1`)!;
    expect(stored.redeemedAtMillis ?? null).toBeNull();
    expect(stored.isRevoked).toBe(false);

    // Once the server is fixed, the SAME code works.
    holder.createCustomToken = vi.fn(async (uid: string) => `custom-token-for-${uid}`);
    await expect(redeem("newDevice", "TRN111", "anonymous")).resolves.toBeTruthy();
  });
});
