/**
 * CB-7 end-to-end chain replay — COPPA FR-66 (F-22) + FR-67 (F-23).
 *
 * Family membership IS the parental-consent object in this app: `activeFamilyId` is the
 * consent proxy, and a family creator/captain is the "parent/manager" every child rule
 * defers to. Before FR-66 nothing checked who could become one, so the whole boundary could
 * be manufactured by a determined 12-year-old with two accounts:
 *
 *   1. mint a throwaway account that never declares a child age — indistinguishable from an
 *      adult — and call `createFamily`. The child is now their own consenting manager.
 *   2. from their REAL, flagged account, write a `families/{id}/pending/{requestId}` naming
 *      themselves. Target familyIds are harvestable: `activeFamilyId` sits on the
 *      peer-readable user doc.
 *   3. approve it from the throwaway with `isChild: false`. That branch was attestation-free
 *      — no reason, no acknowledgment — so the sticky flag simply cleared.
 *   4. the real account is now an ordinary adult: searchable, friendable, ad-eligible.
 *
 * The SRS requires the chain to fail at three INDEPENDENT links, so that no single
 * regression re-opens it. This file replays the whole thing against the real callables and
 * asserts each link alone is fatal:
 *
 *   (a) lineage      — a pending row no invite produced cannot be approved;
 *   (b) flag-clear   — even with perfect lineage, clearing needs enumerated evidence AND a
 *                      family that is not freshly conjured around a single adult;
 *   (FR-67) throttle — covered in `shareCodeRedemption.test.ts`, which owns the redemption
 *                      surface; step 2's code-redemption variant is bounded there.
 *
 * The final block is the other direction §2.4 demands: a LEGITIMATE new guardian must still
 * be able to clear a flag that was set in error. A boundary that cannot be crossed by the
 * people it exists to serve is its own kind of failure.
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
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
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
import { confirmGuardianConsent } from "./testSupport/consentTestHelpers";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  GUARDIAN_CLEAR_SEASONING_MESSAGE,
  GUARDIAN_CLEAR_SEASONING_WINDOW_MS,
  JOIN_REQUEST_LINEAGE_MISSING_MESSAGE,
} from "./familyJoinRequestIntegrity";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const run = {
  createFamily: (uid: string, name: string) =>
    (createFamily as unknown as Runnable).run({ name }, context(uid)) as Promise<{
      familyId: string;
    }>,
  createShareCode: (uid: string, familyId: string) =>
    (createShareCode as unknown as Runnable).run(
      { type: "family", familyId },
      context(uid)
    ) as Promise<{ codeId: string; code: string }>,
  redeemShareCode: (uid: string, code: string) =>
    (redeemShareCode as unknown as Runnable).run(
      { code, expectedType: "family" },
      context(uid)
    ) as Promise<{ inviteId: string }>,
  acceptInvite: (uid: string, inviteId: string) =>
    (respondToFamilyInvite_UserStep as unknown as Runnable).run(
      { inviteId, response: "accept" },
      context(uid)
    ),
  approve: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "approve", ...payload },
      context(uid)
    ),
};

/** Every pending row under a family, as [id, data] pairs. */
function pendingRows(familyId: string): Array<[string, Record<string, unknown>]> {
  const prefix = `families/${familyId}/pending/`;
  return [...db().store.entries()]
    .filter(([path]) => path.startsWith(prefix))
    .map(([path, data]) => [path.slice(prefix.length), data]);
}

function childFlagOf(uid: string): unknown {
  return db().store.get(`users/${uid}`)?.isChildAccount;
}

/** Walk the attack to the point where a pending row with REAL lineage exists. */
async function launderedJoinRequest(): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("attackerAdult", "Totally Real Family");
  const { code } = await run.createShareCode("attackerAdult", familyId);
  const { inviteId } = await run.redeemShareCode("attackerChild", code);
  await run.acceptInvite("attackerChild", inviteId);
  const rows = pendingRows(familyId);
  expect(rows).toHaveLength(1);
  return { familyId, requestId: rows[0][0] };
}

const FULL_EVIDENCE = {
  isChild: false,
  consentAcknowledged: true,
  guardianAffirmed: true,
  correctionReason: "flag_set_in_error",
};

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;

  // The throwaway "adult". Nothing distinguishes it from a real adult at creation time —
  // that is precisely why the boundary cannot rest on who holds the captain role.
  db().seed("users/attackerAdult", { userName: "Grownup" });
  // FR-59.1: the guardian's email for the consent-request path.
  db().seed("users/attackerAdult/private/contact", { email: "grownup@example.com" });
  // The real account, already flagged (sticky, per FR-1).
  // `ageOutYearMonth` per FR-110(b): the consent record refuses to commit without it.
  db().seed("users/attackerChild", {
    userName: "Kid",
    isChildAccount: true,
    ageOutYearMonth: 203703,
  });
});

// ---------------------------------------------------------------------------
// Link (a) — join-request lineage
// ---------------------------------------------------------------------------

describe("CB-7 link (a): a self-injected join request cannot be approved", () => {
  it("fails at approval when the pending row came from no invite", async () => {
    const { familyId } = await run.createFamily("attackerAdult", "Totally Real Family");

    // Step 2 of the chain, as the attacker used to perform it: a direct client write of a
    // truthfully self-named pending row. `firestore.rules` now denies this outright
    // (`create: if false`, covered in the rules matrix); seeding it here proves the
    // CALLABLE refuses independently, so a rules regression alone does not re-open CB-7.
    db().seed(`families/${familyId}/pending/forged`, {
      userId: "attackerChild",
      requestedBy: "attackerChild",
      method: "self",
      status: "pending",
      createdAt: Date.now(),
    });

    await expect(
      run.approve("attackerAdult", { familyId, requestId: "forged", ...FULL_EVIDENCE })
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: JOIN_REQUEST_LINEAGE_MISSING_MESSAGE,
    });

    // Nothing moved: no membership, no flag change.
    expect(db().store.get(`families/${familyId}/members/attackerChild`)).toBeUndefined();
    expect(childFlagOf("attackerChild")).toBe(true);
  });

  it("refuses a row carrying a fabricated lineage stamp", async () => {
    const { familyId } = await run.createFamily("attackerAdult", "Totally Real Family");
    db().seed(`families/${familyId}/pending/forged`, {
      userId: "attackerChild",
      status: "pending",
      createdAt: Date.now(),
      origin: "definitely_legitimate",
      originInviteId: "made-up",
    });

    await expect(
      run.approve("attackerAdult", { familyId, requestId: "forged", ...FULL_EVIDENCE })
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(childFlagOf("attackerChild")).toBe(true);
  });

  it("REGRESSION: a decline still clears a malformed row from the queue", async () => {
    // A request that can neither be approved nor dismissed would be its own trap.
    const { familyId } = await run.createFamily("attackerAdult", "Totally Real Family");
    db().seed(`families/${familyId}/pending/forged`, {
      userId: "attackerChild",
      status: "pending",
      createdAt: Date.now(),
    });

    await (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { familyId, requestId: "forged", response: "decline" },
      context("attackerAdult")
    );
    expect(db().store.get(`families/${familyId}/pending/forged`)?.status).toBe("declined");
  });

  it("stamps lineage on the legitimate invite path, so real requests still approve", async () => {
    const { familyId, requestId } = await launderedJoinRequest();
    const [, row] = pendingRows(familyId)[0];
    expect(row.origin).toBe("share_code");
    expect(typeof row.originInviteId).toBe("string");
    expect(typeof row.originCodeId).toBe("string");
    expect(requestId).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// Link (b) — the flag clear
// ---------------------------------------------------------------------------

describe("CB-7 link (b): the flag clear is not attestation-free", () => {
  it("fails independently even with PERFECT lineage — the pre-FR-66 payload is refused", async () => {
    const { familyId, requestId } = await launderedJoinRequest();

    // Exactly what the old chain sent: a bare `isChild: false`.
    await expect(
      run.approve("attackerAdult", { familyId, requestId, isChild: false })
    ).rejects.toMatchObject({ code: "failed-precondition" });

    expect(childFlagOf("attackerChild")).toBe(true);
    expect(db().store.get(`families/${familyId}/members/attackerChild`)).toBeUndefined();
  });

  it("refuses a clear with an unenumerated reason", async () => {
    const { familyId, requestId } = await launderedJoinRequest();
    await expect(
      run.approve("attackerAdult", {
        familyId,
        requestId,
        isChild: false,
        consentAcknowledged: true,
        guardianAffirmed: true,
        correctionReason: "i_promise_im_an_adult",
      })
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(childFlagOf("attackerChild")).toBe(true);
  });

  /**
   * The heart of it. An attacker can supply every acknowledgment and pick a real reason —
   * they are just booleans and a slug. Seasoning is what evidence cannot fake: the family
   * was created minutes ago and contains exactly one adult, who is the approver.
   */
  it("refuses a fully-evidenced clear from a freshly-conjured single-adult family", async () => {
    const { familyId, requestId } = await launderedJoinRequest();

    await expect(
      run.approve("attackerAdult", { familyId, requestId, ...FULL_EVIDENCE })
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: GUARDIAN_CLEAR_SEASONING_MESSAGE,
    });

    expect(childFlagOf("attackerChild")).toBe(true);
    expect(db().store.get(`families/${familyId}/members/attackerChild`)).toBeUndefined();
  });

  it("REGRESSION: the child may still be admitted AS a child from the same request", async () => {
    // FR-66 must close the laundering path without closing the consent path. Admitting the
    // child honestly — `isChild: true` with both acknowledgments — still works.
    const { familyId, requestId } = await launderedJoinRequest();

    await run.approve("attackerAdult", {
      familyId,
      requestId,
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });
    // FR-59.1: admission now completes at the guardian's emailed confirmation.
    const outcome = await confirmGuardianConsent(db(), {
      familyId,
      childUserId: "attackerChild",
    });
    expect(outcome.committed).toBe(true);

    expect(childFlagOf("attackerChild")).toBe(true);
    expect(db().store.get(`families/${familyId}/members/attackerChild`)?.isChild).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// The whole chain, and the legitimate path it must not break
// ---------------------------------------------------------------------------

describe("CB-7: the chain end to end", () => {
  it("cannot be completed by any route, and the child's protections survive", async () => {
    const { familyId, requestId } = await launderedJoinRequest();

    const attempts = [
      { familyId, requestId, isChild: false },
      { familyId, requestId, isChild: false, consentAcknowledged: true },
      { familyId, requestId, isChild: false, guardianAffirmed: true },
      { familyId, requestId, ...FULL_EVIDENCE },
      { familyId, requestId, ...FULL_EVIDENCE, correctionReason: "child_turned_13" },
    ];

    for (const payload of attempts) {
      await expect(run.approve("attackerAdult", payload)).rejects.toBeTruthy();
    }

    expect(childFlagOf("attackerChild")).toBe(true);
    expect(db().store.get("users/attackerChild")?.activeFamilyId).toBeUndefined();
    expect(db().store.get(`families/${familyId}/members/attackerChild`)).toBeUndefined();
  });

  /** §2.4, the other direction: a real guardian must not be permanently blocked. */
  it("a corroborating second adult unblocks a genuine correction", async () => {
    const { familyId, requestId } = await launderedJoinRequest();

    // A second, unrelated adult is already in the family — the shape a real household has
    // and a conjured one does not.
    db().seed("users/otherparent", { userName: "OtherParent", activeFamilyId: familyId });
    db().seed(`families/${familyId}/members/otherparent`, { role: "captain" });

    await run.approve("attackerAdult", { familyId, requestId, ...FULL_EVIDENCE });

    expect(childFlagOf("attackerChild")).toBe(false);
    expect(db().store.get(`families/${familyId}/members/attackerChild`)?.isChild).toBe(false);
  });

  it("a family older than the seasoning window unblocks a genuine correction", async () => {
    const { familyId, requestId } = await launderedJoinRequest();

    // Same single-adult family, but it has existed for well over the OD-5 window.
    const family = db().store.get(`families/${familyId}`)!;
    db().seed(`families/${familyId}`, {
      ...family,
      createdAt: Date.now() - GUARDIAN_CLEAR_SEASONING_WINDOW_MS - 60_000,
    });
    const requestPath = `families/${familyId}/pending/${requestId}`;
    db().seed(requestPath, { ...db().store.get(requestPath)!, createdAt: Date.now() });

    await run.approve("attackerAdult", { familyId, requestId, ...FULL_EVIDENCE });

    expect(childFlagOf("attackerChild")).toBe(false);
  });

  it("records the manager's enumerated reason on the correction audit row", async () => {
    const { familyId, requestId } = await launderedJoinRequest();
    db().seed("users/otherparent", { userName: "OtherParent", activeFamilyId: familyId });
    db().seed(`families/${familyId}/members/otherparent`, { role: "captain" });

    await run.approve("attackerAdult", {
      familyId,
      requestId,
      ...FULL_EVIDENCE,
      correctionReason: "child_turned_13",
    });

    const corrected = [...db().store.values()].filter(
      (row) => row.eventType === "AUDIT_PARENTAL_CONSENT_CORRECTED"
    );
    expect(corrected).toHaveLength(1);
    const metadata = corrected[0].metadata as Record<string, unknown>;
    expect(metadata.reason).toBe("child_turned_13");
    expect(metadata.method).toBe("readmission_declaration");
  });
});
