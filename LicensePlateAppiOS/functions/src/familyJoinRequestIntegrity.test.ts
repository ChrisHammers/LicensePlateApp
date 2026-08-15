/**
 * FR-66 (COPPA F-22) — join-request lineage and new-guardian seasoning, in isolation.
 *
 * These are the two server-side links that make the consent boundary unforgeable. The
 * end-to-end replay of the chain they break lives in `consentBoundaryChain.test.ts`; this
 * file pins the decisions themselves, including the cases that only matter adversarially:
 * a lineage stamp that is present but malformed, and a seasoning check whose timestamps
 * cannot be read.
 */

import { describe, it, expect, beforeEach } from "vitest";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  GUARDIAN_CLEAR_SEASONING_MESSAGE,
  GUARDIAN_CLEAR_SEASONING_WINDOW_MS,
  JOIN_REQUEST_LINEAGE_MISSING_MESSAGE,
  assertGuardianClearSeasoning,
  assertJoinRequestLineage,
  buildJoinRequestLineage,
  countCorroboratingAdults,
  evaluateGuardianClearSeasoning,
  readJoinRequestLineage,
  timestampToMillis,
} from "./familyJoinRequestIntegrity";

// ---------------------------------------------------------------------------
// FR-66(a) — lineage
// ---------------------------------------------------------------------------

describe("buildJoinRequestLineage", () => {
  it("marks a plain invite as family_invite", () => {
    expect(buildJoinRequestLineage({ inviteId: "inv1" })).toEqual({
      origin: "family_invite",
      originInviteId: "inv1",
    });
  });

  it("marks a code-derived invite as share_code and keeps the code id", () => {
    expect(buildJoinRequestLineage({ inviteId: "inv1", codeId: "code9" })).toEqual({
      origin: "share_code",
      originInviteId: "inv1",
      originCodeId: "code9",
    });
  });

  it("treats an empty or non-string codeId as no code at all", () => {
    for (const codeId of ["", null, undefined, 7, {}]) {
      expect(buildJoinRequestLineage({ inviteId: "inv1", codeId }).origin).toBe(
        "family_invite"
      );
    }
  });
});

describe("readJoinRequestLineage", () => {
  it("round-trips what buildJoinRequestLineage writes", () => {
    for (const built of [
      buildJoinRequestLineage({ inviteId: "inv1" }),
      buildJoinRequestLineage({ inviteId: "inv1", codeId: "code9" }),
    ]) {
      expect(readJoinRequestLineage({ ...built, userId: "kid" })).toEqual(built);
    }
  });

  /**
   * The adversarial half. A forged pending row would carry whatever its author felt like
   * putting there, so "has an `origin` key" can never be the test.
   */
  it("rejects absent, partial, and invented stamps", () => {
    const rejected: Array<Record<string, unknown> | undefined | null> = [
      undefined,
      null,
      {},
      { userId: "kid", status: "pending" },
      { origin: "family_invite" }, // no invite id
      { originInviteId: "inv1" }, // no origin
      { origin: "family_invite", originInviteId: "" },
      { origin: "family_invite", originInviteId: 42 },
      { origin: "self_service", originInviteId: "inv1" }, // invented origin
      { origin: "", originInviteId: "inv1" },
    ];
    for (const data of rejected) {
      expect(readJoinRequestLineage(data)).toBeNull();
    }
  });
});

describe("assertJoinRequestLineage", () => {
  it("returns the lineage for a server-minted request", () => {
    const lineage = buildJoinRequestLineage({ inviteId: "inv1", codeId: "code9" });
    expect(assertJoinRequestLineage({ ...lineage })).toEqual(lineage);
  });

  it("FR-66(a): refuses a request no invite produced", () => {
    expect(() => assertJoinRequestLineage({ userId: "kid", status: "pending" })).toThrow(
      expect.objectContaining({
        code: "failed-precondition",
        message: JOIN_REQUEST_LINEAGE_MISSING_MESSAGE,
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-66(b) — seasoning
// ---------------------------------------------------------------------------

describe("timestampToMillis", () => {
  it("reads Firestore Timestamps, Dates, and raw millis", () => {
    expect(timestampToMillis({ toMillis: () => 1234 })).toBe(1234);
    expect(timestampToMillis({ toDate: () => new Date(1234) })).toBe(1234);
    expect(timestampToMillis(new Date(1234))).toBe(1234);
    expect(timestampToMillis(1234)).toBe(1234);
  });

  it("reads an unresolved serverTimestamp sentinel as unknown, not as zero", () => {
    // The sentinel is what a request doc holds between `batch.set` and the commit landing.
    // Coercing it to 0 would make every family look infinitely old — the exact inversion
    // this gate exists to prevent.
    for (const value of ["__serverTimestamp__", undefined, null, {}, NaN, "nope"]) {
      expect(timestampToMillis(value)).toBeNull();
    }
  });
});

describe("evaluateGuardianClearSeasoning", () => {
  const DAY = 24 * 60 * 60 * 1000;
  const created = 1_700_000_000_000;

  it("passes a family with a second adult, however new it is", () => {
    expect(
      evaluateGuardianClearSeasoning({
        familyCreatedAtMs: created,
        requestCreatedAtMs: created + 1000,
        otherAdultMemberCount: 1,
      })
    ).toEqual({ ok: true, reason: "corroborating_adult" });
  });

  it("passes a single-adult family that predates the request by more than the window", () => {
    expect(
      evaluateGuardianClearSeasoning({
        familyCreatedAtMs: created,
        requestCreatedAtMs: created + GUARDIAN_CLEAR_SEASONING_WINDOW_MS + 1,
        otherAdultMemberCount: 0,
      })
    ).toEqual({ ok: true, reason: "family_seasoned" });
  });

  /** The laundering shape: a family conjured minutes ago with exactly one adult in it. */
  it("FR-66(b): denies a brand-new single-adult family", () => {
    expect(
      evaluateGuardianClearSeasoning({
        familyCreatedAtMs: created,
        requestCreatedAtMs: created + 60_000,
        otherAdultMemberCount: 0,
      }).ok
    ).toBe(false);
  });

  it("treats the window as exclusive at the boundary", () => {
    const atBoundary = evaluateGuardianClearSeasoning({
      familyCreatedAtMs: created,
      requestCreatedAtMs: created + GUARDIAN_CLEAR_SEASONING_WINDOW_MS,
      otherAdultMemberCount: 0,
    });
    expect(atBoundary.ok).toBe(false);
    expect(GUARDIAN_CLEAR_SEASONING_WINDOW_MS).toBe(3 * DAY);
  });

  it("denies rather than passes when a timestamp cannot be read", () => {
    for (const patch of [
      { familyCreatedAtMs: null },
      { requestCreatedAtMs: null },
      { familyCreatedAtMs: null, requestCreatedAtMs: null },
    ]) {
      expect(
        evaluateGuardianClearSeasoning({
          familyCreatedAtMs: created,
          requestCreatedAtMs: created + 10 * DAY,
          otherAdultMemberCount: 0,
          ...patch,
        }).ok
      ).toBe(false);
    }
  });

  it("does not let a backdated request forge age", () => {
    // requestCreatedAt BEFORE familyCreatedAt yields a negative difference, not a pass.
    expect(
      evaluateGuardianClearSeasoning({
        familyCreatedAtMs: created,
        requestCreatedAtMs: created - 10 * DAY,
        otherAdultMemberCount: 0,
      }).ok
    ).toBe(false);
  });
});

describe("countCorroboratingAdults", () => {
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
  });

  it("excludes the approver and the target, and counts the rest", async () => {
    db.seed("families/fam1/members/captain", { role: "creator" });
    db.seed("families/fam1/members/joiner", { role: "scout" });
    db.seed("families/fam1/members/otherparent", { role: "captain" });
    expect(
      await countCorroboratingAdults(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
      })
    ).toBe(1);
  });

  it("does not count children as corroborating adults", async () => {
    db.seed("families/fam1/members/captain", { role: "creator" });
    db.seed("families/fam1/members/joiner", { role: "scout" });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    expect(
      await countCorroboratingAdults(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
      })
    ).toBe(0);
  });

  it("counts a member with no isChild key as an adult (§4 missing-flag convention)", async () => {
    db.seed("families/fam1/members/captain", { role: "creator" });
    db.seed("families/fam1/members/joiner", { role: "scout" });
    db.seed("families/fam1/members/quiet", {});
    expect(
      await countCorroboratingAdults(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
      })
    ).toBe(1);
  });

  it("returns zero for the self-made-captain family (creator is the approver)", async () => {
    db.seed("families/fam1/members/captain", { role: "creator" });
    expect(
      await countCorroboratingAdults(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
      })
    ).toBe(0);
  });
});

describe("assertGuardianClearSeasoning", () => {
  const created = 1_700_000_000_000;
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
    // FakeFirestore JSON-clones seeds, so timestamps are stored as raw millis —
    // `timestampToMillis` accepts them directly.
    db.seed("families/fam1", { name: "Fam", createdAt: created });
    db.seed("families/fam1/members/captain", { role: "creator" });
  });

  it("passes once a second adult is aboard", async () => {
    db.seed("families/fam1/members/otherparent", { role: "captain" });
    await expect(
      assertGuardianClearSeasoning(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
        requestData: { createdAt: created + 1000 },
      })
    ).resolves.toBeUndefined();
  });

  it("passes a seasoned single-adult family", async () => {
    await expect(
      assertGuardianClearSeasoning(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
        requestData: {
          createdAt: created + GUARDIAN_CLEAR_SEASONING_WINDOW_MS + 1,
        },
      })
    ).resolves.toBeUndefined();
  });

  it("FR-66(b): refuses the freshly-minted single-adult family", async () => {
    await expect(
      assertGuardianClearSeasoning(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
        requestData: { createdAt: created + 60_000 },
      })
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: GUARDIAN_CLEAR_SEASONING_MESSAGE,
    });
  });

  it("refuses when the family doc has no readable createdAt and no second adult", async () => {
    db.seed("families/fam1", { name: "Fam", createdAt: "__serverTimestamp__" });
    await expect(
      assertGuardianClearSeasoning(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
        requestData: { createdAt: created + 999 * 60_000 },
      })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("falls back to nowMs when the request's createdAt is still a sentinel", async () => {
    await expect(
      assertGuardianClearSeasoning(db as never, {
        familyId: "fam1",
        approverUserId: "captain",
        targetUserId: "joiner",
        requestData: { createdAt: "__serverTimestamp__" },
        nowMs: created + GUARDIAN_CLEAR_SEASONING_WINDOW_MS + 1,
      })
    ).resolves.toBeUndefined();
  });
});
