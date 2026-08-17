/**
 * The unanswered-join-request clock — device pass 2026-08-17.
 *
 * A share code expired, and the pending row it had produced sat in the captain's queue
 * unchanged and still approvable, because nothing in the codebase owned a pending row's
 * lifetime: `expireInvitesAndCodes` swept invites, trip invites and share codes, and never
 * looked at `families/{id}/pending`.
 *
 * What is pinned here is the SHAPE of the answer, not just that rows eventually go away:
 *
 *   - the 15-minute redemption clock is NOT the decision clock (a row outlives its invite);
 *   - the decision clock is 7 days, and it is the SAME 7 as FR-60(c)'s account window, so the
 *     `hasLiveJoinRequest` veto and the row it vetoes on can never disagree;
 *   - retiring a row is one atomic act covering three things that stop being true together:
 *     the row, FR-88's `pendingFamilyRequest` stamp, and the still-`accepted` invite behind it.
 *
 * `FakeFirestore` stores the delete sentinel verbatim rather than removing the key, so
 * `"__delete__"` in the store IS the field-delete reaching the batch.
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
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { FakeWriteBatch } from "./testSupport/fakeFirestore";
import {
  PENDING_JOIN_REQUEST_TTL_DAYS,
  sweepUnansweredJoinRequests,
  unansweredJoinRequestCutoffMillis,
} from "./pendingJoinRequestExpiry";
import {
  PENDING_FAMILY_REQUEST_FIELD,
  findLivePendingJoinRequests,
} from "./familyJoinRequestIntegrity";
import { PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS } from "./provisionalChildAccounts";

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_800_000_000_000;

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

/** A child with a live row awaiting a captain, seeded at an explicit age in days. */
function seedAwaitingRow(input: {
  familyId: string;
  requestId: string;
  userId: string;
  ageDays: number;
  inviteId?: string;
  status?: string;
  seedUserDoc?: boolean;
  inviteStatus?: string;
}): void {
  const inviteId = input.inviteId ?? `inv-${input.requestId}`;
  db().seed(`families/${input.familyId}/pending/${input.requestId}`, {
    userId: input.userId,
    requestedBy: input.userId,
    method: "code",
    status: input.status ?? "pending",
    createdAt: NOW - input.ageDays * DAY,
    origin: "share_code",
    originInviteId: inviteId,
  });
  if (input.seedUserDoc !== false) {
    db().seed(`users/${input.userId}`, {
      isChildAccount: true,
      [PENDING_FAMILY_REQUEST_FIELD]: {
        familyId: input.familyId,
        requestId: input.requestId,
        createdAt: NOW - input.ageDays * DAY,
      },
    });
  }
  db().seed(`invites/${inviteId}`, {
    type: "family",
    familyId: input.familyId,
    toUserId: input.userId,
    status: input.inviteStatus ?? "accepted",
    // Long lapsed: the 15-minute redemption window closed days ago and is irrelevant here.
    expiresAt: NOW - input.ageDays * DAY + 15 * 60 * 1000,
  });
}

function sweep(overrides: { maxRetired?: number; pageSize?: number } = {}) {
  return sweepUnansweredJoinRequests(db(), {
    cutoffMillis: unansweredJoinRequestCutoffMillis(NOW),
    ...overrides,
  });
}

function row(familyId: string, requestId: string) {
  return db().store.get(`families/${familyId}/pending/${requestId}`);
}

/** Every document path a body writes through a batch — the one-write-per-doc invariant. */
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

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
});

describe("the decision clock is not the redemption clock", () => {
  it("leaves a row alive long after its 15-minute invite lapsed", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 3 });

    const result = await sweep();

    expect(result.retired).toBe(0);
    expect(row("fam", "req")?.status).toBe("pending");
    // The whole point: the invite behind it expired days ago and the row does not care.
    expect(db().store.get("invites/inv-req")?.expiresAt).toBeLessThan(NOW);
  });

  it("retires a row nobody answered inside the window", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 8 });

    const result = await sweep();

    expect(result).toMatchObject({ retired: 1, truncated: false });
    expect(row("fam", "req")).toMatchObject({
      status: "expired",
      resolvedAt: "__serverTimestamp__",
    });
  });

  it("expires on the seventh day boundary, not the fifteenth minute", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "young", userId: "a", ageDays: 6.9 });
    seedAwaitingRow({ familyId: "fam", requestId: "old", userId: "b", ageDays: 7.1 });

    await sweep();

    expect(row("fam", "young")?.status).toBe("pending");
    expect(row("fam", "old")?.status).toBe("expired");
  });
});

describe("retirement is one atomic act", () => {
  it("clears the FR-88 stamp with the row", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 8 });

    await sweep();

    expect(db().store.get("users/kid")?.[PENDING_FAMILY_REQUEST_FIELD]).toBe("__delete__");
  });

  it("retires the still-accepted invite the row was minted from", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 8 });

    await sweep();

    expect(db().store.get("invites/inv-req")).toMatchObject({
      status: "expired",
      respondedAt: "__serverTimestamp__",
    });
  });

  it("does not rewrite an invite that is already terminal", async () => {
    seedAwaitingRow({
      familyId: "fam",
      requestId: "req",
      userId: "kid",
      ageDays: 8,
      inviteStatus: "declined",
    });

    await sweep();

    expect(db().store.get("invites/inv-req")?.status).toBe("declined");
    expect(db().store.get("invites/inv-req")?.respondedAt).toBeUndefined();
  });

  it("retires a row whose account is already gone, rather than failing the batch", async () => {
    seedAwaitingRow({
      familyId: "fam",
      requestId: "req",
      userId: "ghost",
      ageDays: 8,
      seedUserDoc: false,
    });

    await expect(sweep()).resolves.toMatchObject({ retired: 1 });
    expect(row("fam", "req")?.status).toBe("expired");
  });

  it("writes each user doc at most once when a child is pending in two families", async () => {
    seedAwaitingRow({ familyId: "famA", requestId: "reqA", userId: "kid", ageDays: 8 });
    seedAwaitingRow({ familyId: "famB", requestId: "reqB", userId: "kid", ageDays: 9 });

    const paths = await batchWritePaths(() => sweep());
    const userWrites = paths.filter((path) => path.startsWith("users/"));

    expect(userWrites).toEqual(["users/kid"]);
    expect(row("famA", "reqA")?.status).toBe("expired");
    expect(row("famB", "reqB")?.status).toBe("expired");
  });
});

describe("scope and idempotence", () => {
  it("ignores rows that already carry a decision", async () => {
    for (const status of ["approved", "declined", "expired"]) {
      seedAwaitingRow({
        familyId: "fam",
        requestId: `req-${status}`,
        userId: `u-${status}`,
        ageDays: 30,
        status,
      });
    }

    const result = await sweep();

    expect(result).toMatchObject({ scanned: 0, retired: 0 });
    expect(row("fam", "req-approved")?.status).toBe("approved");
    expect(row("fam", "req-declined")?.status).toBe("declined");
  });

  it("is a genuine no-op on a second run", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 8 });
    await sweep();
    const writesAfterFirst = db().writeCount;

    const second = await sweep();

    expect(second).toMatchObject({ scanned: 0, retired: 0 });
    expect(db().writeCount).toBe(writesAfterFirst);
  });

  it("truncates at the per-run bound and finishes on the next run", async () => {
    for (let i = 0; i < 5; i += 1) {
      seedAwaitingRow({
        familyId: "fam",
        requestId: `req-${i}`,
        userId: `kid-${i}`,
        ageDays: 8 + i,
      });
    }

    const first = await sweep({ maxRetired: 2, pageSize: 2 });
    expect(first).toMatchObject({ retired: 2, truncated: true });

    const second = await sweep({ pageSize: 2 });
    expect(second).toMatchObject({ retired: 3, truncated: false });
    for (let i = 0; i < 5; i += 1) {
      expect(row("fam", `req-${i}`)?.status).toBe("expired");
    }
  });
});

describe("composition with FR-60(c)", () => {
  /**
   * The two clocks are the same clock. If they were not, either the account outlives every
   * decision that could be made about it, or the `hasLiveJoinRequest` veto pins it open
   * forever. Pinned so a later edit to one number cannot silently split them.
   */
  it("uses the same window as the provisional-account sweep", () => {
    expect(PENDING_JOIN_REQUEST_TTL_DAYS).toBe(PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS);
  });

  it("lifts the live-request veto that was holding the account open", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "req", userId: "kid", ageDays: 8 });
    expect(
      await findLivePendingJoinRequests(db() as any, { familyId: "fam", userId: "kid" })
    ).toHaveLength(1);

    await sweep();

    expect(
      await findLivePendingJoinRequests(db() as any, { familyId: "fam", userId: "kid" })
    ).toHaveLength(0);
  });

  it("leaves a fresh redemption free to mint a new row", async () => {
    seedAwaitingRow({ familyId: "fam", requestId: "old", userId: "kid", ageDays: 8 });
    await sweep();

    // What `respondToFamilyInvite_UserStep` asks before deciding to reuse or mint.
    const live = await findLivePendingJoinRequests(db() as any, {
      familyId: "fam",
      userId: "kid",
    });

    expect(live).toHaveLength(0);
  });
});
