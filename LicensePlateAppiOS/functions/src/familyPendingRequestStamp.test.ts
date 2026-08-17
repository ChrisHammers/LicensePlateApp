/**
 * FR-88 (F-45) — `users/{uid}.pendingFamilyRequest`, the server's answer to "is anyone
 * actually deciding about me?"
 *
 * DEVICE PASS 2026-08-17. "Waiting for your family's approval" was a device guess: a
 * UserDefaults uid written at share-code redemption, cleared in exactly two places — the
 * child stops being a restricted unconsented child (they were approved), and identity detach
 * (the account was deleted). A DECLINE that deletes nothing clears neither, and FR-60(c)
 * deliberately spares a child with `wasEverInFamily === true`. That child sat in front of a
 * screen promising an answer from a captain who had already said no, with no way to check:
 * `firestore.rules` limits `families/{id}/pending` reads to family members, and a pending
 * child is by definition not one.
 *
 * The fix moves the truth onto the one document the child can always read — their own. What
 * is pinned here is the invariant that makes it trustworthy: the stamp and the row it mirrors
 * are written and retired by the SAME batch, on every path either of them can take.
 *
 * `FakeFirestore` stores the delete sentinel verbatim rather than removing the key (the same
 * convention `fr60ConsentExits.test.ts` asserts against for `childDeclaredAt`), so
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
  inactivateFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  PENDING_FAMILY_REQUEST_FIELD,
  buildPendingFamilyRequestStamp,
} from "./familyJoinRequestIntegrity";
import { deleteProvisionalChildAccountIfNeverConsented } from "./provisionalChildAccounts";

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
  inactivateFamily: (uid: string, familyId: string) =>
    (inactivateFamily as unknown as Runnable).run({ familyId }, context(uid)),
};

function rowsIn(familyId: string): Array<[string, Record<string, unknown>]> {
  const prefix = `families/${familyId}/pending/`;
  return [...db().store.entries()]
    .filter(([path]) => path.startsWith(prefix))
    .map(([path, data]) => [path.slice(prefix.length), data]);
}

function liveRowsIn(familyId: string): Array<[string, Record<string, unknown>]> {
  return rowsIn(familyId).filter(([, data]) => data.status === "pending");
}

function stampOn(userId: string): unknown {
  return db().store.get(`users/${userId}`)?.[PENDING_FAMILY_REQUEST_FIELD];
}

/**
 * Every document path `body` writes through a batch, in order.
 *
 * Firestore rejects a commit that carries two writes for the same document, and
 * `FakeFirestore` does not — it applies both and the outcome looks correct. So the
 * one-write-per-doc invariant has to be asserted on the operations themselves.
 */
async function batchWritePaths(body: () => Promise<unknown>): Promise<string[]> {
  const paths: string[] = [];
  const proto = FakeWriteBatch.prototype as unknown as Record<string, any>;
  const originals = { set: proto.set, update: proto.update, delete: proto.delete };
  for (const op of ["set", "update", "delete"] as const) {
    proto[op] = function (ref: { path: string }, ...rest: unknown[]) {
      paths.push(ref.path);
      return originals[op].call(this, ref, ...rest);
    };
  }
  try {
    await body();
  } finally {
    Object.assign(proto, originals);
  }
  return paths;
}

/** Family + code + one accepted invite: a child with a live request awaiting a captain. */
async function childAwaitingApproval(
  child = "kid"
): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const { code } = await run.createShareCode("captain", familyId);
  const { inviteId } = await run.redeemShareCode(child, code);
  await run.acceptInvite(child, inviteId);
  const [requestId] = liveRowsIn(familyId).find(([, row]) => row.userId === child)!;
  return { familyId, requestId };
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;

  db().seed("users/captain", { userName: "Captain" });
  // The child as the local-first path leaves them: flagged, no family, never in one.
  db().seed("users/kid", {
    userName: "Speedy",
    avatarId: "scout_otter",
    isChildAccount: true,
    childDeclaredAt: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// Creation
// ---------------------------------------------------------------------------

describe("FR-88: accepting an invite stamps the requester's own user doc", () => {
  it("writes familyId + requestId + a server timestamp naming the live row", async () => {
    const { familyId, requestId } = await childAwaitingApproval();

    expect(stampOn("kid")).toEqual(
      buildPendingFamilyRequestStamp({
        familyId,
        requestId,
        createdAt: "__serverTimestamp__",
      })
    );
  });

  /**
   * The row and its shadow are ONE write. Failing the commit is the only way to prove that
   * from outside: a stamp written before the batch would have survived the failure, and one
   * written after it would need code the throw never reaches.
   */
  it("stamp and row are the same batch — a failed commit lands neither", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);

    const original = FakeWriteBatch.prototype.commit;
    FakeWriteBatch.prototype.commit = async function failing() {
      throw new Error("commit failed");
    };
    try {
      await expect(run.acceptInvite("kid", inviteId)).rejects.toThrow("commit failed");
    } finally {
      FakeWriteBatch.prototype.commit = original;
    }

    expect(stampOn("kid")).toBeUndefined();
    expect(liveRowsIn(familyId)).toHaveLength(0);
  });

  /**
   * SCOPE. `ChildFamilyPromptPolicy` resolves pending BEFORE its restriction classification,
   * so a stamp on an adult's doc would raise the child's "ask a parent" banner on an adult's
   * home screen — and a consented child's banner is hidden today and must stay hidden.
   */
  it.each([
    ["an adult", { userName: "Grown" }],
    [
      "a consented child already in a family",
      { userName: "Kid", isChildAccount: true, activeFamilyId: "otherFam" },
    ],
  ])("writes no stamp for %s", async (_label, userData) => {
    db().seed("users/joiner", userData);
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("joiner", code);
    await run.acceptInvite("joiner", inviteId);

    expect(liveRowsIn(familyId)).toHaveLength(1);
    expect(stampOn("joiner")).toBeUndefined();
  });

  it("accepts normally when the requester has no user doc at all", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    db().store.delete("users/kid");

    await expect(run.acceptInvite("kid", inviteId)).resolves.toMatchObject({
      success: true,
    });
    // A set-merge would have MINTED a user doc holding nothing but the stamp.
    expect(db().store.has("users/kid")).toBe(false);
    expect(liveRowsIn(familyId)).toHaveLength(1);
  });

  /**
   * F-44's dedupe refresh: the second accept reuses the surviving row, so the one stamp must
   * name that row and not the one it superseded.
   */
  it("re-points the stamp at the surviving row on the dedupe-refresh path", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);

    const first = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", first.inviteId);
    const second = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", second.inviteId);

    const live = liveRowsIn(familyId);
    expect(live).toHaveLength(1);
    expect(stampOn("kid")).toMatchObject({ familyId, requestId: live[0][0] });
  });
});

// ---------------------------------------------------------------------------
// Resolution — every path clears it
// ---------------------------------------------------------------------------

describe("FR-88: every resolution clears the stamp", () => {
  it("approve clears it in the membership batch", async () => {
    const { familyId, requestId } = await childAwaitingApproval();

    await run.approve("captain", {
      familyId,
      requestId,
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });

    expect(stampOn("kid")).toBe("__delete__");
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(familyId);
  });

  /**
   * THE OWNER'S BUG, EXACTLY. A child with `wasEverInFamily === true` is a sticky
   * post-revocation child: FR-60(c) refuses to delete them, so the decline leaves the account
   * standing — and before this field, it left the device's "waiting" flag standing with it,
   * permanently. The account surviving is the point of the test, not an incidental detail.
   */
  it("a decline that does NOT delete the account still clears it", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      wasEverInFamily: true,
    });
    const { familyId, requestId } = await childAwaitingApproval();
    expect(stampOn("kid")).toMatchObject({ familyId, requestId });

    await run.decline("captain", { familyId, requestId });

    expect(db().store.has("users/kid")).toBe(true);
    expect(holder.deletedAuthUsers).toEqual([]);
    expect(stampOn("kid")).toBe("__delete__");
  });

  it("a decline that DOES delete the account takes the whole doc with it", async () => {
    const { familyId, requestId } = await childAwaitingApproval();

    await run.decline("captain", { familyId, requestId });

    expect(db().store.has("users/kid")).toBe(false);
    expect(holder.deletedAuthUsers).toEqual(["kid"]);
  });

  it("declines a row whose account is already gone without throwing", async () => {
    const { familyId, requestId } = await childAwaitingApproval();
    db().store.delete("users/kid");

    await expect(
      run.decline("captain", { familyId, requestId })
    ).resolves.toMatchObject({ success: true });
    expect(liveRowsIn(familyId)).toHaveLength(0);
    expect(db().store.has("users/kid")).toBe(false);
  });

  /**
   * F-44 supersede. Two rows for one child were the 2026-08-16 wedge; resolving either one
   * retires both, and the single stamp must go with them whichever row carried the decision.
   */
  it.each([
    ["approve", true],
    ["decline", false],
  ])("clears it when %s retires a duplicate row alongside the decided one", async (
    _label,
    isApprove
  ) => {
    const { familyId, requestId } = await childAwaitingApproval();
    db().seed(`families/${familyId}/pending/legacy-dupe`, {
      userId: "kid",
      status: "pending",
      createdAt: Date.now(),
      origin: "share_code",
      originInviteId: "inv-legacy",
    });

    if (isApprove) {
      await run.approve("captain", {
        familyId,
        requestId,
        isChild: true,
        consentAcknowledged: true,
        guardianAffirmed: true,
      });
      expect(
        db().store.get(`families/${familyId}/pending/legacy-dupe`)?.status
      ).toBe("expired");
      expect(stampOn("kid")).toBe("__delete__");
    } else {
      await run.decline("captain", { familyId, requestId });
      expect(
        db().store.get(`families/${familyId}/pending/legacy-dupe`)?.status
      ).toBe("declined");
      // The decline deleted this never-consented account outright, stamp included.
      expect(db().store.has("users/kid")).toBe(false);
    }
    expect(liveRowsIn(familyId)).toHaveLength(0);
  });

  /**
   * The expiry half of FR-60(c): a family invite that lapses unaccepted runs this cleanup,
   * and it removes the user document entirely — so there is no stamp left to dangle.
   */
  it("FR-60(c) account cleanup takes the stamp with the document", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      isChildAccount: true,
      childDeclaredAt: Date.now(),
      [PENDING_FAMILY_REQUEST_FIELD]: buildPendingFamilyRequestStamp({
        familyId: "ghost",
        requestId: "ghost-row",
        createdAt: Date.now(),
      }),
    });

    const result = await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "kid", actorId: "system_retention", clientMetadata: null },
      {
        deleteAuthUser: async (uid: string) => {
          holder.deletedAuthUsers.push(uid);
        },
      }
    );

    expect(result).toEqual({ deleted: true, reason: "deleted" });
    expect(db().store.has("users/kid")).toBe(false);
  });

  /**
   * A family that stops existing stops deciding. The row used to be simply orphaned in a
   * subcollection nobody would open again — the same stranding as the decline, by a different
   * door — so it is closed the same way and in the same batch.
   */
  it("inactivating a family retires the orphan row and clears the stamp", async () => {
    const { familyId, requestId } = await childAwaitingApproval();
    expect(stampOn("kid")).toMatchObject({ familyId, requestId });

    await run.inactivateFamily("captain", familyId);

    expect(db().store.get(`families/${familyId}/pending/${requestId}`)?.status).toBe(
      "expired"
    );
    expect(liveRowsIn(familyId)).toHaveLength(0);
    expect(stampOn("kid")).toBe("__delete__");
    // The account is left for the FR-77 backstop, which no live row blocks any more.
    expect(db().store.has("users/kid")).toBe(true);
  });

  /**
   * Both collisions are reachable on legacy data — F-44 duplicate rows for one uid, and a row
   * left live beside a membership granted on its sibling — and either one would make the
   * COMMIT invalid rather than merely redundant.
   */
  it("inactivation writes each user doc at most once, duplicates and members included", async () => {
    const { familyId, requestId } = await childAwaitingApproval();
    // A second live row for the same child: the pre-F-44 wedge, seeded directly.
    db().seed(`families/${familyId}/pending/legacy-dupe`, {
      userId: "kid",
      status: "pending",
      createdAt: Date.now(),
      origin: "share_code",
      originInviteId: "inv-legacy",
    });
    // And a live row naming someone who is ALREADY a member — here, the captain.
    db().seed(`families/${familyId}/pending/member-row`, {
      userId: "captain",
      status: "pending",
      createdAt: Date.now(),
      origin: "family_invite",
      originInviteId: "inv-captain",
    });

    const paths = await batchWritePaths(() => run.inactivateFamily("captain", familyId));
    const userWrites = paths.filter((path) => path.startsWith("users/"));

    expect(userWrites).toEqual([...new Set(userWrites)]);
    expect(db().store.get(`families/${familyId}/pending/${requestId}`)?.status).toBe(
      "expired"
    );
    expect(db().store.get(`families/${familyId}/pending/legacy-dupe`)?.status).toBe(
      "expired"
    );
    expect(liveRowsIn(familyId)).toHaveLength(0);
    expect(stampOn("kid")).toBe("__delete__");
    // The captain's ONE write carried both jobs: the membership exit and the stamp clear.
    expect(stampOn("captain")).toBe("__delete__");
    expect(db().store.get("users/captain")?.activeFamilyId).toBe("__delete__");
  });
});
