/**
 * COPPA FR-60 (F-18) end-to-end — the two consent exits and what happens after them, run
 * against the REAL callables with `firebase-admin` replaced by a `FakeFirestore`
 * (same shape as `consentBoundaryChain.test.ts`).
 *
 * Under the local-first model an under-13 player has no backend identity until they enter a
 * share code. From that moment until the captain decides, they are an ANONYMOUS Firebase
 * caller holding a declared `users/{uid}` — a shape that every existing gate on these two
 * callables was written to reject. So this file drives the whole arc from the server's side:
 *
 *   redeem (anonymous, declared)  →  accept  →  captain decides
 *                                                 ├─ decline → the account stops existing
 *                                                 └─ approve → the redemption window closes
 *
 * and asserts the two ways it must NOT go: an ordinary anonymous caller is still refused,
 * with a reply that tells them nothing; and a sticky post-revocation child — who looks
 * identical on the FR-28 fields — is never swept up by the decline cleanup.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({ db: undefined as any, deletedAuthUsers: [] as string[] }));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
  };
  // Raw millis (see `consentBoundaryChain.test.ts`): FakeFirestore JSON-clones every write.
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
  };
  const auth = () => ({
    deleteUser: async (uid: string) => {
      holder.deletedAuthUsers.push(uid);
    },
  });
  return { default: { firestore, auth }, firestore, auth };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { confirmGuardianConsent } from "./testSupport/consentTestHelpers";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import { REGISTERED_ACCOUNT_REQUIRED_MESSAGE } from "./callableAuth";
import { CHILD_DECLARED_AT_FIELD } from "./provisionalChildAccounts";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

/** A registered (email/password) caller. */
function registered(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

/** The FR-60 shape: provisioned minutes ago at share-code entry, no credentials yet. */
function anonymous(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "anonymous" } } } };
}

const run = {
  createFamily: (uid: string, name: string) =>
    (createFamily as unknown as Runnable).run({ name }, registered(uid)) as Promise<{
      familyId: string;
    }>,
  createShareCode: (uid: string, familyId: string) =>
    (createShareCode as unknown as Runnable).run(
      { type: "family", familyId },
      registered(uid)
    ) as Promise<{ codeId: string; code: string }>,
  redeem: (ctx: unknown, code: string) =>
    (redeemShareCode as unknown as Runnable).run(
      { code, expectedType: "family" },
      ctx
    ) as Promise<{ inviteId: string }>,
  accept: (ctx: unknown, inviteId: string) =>
    (respondToFamilyInvite_UserStep as unknown as Runnable).run({ inviteId, response: "accept" }, ctx),
  decide: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(payload, registered(uid)),
};

function pendingRows(familyId: string): Array<[string, Record<string, unknown>]> {
  const prefix = `families/${familyId}/pending/`;
  return [...db().store.entries()]
    .filter(([path]) => path.startsWith(prefix))
    .map(([path, data]) => [path.slice(prefix.length), data]);
}

/** Walk the child all the way to a pending join request, exactly as the client would. */
async function childAwaitingApproval(
  childUid: string
): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("parent", "Real Family");
  const { code } = await run.createShareCode("parent", familyId);
  const { inviteId } = await run.redeem(anonymous(childUid), code);
  await run.accept(anonymous(childUid), inviteId);
  const rows = pendingRows(familyId);
  expect(rows).toHaveLength(1);
  return { familyId, requestId: rows[0][0] };
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;

  db().seed("users/parent", { userName: "Parent" });
  // FR-59.1: the guardian's email for the consent-request path.
  db().seed("users/parent/private/contact", { email: "parent@example.com" });
  // Provisioned at share-code entry: declared, stamped, nothing else.
  // `ageOutYearMonth` per FR-110(b): the consent record refuses to commit without it.
  db().seed("users/kid", {
    userName: "Kid",
    isChildAccount: true,
    [CHILD_DECLARED_AT_FIELD]: Date.now(),
    ageOutYearMonth: 203703,
  });
  // Consented once, then revoked. Identical to `kid` on the FR-28 fields.
  db().seed("users/revokedkid", {
    userName: "RevokedKid",
    isChildAccount: true,
    wasEverInFamily: true,
  });
  // An ordinary anonymous guest — no declaration, no carve-out.
  db().seed("users/guest", { userName: "Guest" });
});

// ---------------------------------------------------------------------------
// The carve-out on the two exits
// ---------------------------------------------------------------------------

describe("FR-60(b): the consent exits admit a declared child's anonymous session", () => {
  it("an anonymous declared child redeems a family code and reaches a pending request", async () => {
    const { familyId, requestId } = await childAwaitingApproval("kid");
    const request = db().store.get(`families/${familyId}/pending/${requestId}`)!;
    expect(request.userId).toBe("kid");
    expect(request.status).toBe("pending");
    // FR-66(a): the row still carries the lineage the captain's approval demands. The
    // carve-out changes who may call the exits, never what the exits produce.
    expect(request.origin).toBe("share_code");
    expect(request.originInviteId).toBeTruthy();
    expect(request.originCodeId).toBeTruthy();
  });

  it("a sticky post-revocation child gets the same exit (re-admission is their route back)", async () => {
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);
    await expect(run.redeem(anonymous("revokedkid"), code)).resolves.toMatchObject({
      inviteId: expect.any(String),
    });
  });

  it("an ordinary anonymous guest is still refused on both exits", async () => {
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);

    await expect(run.redeem(anonymous("guest"), code)).rejects.toMatchObject({
      code: "failed-precondition",
      message: REGISTERED_ACCOUNT_REQUIRED_MESSAGE,
    });

    // And on the invite exit, using an invite minted for someone else.
    const { inviteId } = await run.redeem(anonymous("kid"), code);
    await expect(run.accept(anonymous("guest"), inviteId)).rejects.toMatchObject({
      code: "failed-precondition",
      message: REGISTERED_ACCOUNT_REQUIRED_MESSAGE,
    });
    expect(pendingRows(familyId)).toHaveLength(0);
  });

  /**
   * FR-24: the refusal must not double as a "is this uid a declared child?" oracle. An
   * attacker holding a bearer share code and a list of uids gets the same bytes either way.
   */
  it("refuses the guest with no details payload", async () => {
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);
    const error = await run.redeem(anonymous("guest"), code).catch((e) => e);
    expect(error.details).toBeUndefined();
    expect(pendingRows(familyId)).toHaveLength(0);
  });

  it("registered adults are unaffected", async () => {
    db().seed("users/otheradult", { userName: "Other" });
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);
    const { inviteId } = await run.redeem(registered("otheradult"), code);
    await run.accept(registered("otheradult"), inviteId);
    expect(pendingRows(familyId)).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// FR-60(c): decline ends the transient account
// ---------------------------------------------------------------------------

describe("FR-60(c): a declined never-consented child's account is deleted", () => {
  it("deletes users/{uid} and the Firebase Auth user after the decline commits", async () => {
    const { familyId, requestId } = await childAwaitingApproval("kid");
    db().seed("user_progression/kid", { totalXp: 25 });

    await run.decide("parent", { familyId, requestId, response: "decline" });

    // The captain's decline itself still lands.
    expect(db().store.get(`families/${familyId}/pending/${requestId}`)!.status).toBe("declined");
    // And the account it was about no longer exists.
    expect(db().store.has("users/kid")).toBe(false);
    expect(db().store.has("user_progression/kid")).toBe(false);
    expect(holder.deletedAuthUsers).toEqual(["kid"]);
  });

  /**
   * The carve-out that matters. A revoked child can legitimately be re-admitted (FR-25), so
   * a captain may decline that request — and doing so must NOT delete an account whose data
   * FR-28 retains and whose parent still holds a deletion offer under FR-63(a).
   */
  it("does NOT delete a sticky post-revocation child on decline", async () => {
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);
    const { inviteId } = await run.redeem(anonymous("revokedkid"), code);
    await run.accept(anonymous("revokedkid"), inviteId);
    const requestId = pendingRows(familyId)[0][0];
    db().seed("user_progression/revokedkid", { totalXp: 900 });

    await run.decide("parent", { familyId, requestId, response: "decline" });

    expect(db().store.get(`families/${familyId}/pending/${requestId}`)!.status).toBe("declined");
    expect(db().store.get("users/revokedkid")).toBeDefined();
    expect(db().store.get("users/revokedkid")!.isChildAccount).toBe(true);
    expect(db().store.get("user_progression/revokedkid")).toBeDefined();
    expect(holder.deletedAuthUsers).toEqual([]);
  });

  it("does not delete a declined ADULT applicant", async () => {
    db().seed("users/otheradult", { userName: "Other" });
    const { familyId } = await run.createFamily("parent", "Real Family");
    const { code } = await run.createShareCode("parent", familyId);
    const { inviteId } = await run.redeem(registered("otheradult"), code);
    await run.accept(registered("otheradult"), inviteId);
    const requestId = pendingRows(familyId)[0][0];

    await run.decide("parent", { familyId, requestId, response: "decline" });

    expect(db().store.get("users/otheradult")).toBeDefined();
    expect(holder.deletedAuthUsers).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// FR-60(c): approval closes the redemption window
// ---------------------------------------------------------------------------

describe("FR-60(c): admission clears the redemption-window marker", () => {
  it("approval removes childDeclaredAt and sets the consent proxy", async () => {
    const { familyId, requestId } = await childAwaitingApproval("kid");
    expect(db().store.get("users/kid")![CHILD_DECLARED_AT_FIELD]).toBeDefined();

    await run.decide("parent", {
      familyId,
      requestId,
      response: "approve",
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });
    // FR-59.1: admission (and with it the marker delete) commits at the guardian's
    // emailed confirmation, not at the captain's tap.
    const outcome = await confirmGuardianConsent(db(), {
      familyId,
      childUserId: "kid",
    });
    expect(outcome.committed).toBe(true);

    const kid = db().store.get("users/kid")!;
    // `FakeFirestore` stores the delete sentinel verbatim rather than removing the key (the
    // same convention `wasEverInFamilyUserUpdates.test.ts` asserts against for
    // `activeFamilyId`), so seeing it here IS the field-delete reaching the batch.
    expect(kid[CHILD_DECLARED_AT_FIELD]).toBe("__delete__");
    expect(kid.activeFamilyId).toBe(familyId);
    expect(kid.wasEverInFamily).toBe(true);
    expect(kid.isChildAccount).toBe(true);
    expect(holder.deletedAuthUsers).toEqual([]);
  });

  /**
   * COPPA FR-85 (F-42): the capability grant rides the SAME batch as membership, so there
   * is no window in which a child is consented but second-class. Asserted end to end through
   * the real approval callable, not just the update builder.
   */
  it("FR-85: the same batch grants the signed-up-equivalent capability, and never isRegistered", async () => {
    const { familyId, requestId } = await childAwaitingApproval("kid");

    await run.decide("parent", {
      familyId,
      requestId,
      response: "approve",
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });
    const outcome = await confirmGuardianConsent(db(), {
      familyId,
      childUserId: "kid",
    });
    expect(outcome.committed).toBe(true);

    const kid = db().store.get("users/kid")!;
    expect(kid.entitlementTags).toEqual({ __arrayUnion__: ["signedUpEquivalent"] });
    // The prohibited implementation: `isRegistered` drives search indexing (FR-70/FR-11).
    expect(kid.isRegistered).toBeUndefined();
  });
});
