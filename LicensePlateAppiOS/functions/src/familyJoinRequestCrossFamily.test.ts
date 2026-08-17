/**
 * Admission is about the USER, not the family — owner decision 2026-08-17.
 *
 * "On accept of a family, we should delete all other pending. The offline nature of the app
 * may hurt that, but the backend should be authoritative."
 *
 * WHY IT IS A CORRECTNESS FIX AND NOT A TIDY-UP
 * --------------------------------------------
 * A uid holds exactly one `activeFamilyId`. The instant family A admits a child, every live
 * `pending` row that child holds in B or C is unapprovable — `canAddMemberToFamily` answers
 * "User is already in another active family", and FR-15 refuses even to invite a child who has
 * one. The rows do not stop RENDERING, though: B's captain still sees a normal request with a
 * name on it, still makes FR-31's guardianship affirmation about it, taps approve, and gets a
 * failure for a decision that could never have succeeded. F-44 already retires sibling rows
 * inside the approving family for exactly this reason; this is the same argument across the
 * family boundary, which was never the right boundary.
 *
 * WHAT IS PINNED HERE
 * -------------------
 *   - approve into A retires the live rows in B and C, AND the accepted invites behind them;
 *   - it retires them as `expired`, never `declined` — nobody refused, and `InviteStatus` fails
 *     OPEN on an unknown raw value (it parses back as `.pending`), which would resurrect the
 *     row in the captain's queue;
 *   - F-44's same-family sibling retirement is untouched;
 *   - DECLINE is the mirror and is deliberately NOT symmetric: B's request is still legitimate,
 *     so nothing there is retired — but FR-88's single stamp is re-pointed at B's surviving row
 *     instead of cleared, or the child's genuine "waiting" state disappears with a decline that
 *     was never about it;
 *   - one write per document, because Firestore rejects a commit that carries two.
 *
 * `FakeFirestore` stores the delete sentinel verbatim rather than removing the key, so
 * `"__delete__"` in the store IS the field-delete reaching the batch.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  deletedAuthUsers: [] as string[],
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  const auth: any = () => ({
    deleteUser: async (uid: string) => {
      holder.deletedAuthUsers.push(uid);
    },
  });
  const messaging: any = () => ({ send: async () => "sent" });
  return { default: { firestore, auth, messaging }, firestore, auth, messaging };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { FakeWriteBatch } from "./testSupport/fakeFirestore";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  PENDING_FAMILY_REQUEST_FIELD,
  findLivePendingJoinRequestsInOtherFamilies,
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
  decline: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "decline", ...payload },
      context(uid)
    ),
};

interface Request {
  familyId: string;
  requestId: string;
  inviteId: string;
}

/** A family whose captain is holding one live join request from `child`. */
async function familyAwaiting(
  captain: string,
  name: string,
  child = "kid"
): Promise<Request> {
  db().seed(`users/${captain}`, { userName: captain });
  const { familyId } = await run.createFamily(captain, name);
  const { code } = await run.createShareCode(captain, familyId);
  const { inviteId } = await run.redeemShareCode(child, code);
  await run.acceptInvite(child, inviteId);
  const [requestId] = liveRowsIn(familyId).find(([, row]) => row.userId === child)!;
  return { familyId, requestId, inviteId };
}

function rowsIn(familyId: string): Array<[string, Record<string, unknown>]> {
  const prefix = `families/${familyId}/pending/`;
  return [...db().store.entries()]
    .filter(([path]) => path.startsWith(prefix))
    .map(([path, data]) => [path.slice(prefix.length), data]);
}

function liveRowsIn(familyId: string): Array<[string, Record<string, unknown>]> {
  return rowsIn(familyId).filter(([, data]) => data.status === "pending");
}

function statusOf(request: Request): unknown {
  return db().store.get(`families/${request.familyId}/pending/${request.requestId}`)
    ?.status;
}

function inviteOf(request: Request): Record<string, unknown> | undefined {
  return db().store.get(`invites/${request.inviteId}`);
}

function stampOn(userId: string): unknown {
  return db().store.get(`users/${userId}`)?.[PENDING_FAMILY_REQUEST_FIELD];
}

const CHILD_APPROVAL = {
  isChild: true,
  consentAcknowledged: true,
  guardianAffirmed: true,
};

/**
 * The document paths `body` writes, GROUPED BY BATCH.
 *
 * Firestore rejects a commit carrying two writes for the same document, and `FakeFirestore`
 * does not — it applies both and the outcome looks fine. The invariant is therefore per batch,
 * not per call: a callable legitimately writes one document from its membership batch and
 * again from an idempotent follow-on batch afterwards.
 */
async function batchWriteGroups(body: () => Promise<unknown>): Promise<string[][]> {
  const groups = new Map<unknown, string[]>();
  const proto = FakeWriteBatch.prototype as unknown as Record<string, any>;
  const originals = { set: proto.set, update: proto.update, delete: proto.delete };
  for (const op of ["set", "update", "delete"] as const) {
    proto[op] = function (this: unknown, ref: { path: string }, ...rest: unknown[]) {
      const group = groups.get(this) ?? [];
      group.push(ref.path);
      groups.set(this, group);
      return originals[op].call(this, ref, ...rest);
    };
  }
  try {
    await body();
  } finally {
    Object.assign(proto, originals);
  }
  return [...groups.values()];
}

/** The batch that carried a given document — used to name the membership batch. */
function groupContaining(groups: string[][], path: string): string[] {
  return groups.find((group) => group.includes(path))!;
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;

  // The child as the local-first path leaves them: flagged, no family, never in one.
  db().seed("users/kid", {
    userName: "Speedy",
    avatarId: "scout_otter",
    isChildAccount: true,
    childDeclaredAt: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// Approve — the ghost rows go with the admission
// ---------------------------------------------------------------------------

describe("approving into one family retires the requests held in every other", () => {
  it("retires the live rows in B and C as expired", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    const c = await familyAwaiting("captainC", "Cousins");

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    expect(statusOf(a)).toBe("approved");
    // NOT "declined": nobody refused, and the child WAS admitted — somewhere else.
    expect(statusOf(b)).toBe("expired");
    expect(statusOf(c)).toBe("expired");
    expect(liveRowsIn(b.familyId)).toHaveLength(0);
    expect(liveRowsIn(c.familyId)).toHaveLength(0);
  });

  it("retires the accepted invites those rows were minted from", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    expect(inviteOf(b)?.status).toBe("accepted");

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    // Left "accepted" it keeps reading as a live "awaiting approval" invitation on the
    // requester's own dashboard — the same stale surface, one window over.
    expect(inviteOf(b)).toMatchObject({
      status: "expired",
      respondedAt: "__serverTimestamp__",
    });
  });

  it("still retires the approving family's OWN sibling row (F-44 preserved)", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    // The pre-F-44 wedge, seeded directly: a second live row for the same child in A.
    db().seed(`families/${a.familyId}/pending/legacy-dupe`, {
      userId: "kid",
      status: "pending",
      createdAt: Date.now(),
      origin: "share_code",
      originInviteId: "inv-legacy",
    });

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    expect(
      db().store.get(`families/${a.familyId}/pending/legacy-dupe`)?.status
    ).toBe("expired");
    expect(statusOf(b)).toBe("expired");
    expect(liveRowsIn(a.familyId)).toHaveLength(0);
  });

  it("admits the child exactly as before — one family, one membership", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    await familyAwaiting("captainB", "Neighbours");

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    expect(db().store.get(`families/${a.familyId}/members/kid`)?.isChild).toBe(true);
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(a.familyId);
    expect(holder.deletedAuthUsers).toEqual([]);
  });

  it("leaves a child with no other rows completely unaffected", async () => {
    const a = await familyAwaiting("captainA", "Hammers");

    await expect(
      run.approve("captainA", {
        familyId: a.familyId,
        requestId: a.requestId,
        ...CHILD_APPROVAL,
      })
    ).resolves.toMatchObject({ success: true });

    expect(statusOf(a)).toBe("approved");
    expect(rowsIn(a.familyId)).toHaveLength(1);
  });

  it("touches only the approved user's rows, not another child's", async () => {
    db().seed("users/sibling", {
      userName: "Zoom",
      avatarId: "navigator_raccoon",
      isChildAccount: true,
      childDeclaredAt: Date.now(),
    });
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    const siblingInB = await (async () => {
      const { code } = await run.createShareCode("captainB", b.familyId);
      const { inviteId } = await run.redeemShareCode("sibling", code);
      await run.acceptInvite("sibling", inviteId);
      const [requestId] = liveRowsIn(b.familyId).find(
        ([, row]) => row.userId === "sibling"
      )!;
      return { familyId: b.familyId, requestId, inviteId };
    })();

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    expect(statusOf(b)).toBe("expired");
    expect(statusOf(siblingInB)).toBe("pending");
    expect(inviteOf(siblingInB)?.status).toBe("accepted");
    expect(stampOn("sibling")).toMatchObject({ familyId: b.familyId });
  });

  /**
   * The one membership that is NOT exclusive. `familyMembershipGrantUserUpdate` writes no
   * `activeFamilyId` for a retired general and `canAddMemberToFamily` exempts them from the
   * one-family check — the role exists so a grandparent can belong to several families. Their
   * other rows therefore stay APPROVABLE, and retiring them would destroy live requests in two
   * other captains' queues rather than clean up dead ones.
   */
  it("leaves a retired general's other requests alone — theirs are still approvable", async () => {
    db().seed("users/vet", { userName: "Gramps", isRetiredGeneral: true });
    const a = await familyAwaiting("captainA", "Hammers", "vet");
    const b = await familyAwaiting("captainB", "Neighbours", "vet");

    await run.approve("captainA", { familyId: a.familyId, requestId: a.requestId });

    expect(db().store.get(`families/${a.familyId}/members/vet`)?.role).toBe(
      "retired_general"
    );
    expect(db().store.get("users/vet")?.activeFamilyId).toBeUndefined();
    expect(statusOf(b)).toBe("pending");
    expect(inviteOf(b)?.status).toBe("accepted");
  });

  it("re-approving the same row is still an idempotent success", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    const payload = { familyId: a.familyId, requestId: a.requestId, ...CHILD_APPROVAL };

    await run.approve("captainA", payload);
    const writesAfterFirst = db().writeCount;

    await expect(run.approve("captainA", payload)).resolves.toMatchObject({
      success: true,
    });
    // The second call short-circuits on the already-approved row: no second retirement pass.
    expect(db().writeCount).toBe(writesAfterFirst);
    expect(statusOf(b)).toBe("expired");
  });
});

// ---------------------------------------------------------------------------
// FR-88 and the one-write-per-document rule
// ---------------------------------------------------------------------------

describe("FR-88: the single stamp ends in the right state", () => {
  it("approve clears it once, in the grant write, not twice", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    await familyAwaiting("captainB", "Neighbours");
    await familyAwaiting("captainC", "Cousins");

    const groups = await batchWriteGroups(() =>
      run.approve("captainA", {
        familyId: a.familyId,
        requestId: a.requestId,
        ...CHILD_APPROVAL,
      })
    );

    // A commit carrying two writes for one document is REJECTED outright — the cross-family
    // retirement must not add a second clear beside the grant's.
    const membershipBatch = groupContaining(
      groups,
      `families/${a.familyId}/pending/${a.requestId}`
    );
    expect(membershipBatch.filter((path) => path === "users/kid")).toHaveLength(1);
    for (const group of groups) {
      expect(group).toEqual([...new Set(group)]);
    }
    expect(stampOn("kid")).toBe("__delete__");
  });

  it("the clear is now TRUE: no live row survives anywhere", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");

    await run.approve("captainA", {
      familyId: a.familyId,
      requestId: a.requestId,
      ...CHILD_APPROVAL,
    });

    const stillLive = await findLivePendingJoinRequestsInOtherFamilies(db() as any, {
      userId: "kid",
      excludeFamilyId: b.familyId,
    });
    expect(stillLive.rows).toHaveLength(0);
    expect(liveRowsIn(a.familyId)).toHaveLength(0);
    expect(liveRowsIn(b.familyId)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Decline — the mirror, and why it is not symmetric
// ---------------------------------------------------------------------------

describe("declining in one family says nothing about another", () => {
  it("does NOT retire the row or the invite in B", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");

    await run.decline("captainA", { familyId: a.familyId, requestId: a.requestId });

    expect(statusOf(a)).toBe("declined");
    // B's captain never refused anything and is still entitled to decide.
    expect(statusOf(b)).toBe("pending");
    expect(inviteOf(b)?.status).toBe("accepted");
  });

  it("re-points the FR-88 stamp at B's surviving row instead of clearing it", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");

    await run.decline("captainA", { familyId: a.familyId, requestId: a.requestId });

    // Cleared, the child's screen would stop saying "waiting" while a captain genuinely is
    // deciding — the exact false state FR-88 exists to prevent, arriving from the other side.
    expect(stampOn("kid")).toMatchObject({
      familyId: b.familyId,
      requestId: b.requestId,
    });
    // FR-60(c) leaves the account alone precisely because that decision is still live.
    expect(db().store.has("users/kid")).toBe(true);
    expect(holder.deletedAuthUsers).toEqual([]);
  });

  it("writes the child's user doc exactly once while doing it", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    await familyAwaiting("captainB", "Neighbours");

    const groups = await batchWriteGroups(() =>
      run.decline("captainA", { familyId: a.familyId, requestId: a.requestId })
    );

    const declineBatch = groupContaining(
      groups,
      `families/${a.familyId}/pending/${a.requestId}`
    );
    expect(declineBatch.filter((path) => path === "users/kid")).toHaveLength(1);
    for (const group of groups) {
      expect(group).toEqual([...new Set(group)]);
    }
  });

  it("clears the stamp outright when no other family is deciding", async () => {
    // Sticky post-revocation child: FR-60(c) spares the account, so the field is observable.
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      wasEverInFamily: true,
    });
    const a = await familyAwaiting("captainA", "Hammers");

    await run.decline("captainA", { familyId: a.familyId, requestId: a.requestId });

    expect(db().store.has("users/kid")).toBe(true);
    expect(stampOn("kid")).toBe("__delete__");
  });

  it("never mints a stamp on an adult, even one with a live row elsewhere", async () => {
    db().seed("users/grown", { userName: "Grown" });
    const a = await familyAwaiting("captainA", "Hammers", "grown");
    const b = await familyAwaiting("captainB", "Neighbours", "grown");

    await run.decline("captainA", { familyId: a.familyId, requestId: a.requestId });

    // An adult carrying this field raises the child's "ask a parent" banner on an adult's
    // home screen — `ChildFamilyPromptPolicy` resolves pending before it classifies.
    expect(stampOn("grown")).toBe("__delete__");
    expect(statusOf(b)).toBe("pending");
  });

  it("still declines a row whose account is already gone", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    await familyAwaiting("captainB", "Neighbours");
    db().store.delete("users/kid");

    await expect(
      run.decline("captainA", { familyId: a.familyId, requestId: a.requestId })
    ).resolves.toMatchObject({ success: true });
    expect(statusOf(a)).toBe("declined");
  });
});

// ---------------------------------------------------------------------------
// The query itself
// ---------------------------------------------------------------------------

describe("findLivePendingJoinRequestsInOtherFamilies", () => {
  it("excludes the caller's own family and any resolved row", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    const b = await familyAwaiting("captainB", "Neighbours");
    const c = await familyAwaiting("captainC", "Cousins");
    db().seed(`families/${c.familyId}/pending/${c.requestId}`, {
      ...db().store.get(`families/${c.familyId}/pending/${c.requestId}`)!,
      status: "declined",
    });

    const result = await findLivePendingJoinRequestsInOtherFamilies(db() as any, {
      userId: "kid",
      excludeFamilyId: a.familyId,
    });

    expect(result.rows.map((doc) => doc.id)).toEqual([b.requestId]);
    expect(result.truncated).toBe(false);
  });

  /** No silent caps (SRS §): a bound that hides rows must SAY it hid them. */
  it("reports truncation rather than dropping rows quietly", async () => {
    const a = await familyAwaiting("captainA", "Hammers");
    await familyAwaiting("captainB", "Neighbours");
    await familyAwaiting("captainC", "Cousins");

    const result = await findLivePendingJoinRequestsInOtherFamilies(db() as any, {
      userId: "kid",
      excludeFamilyId: a.familyId,
      limit: 1,
    });

    expect(result.rows).toHaveLength(1);
    expect(result.truncated).toBe(true);
  });
});
