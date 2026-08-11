/**
 * FR-14 / FR-15 / FR-24 (COPPA F-5b) — the actor/target child gates shared by
 * `sendFriendInvite`, `sendFamilyInvite`, `createFamily` and `createShareCode`.
 *
 * The two properties worth pinning beyond allow/deny:
 *  - the ACTOR gate covers ALL children, not just unconsented ones (F-5a's
 *    `assertNotUnconsentedChild` deliberately lets a consented child through — these
 *    callables must not);
 *  - rejections are indistinguishable from the pre-existing privacy opt-out, so a sender
 *    can never use an invite as a child-detector.
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  assertCallerIsNotChild,
  assertTargetIsNotChild,
  isChildAccount,
} from "./childAccessGuards";
import {
  CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
  CHILD_CALLER_REJECTION_REASON,
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
  isChildWithActiveFamilyUserData,
} from "./childAccountCore";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

function seededStore(): FakeFirestore {
  const db = new FakeFirestore();
  db.seed("users/lonekid", { userName: "Lone", isChildAccount: true });
  db.seed("users/famkid", {
    userName: "Fam",
    isChildAccount: true,
    activeFamilyId: "fam1",
  });
  db.seed("users/adult", { userName: "Grown" });
  db.seed("users/exadult", { userName: "Grown2", isChildAccount: false });
  return db;
}

describe("isChildAccount", () => {
  it("is true only for the literal flag; missing doc and missing flag are adults", async () => {
    const db = asFirestore(seededStore());
    await expect(isChildAccount(db, "lonekid")).resolves.toBe(true);
    await expect(isChildAccount(db, "famkid")).resolves.toBe(true);
    await expect(isChildAccount(db, "adult")).resolves.toBe(false);
    await expect(isChildAccount(db, "exadult")).resolves.toBe(false);
    await expect(isChildAccount(db, "nobody")).resolves.toBe(false);
  });
});

describe("FR-24: assertCallerIsNotChild rejects every child caller", () => {
  it("rejects an unconsented child", async () => {
    await expect(
      assertCallerIsNotChild(asFirestore(seededStore()), "lonekid")
    ).rejects.toMatchObject({
      code: "permission-denied",
      message: CHILD_CALLER_NOT_SEARCHABLE_MESSAGE,
      details: { reason: CHILD_CALLER_REJECTION_REASON },
    });
  });

  it("rejects a CONSENTED child too — wider than FR-28's unconsented-only gate", async () => {
    await expect(
      assertCallerIsNotChild(asFirestore(seededStore()), "famkid")
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("allows adults, explicit non-children, and callers with no user doc", async () => {
    const db = asFirestore(seededStore());
    await expect(assertCallerIsNotChild(db, "adult")).resolves.toBeUndefined();
    await expect(assertCallerIsNotChild(db, "exadult")).resolves.toBeUndefined();
    await expect(assertCallerIsNotChild(db, "nobody")).resolves.toBeUndefined();
  });

  it("uses the 'not searchable' wording the iOS analytics mapping already classifies", () => {
    expect(CHILD_CALLER_NOT_SEARCHABLE_MESSAGE.toLowerCase()).toContain(
      "not searchable"
    );
  });
});

describe("FR-14: assertTargetIsNotChild rejects child friend targets outright", () => {
  it("rejects both unconsented and consented children — no family carve-out", async () => {
    const db = asFirestore(seededStore());
    for (const target of ["lonekid", "famkid"]) {
      await expect(assertTargetIsNotChild(db, target)).rejects.toMatchObject({
        code: "permission-denied",
        message: CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
      });
    }
  });

  it("allows adults and unknown uids", async () => {
    const db = asFirestore(seededStore());
    await expect(assertTargetIsNotChild(db, "adult")).resolves.toBeUndefined();
    await expect(assertTargetIsNotChild(db, "nobody")).resolves.toBeUndefined();
  });

  it("is byte-identical to the existing privacy-opt-out rejection (non-disclosure)", () => {
    // `friends.ts` / `family.ts` already throw exactly this string when a target has turned
    // contact search off. Reusing it verbatim is what makes the child case undetectable.
    expect(CHILD_TARGET_NOT_SEARCHABLE_MESSAGE).toBe(
      "User is not searchable by this method"
    );
  });
});

/**
 * FR-24 has an "and NOT here" half that no allow/deny unit test can express: a child MUST
 * keep `redeemShareCode`, `respondToFamilyInvite_UserStep` and `deleteAccount` — their only
 * routes back into consented play and out of the system. Adding the actor gate to any of
 * them would trap an orphaned child with no exit, so the wiring itself is pinned here.
 */
function callableBodies(fileName: string): Map<string, string> {
  const source = readFileSync(resolve(__dirname, fileName), "utf8");
  const bodies = new Map<string, string>();
  const boundary = /^export (?:const|async function) (\w+)/gm;
  const marks: Array<{ name: string; index: number }> = [];
  for (let m = boundary.exec(source); m; m = boundary.exec(source)) {
    marks.push({ name: m[1], index: m.index });
  }
  marks.forEach((mark, i) => {
    const end = i + 1 < marks.length ? marks[i + 1].index : source.length;
    bodies.set(mark.name, source.slice(mark.index, end));
  });
  return bodies;
}

describe("FR-24 wiring: the actor gate is on the contact callables and nowhere else", () => {
  const expected: Record<string, Record<string, boolean>> = {
    "friends.ts": {
      sendFriendInvite: true,
      respondToFriendInvite: false,
      removeFriend: false,
    },
    "family.ts": {
      createFamily: true,
      sendFamilyInvite: true,
      respondToFamilyInvite_UserStep: false,
      approveFamilyJoinRequest_CaptainStep: false,
      removeFamilyMember: false,
      changeFamilyMemberRole: false,
      inactivateFamily: false,
    },
    "shareCodes.ts": { createShareCode: true, redeemShareCode: false },
    "accountDeletion.ts": { deleteAccount: false },
  };

  for (const [fileName, callables] of Object.entries(expected)) {
    it(`${fileName} carries the gate exactly where FR-24 says`, () => {
      const bodies = callableBodies(fileName);
      for (const [callable, shouldGate] of Object.entries(callables)) {
        const body = bodies.get(callable);
        expect(body, `${fileName} no longer exports ${callable}`).toBeDefined();
        expect(
          body!.includes("assertCallerIsNotChild"),
          `${callable} child-gate wiring changed`
        ).toBe(shouldGate);
      }
    });
  }

  it("FR-14: the child-TARGET gate covers both invite creation AND acceptance", () => {
    // Acceptance matters because `redeemShareCode` — which children must keep calling —
    // also mints `invites` rows, so `sendFriendInvite` alone cannot prevent the edge.
    const bodies = callableBodies("friends.ts");
    expect(bodies.get("sendFriendInvite")!).toContain("assertTargetIsNotChild");
    expect(bodies.get("respondToFriendInvite")!).toContain("assertTargetIsNotChild");
    expect(bodies.get("removeFriend")!).not.toContain("assertTargetIsNotChild");
  });
});

describe("FR-15: family invites and children who already have a family", () => {
  it("blocks a child who is already in a family", () => {
    expect(
      isChildWithActiveFamilyUserData({
        isChildAccount: true,
        activeFamilyId: "fam1",
      })
    ).toBe(true);
  });

  it("still allows inviting an UNCONSENTED child — the path back to consented play", () => {
    expect(isChildWithActiveFamilyUserData({ isChildAccount: true })).toBe(false);
    expect(
      isChildWithActiveFamilyUserData({ isChildAccount: true, activeFamilyId: "" })
    ).toBe(false);
  });

  it("never blocks adults, in or out of a family", () => {
    expect(isChildWithActiveFamilyUserData({ activeFamilyId: "fam1" })).toBe(false);
    expect(
      isChildWithActiveFamilyUserData({
        isChildAccount: false,
        activeFamilyId: "fam1",
      })
    ).toBe(false);
    expect(isChildWithActiveFamilyUserData(undefined)).toBe(false);
  });
});
