/**
 * F-44 — duplicate join requests, and the account deletion they used to trigger.
 *
 * DEVICE PASS 2026-08-16, dev project roadtrip-royale-dev-d2652. The owner entered one family
 * share code twice from the same child account. Each entry minted its own invite, each invite
 * was accepted, and the captain's queue showed two identical "Pending User" rows for a single
 * child. Resolving either one ran FR-60(c)'s never-consented cleanup — visible in the
 * function log as
 *
 *   approveFamilyJoinRequest_CaptainStep: FR-78 RevenueCat deletion skipped for
 *   oNnMQ7krxNV83NqmgAeAwZhwHou2: no secret API key configured
 *
 * followed immediately by `onAuthUserDeleted` — and DELETED the child's whole account while
 * the other row was still pending. That row then named a uid that no longer existed:
 * approving it threw `not-found "User not found"` forever, and the captain had a request they
 * could neither approve nor make sense of.
 *
 * Three independent things are pinned here, because any one of them alone closes the wedge
 * and all three should hold:
 *
 *   (a) the second row never gets created — `redeemShareCode` reuses a live invite and
 *       `respondToFamilyInvite_UserStep` reuses a live row;
 *   (b) a resolution tolerates duplicates that already exist, in either order, and tolerates
 *       an account that is already gone;
 *   (c) `deleteProvisionalChildAccountIfNeverConsented` refuses to delete an account that
 *       still holds a pending consent decision, whichever path calls it.
 *
 * Plus FR-86: the row carries the child's username and avatar so the guardian knows who they
 * are affirming for — and carries NOTHING else about them.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  deletedAuthUsers: [] as string[],
  /** Every uid the FR-60(c) cleanup was ASKED to delete, whether or not it went through. */
  cleanupCalls: [] as string[],
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

/**
 * The deletion spy. It calls straight through to the real implementation — the point is not
 * to stub the cleanup out but to record every uid it is pointed at, so "approve did not even
 * ASK to delete the account it was approving" is assertable as a property of the call graph
 * rather than inferred from surviving documents.
 */
vi.mock("./provisionalChildAccounts", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./provisionalChildAccounts")>();
  return {
    ...actual,
    deleteProvisionalChildAccountIfNeverConsented: async (
      db: never,
      input: { userId: string },
      deps?: never
    ) => {
      holder.cleanupCalls.push(input.userId);
      return actual.deleteProvisionalChildAccountIfNeverConsented(db, input as never, deps);
    },
  };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  PENDING_REQUEST_IDENTITY_FIELDS,
  buildPendingRequestIdentity,
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

function invitesTo(userId: string): Array<Record<string, unknown>> {
  return [...db().store.entries()]
    .filter(([path]) => path.startsWith("invites/"))
    .map(([, data]) => data)
    .filter((data) => data.toUserId === userId);
}

function liveInvitesTo(userId: string): Array<Record<string, unknown>> {
  return invitesTo(userId).filter(
    (data) => data.status === "pending" || data.status === "accepted"
  );
}

/** The whole owner sequence: create a family, mint a code, redeem it TWICE, accept both. */
async function doubleRedeem(): Promise<{ familyId: string; code: string }> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const { code } = await run.createShareCode("captain", familyId);

  const first = await run.redeemShareCode("kid", code);
  await run.acceptInvite("kid", first.inviteId);
  const second = await run.redeemShareCode("kid", code);
  await run.acceptInvite("kid", second.inviteId);

  return { familyId, code };
}

/**
 * The wedged state as it exists on the owner's dev project TODAY: two live rows for one uid,
 * produced by the pre-fix code. Seeded directly, because the fixed callables can no longer
 * create it — and the recovery requirement is precisely that the fixed decline must clear
 * rows the broken code left behind.
 */
async function seedLegacyDuplicateRows(): Promise<{
  familyId: string;
  requestIds: [string, string];
}> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const lineage = { origin: "share_code", originInviteId: "inv-1", originCodeId: "code-1" };
  db().seed(`families/${familyId}/pending/legacy-a`, {
    userId: "kid",
    requestedBy: "captain",
    method: "code",
    status: "pending",
    createdAt: Date.now(),
    ...lineage,
  });
  db().seed(`families/${familyId}/pending/legacy-b`, {
    userId: "kid",
    requestedBy: "captain",
    method: "code",
    status: "pending",
    createdAt: Date.now(),
    ...lineage,
    originInviteId: "inv-2",
  });
  return { familyId, requestIds: ["legacy-a", "legacy-b"] };
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;
  holder.cleanupCalls.length = 0;

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
// (a) The duplicate never gets created
// ---------------------------------------------------------------------------

describe("F-44 (a): double redemption yields ONE live pending row", () => {
  it("reuses the invite and the row instead of minting rivals", async () => {
    const { familyId } = await doubleRedeem();

    expect(liveRowsIn(familyId)).toHaveLength(1);
    expect(rowsIn(familyId)).toHaveLength(1);
    expect(liveInvitesTo("kid")).toHaveLength(1);
  });

  it("re-stamps the refreshed row's lineage onto the invite that was just accepted", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);

    const first = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", first.inviteId);
    const second = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", second.inviteId);

    const [, row] = liveRowsIn(familyId)[0];
    expect(row.origin).toBe("share_code");
    expect(row.originInviteId).toBe(second.inviteId);
  });

  it("a repeat accept is idempotent, not 'Invite already responded to'", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);

    await run.acceptInvite("kid", inviteId);
    await expect(run.acceptInvite("kid", inviteId)).resolves.toMatchObject({
      success: true,
    });
    expect(liveRowsIn(familyId)).toHaveLength(1);
  });

  it("still refuses to re-accept an invite that was DECLINED", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);

    await (respondToFamilyInvite_UserStep as unknown as Runnable).run(
      { inviteId, response: "decline" },
      context("kid")
    );

    await expect(run.acceptInvite("kid", inviteId)).rejects.toMatchObject({
      code: "failed-precondition",
      message: "Invite already responded to",
    });
    expect(liveRowsIn(familyId)).toHaveLength(0);
  });

  it("two DIFFERENT children in one family still get one row each", async () => {
    db().seed("users/sibling", {
      userName: "Zoom",
      avatarId: "navigator_raccoon",
      isChildAccount: true,
    });
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);

    for (const child of ["kid", "sibling"]) {
      const { inviteId } = await run.redeemShareCode(child, code);
      await run.acceptInvite(child, inviteId);
    }

    const live = liveRowsIn(familyId);
    expect(live).toHaveLength(2);
    expect(live.map(([, row]) => row.userId).sort()).toEqual(["kid", "sibling"]);
  });
});

// ---------------------------------------------------------------------------
// (b) + (c) Approve tolerates a duplicate and never deletes its target
// ---------------------------------------------------------------------------

describe("F-44 (b/c): approve with a duplicate present", () => {
  it("succeeds, admits the child, and retires the duplicate row", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();

    await run.approve("captain", {
      familyId,
      requestId: requestIds[0],
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });

    expect(db().store.get(`families/${familyId}/members/kid`)?.isChild).toBe(true);
    expect(db().store.get(`families/${familyId}/pending/${requestIds[0]}`)?.status).toBe(
      "approved"
    );
    // "expired", never "declined": the child was admitted, and a declined sibling row would
    // tell them the opposite of what happened.
    expect(db().store.get(`families/${familyId}/pending/${requestIds[1]}`)?.status).toBe(
      "expired"
    );
    expect(liveRowsIn(familyId)).toHaveLength(0);
  });

  it("NEVER asks to delete the account it is approving", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();

    await run.approve("captain", {
      familyId,
      requestId: requestIds[0],
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    });

    // The spy, not the leftovers: the approval path must not even reach the cleanup.
    expect(holder.cleanupCalls).toEqual([]);
    expect(holder.deletedAuthUsers).toEqual([]);
    expect(db().store.get("users/kid")).toBeDefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(familyId);
    expect(db().store.get("users/kid")?.wasEverInFamily).toBe(true);
  });

  it("survives an FCM push that throws — the membership is already committed", async () => {
    const admin = (await import("firebase-admin")) as unknown as {
      messaging: () => { send: (m: unknown) => Promise<string> };
    };
    const original = admin.messaging;
    (admin as { messaging: unknown }).messaging = () => ({
      send: async () => {
        throw new Error("messaging/registration-token-not-registered");
      },
    });
    db().seed("users/kid/private/fcm", { token: "stale-token" });

    try {
      const { familyId, requestIds } = await seedLegacyDuplicateRows();
      await run.approve("captain", {
        familyId,
        requestId: requestIds[0],
        isChild: true,
        consentAcknowledged: true,
        guardianAffirmed: true,
      });
      expect(db().store.get(`families/${familyId}/members/kid`)).toBeDefined();
    } finally {
      (admin as { messaging: unknown }).messaging = original;
    }
  });

  it("re-approving an already-approved row is an idempotent success", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();
    const payload = {
      familyId,
      requestId: requestIds[0],
      isChild: true,
      consentAcknowledged: true,
      guardianAffirmed: true,
    };

    await run.approve("captain", payload);
    await expect(run.approve("captain", payload)).resolves.toMatchObject({
      success: true,
    });
  });
});

// ---------------------------------------------------------------------------
// (b) + (d) Decline tolerates duplicates, any order, and a vanished account
// ---------------------------------------------------------------------------

describe("F-44 (b/d): decline clears wedged rows", () => {
  it("resolves BOTH duplicate rows in one operation and then deletes the account", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();

    await run.decline("captain", { familyId, requestId: requestIds[0] });

    expect(db().store.get(`families/${familyId}/pending/${requestIds[0]}`)?.status).toBe(
      "declined"
    );
    expect(db().store.get(`families/${familyId}/pending/${requestIds[1]}`)?.status).toBe(
      "declined"
    );
    // FR-60(c) still fires — consent was refused and no row survives to be stranded.
    expect(db().store.has("users/kid")).toBe(false);
    expect(holder.deletedAuthUsers).toEqual(["kid"]);
  });

  it.each([
    ["first then second", 0, 1],
    ["second then first", 1, 0],
  ])("clears two rows for one uid declined %s", async (_label, a, b) => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();

    await run.decline("captain", { familyId, requestId: requestIds[a] });
    // The second tap lands on a row this operation already retired — and must still succeed,
    // because the captain has no way to know that and will tap it.
    await expect(
      run.decline("captain", { familyId, requestId: requestIds[b] })
    ).resolves.toMatchObject({ success: true });

    expect(liveRowsIn(familyId)).toHaveLength(0);
  });

  it("declines a stale row whose account is already GONE, with no error", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();
    db().store.delete("users/kid");

    await expect(
      run.decline("captain", { familyId, requestId: requestIds[0] })
    ).resolves.toMatchObject({ success: true });

    expect(liveRowsIn(familyId)).toHaveLength(0);
    expect(holder.deletedAuthUsers).toEqual([]);
  });

  it("re-declining an already-declined row is an idempotent success", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();

    await run.decline("captain", { familyId, requestId: requestIds[0] });
    await expect(
      run.decline("captain", { familyId, requestId: requestIds[0] })
    ).resolves.toMatchObject({ success: true });
  });

  it("still refuses to APPROVE a row that was already declined", async () => {
    const { familyId, requestIds } = await seedLegacyDuplicateRows();
    await run.decline("captain", { familyId, requestId: requestIds[0] });

    await expect(
      run.approve("captain", {
        familyId,
        requestId: requestIds[1],
        isChild: true,
        consentAcknowledged: true,
        guardianAffirmed: true,
      })
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "Request already resolved",
    });
  });
});

// ---------------------------------------------------------------------------
// (c) The cleanup itself refuses to strand a live decision
// ---------------------------------------------------------------------------

describe("F-44 (c): cleanup no-ops while a consent decision is live", () => {
  it("leaves a provisional child alone when a pending row is still awaiting a captain", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);

    const result = await deleteProvisionalChildAccountIfNeverConsented(db() as never, {
      userId: "kid",
      actorId: "system_retention",
      clientMetadata: null,
    });

    expect(result).toEqual({ deleted: false, reason: "live_join_request" });
    expect(db().store.get("users/kid")).toBeDefined();
    expect(liveRowsIn(familyId)).toHaveLength(1);
  });

  it("deletes once the row is resolved", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    db().seed(`families/${familyId}/pending/resolved`, {
      userId: "kid",
      status: "declined",
      createdAt: Date.now(),
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

  it("a pending row in ANOTHER family also protects the account", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);

    db().seed("users/otherCaptain", { userName: "Other" });
    const other = await run.createFamily("otherCaptain", "Neighbours");
    db().seed(`families/${other.familyId}/pending/stale`, {
      userId: "kid",
      status: "pending",
      createdAt: Date.now(),
      origin: "share_code",
      originInviteId: "inv-x",
    });

    // Declining in the FIRST family resolves only that family's rows; the second family's
    // captain still has a decision to make, so the account must survive.
    const [requestId] = liveRowsIn(familyId)[0];
    await run.decline("captain", { familyId, requestId });

    expect(holder.cleanupCalls).toEqual(["kid"]);
    expect(db().store.get("users/kid")).toBeDefined();
    expect(holder.deletedAuthUsers).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// FR-86 (F-43) — who the guardian is affirming for, and nothing more
// ---------------------------------------------------------------------------

describe("FR-86: the pending row identifies the requester", () => {
  it("stamps userName and avatarId at creation", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);

    const [, row] = liveRowsIn(familyId)[0];
    expect(row.userName).toBe("Speedy");
    expect(row.avatarId).toBe("scout_otter");
  });

  it("carries NO contact field — the FR-43 boundary is unchanged", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      email: "kid@example.com",
      phoneNumber: "+15555550123",
      fcmToken: "device-token",
      searchableEmail: "kid@example.com",
    });
    db().seed("users/kid/private/contact", {
      email: "kid@example.com",
      phoneNumber: "+15555550123",
    });

    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);

    const [, row] = liveRowsIn(familyId)[0];
    expect(Object.keys(row).sort()).toEqual(
      [
        "avatarId",
        "createdAt",
        "method",
        "origin",
        "originCodeId",
        "originInviteId",
        "requestedBy",
        "status",
        "userId",
        "userName",
      ].sort()
    );
  });

  it("re-stamps current values on the dedupe-refresh path", async () => {
    const { familyId } = await run.createFamily("captain", "Hammers");
    const { code } = await run.createShareCode("captain", familyId);

    const first = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", first.inviteId);

    db().seed("users/kid", {
      ...db().store.get("users/kid")!,
      userName: "Speedy2",
      avatarId: "navigator_raccoon",
    });

    const second = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", second.inviteId);

    const live = liveRowsIn(familyId);
    expect(live).toHaveLength(1);
    expect(live[0][1].userName).toBe("Speedy2");
    expect(live[0][1].avatarId).toBe("navigator_raccoon");
  });

  it("omits absent fields rather than writing empty ones", () => {
    expect(buildPendingRequestIdentity({ userName: "Only" })).toEqual({ userName: "Only" });
    expect(buildPendingRequestIdentity({ userName: "", avatarId: 7 })).toEqual({});
    expect(buildPendingRequestIdentity(undefined)).toEqual({});
  });

  /**
   * The allowlist is the containment boundary, so it is pinned as a value and not merely
   * exercised. Widening it steps outside §312.5(c)(1)'s notice-and-consent exception, which
   * is what makes stamping a child's name here lawful in the first place.
   */
  it("allows exactly two fields, forever", () => {
    expect([...PENDING_REQUEST_IDENTITY_FIELDS]).toEqual(["userName", "avatarId"]);
    expect(
      buildPendingRequestIdentity({
        userName: "Speedy",
        avatarId: "scout_otter",
        email: "kid@example.com",
        phoneNumber: "+15555550123",
      })
    ).toEqual({ userName: "Speedy", avatarId: "scout_otter" });
  });
});
