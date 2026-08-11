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
import { createFamily, sendFamilyInvite } from "./family";
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

function invite(uid: string, toUserId: string, method?: string) {
  return (sendFamilyInvite as unknown as Runnable).run(
    { toUserId, familyId: "fam1", ...(method ? { method } : {}) },
    context(uid)
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
