/**
 * FR-77 / NP-3 row 11 — OD-3 (36 months, ALL AGES, owner 2026-08-30): the inactive-account
 * sweep.
 *
 * The property under test is the NEGATIVE one, as with every deletion sweep in this program.
 * The window is anchored on the ABSENCE of an event, so the sweep has to be provably unable to
 * fire on absent evidence: an account with no `lastDateLoggedIn` at all must be invisible to
 * it, and a value that is not a timestamp must be rejected by the guard even when the range
 * filter hands it over.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import type * as adminTypes from "firebase-admin";

const holder = vi.hoisted(() => ({ db: undefined as any }));

// Raw millis, not Timestamp objects: FakeFirestore JSON-clones every write, so a
// `{ toMillis() }` object would come back as `{}` and the range filter would never match.
// Same mock shape as provisionalChildAccounts.test.ts, extended with the statics the
// account-deletion cascade reaches (`FieldValue.increment`, `FieldPath.documentId`).
vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    increment: (n: number) => ({ __increment__: n }),
  };
  firestore.FieldPath = { documentId: () => "__name__" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT,
  LAST_AUTHENTICATED_ACTIVITY_FIELD,
  hasPendingDeletionMarker,
  inactiveAccountDeletionCutoffMillis,
  inactiveAccountRetentionDays,
  lastAuthenticatedActivityMillis,
  sweepInactiveAccounts,
} from "./inactiveAccountRetention";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

function asFirestore(fake: FakeFirestore): adminTypes.firestore.Firestore {
  return fake as unknown as adminTypes.firestore.Firestore;
}

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_800_000_000_000;
const CUTOFF = NOW - 1095 * DAY;
const STALE = CUTOFF - 30 * DAY; // last seen ~37 months ago
const RECENT = CUTOFF + 30 * DAY; // last seen ~35 months ago

let authDeleted: string[];

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  authDeleted = [];
});

function deps() {
  return {
    deleteAuthUser: async (userId: string) => {
      authDeleted.push(userId);
    },
    // Global-bound helpers (admin.firestore()) crash in the fake harness —
    // same injected fakes as revokedChildRetention.test.ts.
    accountDeletionDeps: {
      clearSearchIndexes: async () => undefined,
      deleteRevenueCatCustomer: async () => "deleted" as const,
    },
  };
}

function seedAccount(
  uid: string,
  lastSeenMillis: unknown,
  extra: Record<string, unknown> = {}
): void {
  db().seed(`users/${uid}`, {
    userName: `u-${uid}`,
    [LAST_AUTHENTICATED_ACTIVITY_FIELD]: lastSeenMillis,
    ...extra,
  });
}

async function sweep(
  options: Partial<Parameters<typeof sweepInactiveAccounts>[1]> = {}
) {
  return sweepInactiveAccounts(
    asFirestore(db()),
    { cutoffMillis: CUTOFF, actorId: "system_retention", ...options },
    deps()
  );
}

describe("OD-3 inactivity sweep: the delete case", () => {
  it("deletes an account dormant past the window, through the shared machinery", async () => {
    seedAccount("dormant", STALE);
    db().seed("user_progression/dormant", { totalXp: 120 });
    db().seed("public_lifetime_stats/dormant", { platesFound: 9 });

    const result = await sweep();

    expect(result.deleted).toBe(1);
    expect(result.deletedUids).toEqual(["dormant"]);
    expect(db().store.has("users/dormant")).toBe(false);
    expect(db().store.has("user_progression/dormant")).toBe(false);
    expect(db().store.has("public_lifetime_stats/dormant")).toBe(false);
    expect(authDeleted).toEqual(["dormant"]);

    // Evidenced with the schedule as the uid-only actor — no parent or user asked.
    const auditRows = db().docPathsMatching(
      (path, data) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_ACCOUNT_DELETED" &&
        data.subjectId === "dormant" &&
        data.actorId === "system_retention"
    );
    expect(auditRows.length).toBe(1);
  });

  it("is all ages: a dormant child account is swept on the same clock as an adult", async () => {
    seedAccount("kid", STALE, { isChildAccount: true, wasEverInFamily: true });
    seedAccount("grown", STALE);

    const result = await sweep();

    expect(result.deleted).toBe(2);
    expect(result.deletedUids.sort()).toEqual(["grown", "kid"]);
  });
});

describe("OD-3 inactivity sweep: every skip fails safe toward retention", () => {
  it("keeps an account seen inside the window", async () => {
    seedAccount("active", RECENT);
    const result = await sweep();
    expect(result.deleted).toBe(0);
    expect(db().store.has("users/active")).toBe(true);
  });

  it("cannot even see an account that has never logged in (absent evidence)", async () => {
    db().seed("users/never-signed-in", { userName: "New" });
    const result = await sweep();
    // Range operators never match a missing field: the account is structurally invisible.
    expect(result.scanned).toBe(0);
    expect(result.deleted).toBe(0);
    expect(db().store.has("users/never-signed-in")).toBe(true);
  });

  it("rejects a non-timestamp stamp the range filter handed over", async () => {
    // A boolean sorts below the cutoff number, so the filter returns it; the guard is what
    // refuses it. This is the branch that also protects the production case where an
    // explicit `null` sorts BELOW every Timestamp and is returned by a `<` query.
    seedAccount("garbled", true as unknown as number);
    const result = await sweep();
    expect(result.scanned).toBe(1);
    expect(result.skipped.missingTimestamp).toBe(1);
    expect(result.deleted).toBe(0);
    expect(db().store.has("users/garbled")).toBe(true);
  });

  it("skips an account whose parent-directed deletion is already in flight", async () => {
    seedAccount("mid-cascade", STALE, {
      pendingDeletionRequestedBy: "parent-1",
      pendingDeletionRequestedAtMillis: NOW - DAY,
    });
    const result = await sweep();
    expect(result.skipped.pendingDeletion).toBe(1);
    expect(result.deleted).toBe(0);
    expect(db().store.has("users/mid-cascade")).toBe(true);
  });

  it("skips a dormant child whose re-admission awaits the guardian's email", async () => {
    seedAccount("kid-waiting", STALE, { isChildAccount: true });
    db().seed("families/fam-1/pending/req-1", {
      userId: "kid-waiting",
      status: "awaiting_guardian",
    });
    const result = await sweep();
    expect(result.skipped.liveJoinRequest).toBe(1);
    expect(db().store.has("users/kid-waiting")).toBe(true);
  });

  it("skips a dormant account with a captain-undecided join request too", async () => {
    seedAccount("kid-pending", STALE, { isChildAccount: true });
    db().seed("families/fam-1/pending/req-2", {
      userId: "kid-pending",
      status: "pending",
    });
    const result = await sweep();
    expect(result.skipped.liveJoinRequest).toBe(1);
    expect(db().store.has("users/kid-pending")).toBe(true);
  });
});

describe("OD-3 inactivity sweep: caps are loud, never silent", () => {
  it("stops at maxDeletes and reports truncation", async () => {
    seedAccount("dormant-a", STALE);
    seedAccount("dormant-b", STALE + 1);

    const result = await sweep({ maxDeletes: 1 });
    expect(result.deleted).toBe(1);
    expect(result.truncated).toBe(true);

    // The nightly re-run finishes the remainder.
    const second = await sweep({ maxDeletes: 25 });
    expect(second.deleted).toBe(1);
  });
});

describe("OD-3 inactivity sweep: the guards, directly", () => {
  it("reads a stamp only from the two representations that exist", () => {
    expect(lastAuthenticatedActivityMillis({ lastDateLoggedIn: 1234 })).toBe(1234);
    expect(
      lastAuthenticatedActivityMillis({ lastDateLoggedIn: { toMillis: () => 99 } })
    ).toBe(99);
    // Everything else is absent evidence.
    expect(lastAuthenticatedActivityMillis({ lastDateLoggedIn: null })).toBeNull();
    expect(lastAuthenticatedActivityMillis({ lastDateLoggedIn: "2024-01-01" })).toBeNull();
    expect(lastAuthenticatedActivityMillis({ lastDateLoggedIn: {} })).toBeNull();
    expect(lastAuthenticatedActivityMillis({ lastDateLoggedIn: NaN })).toBeNull();
    expect(lastAuthenticatedActivityMillis({})).toBeNull();
    expect(lastAuthenticatedActivityMillis(undefined)).toBeNull();
  });

  it("sees a deletion marker from either half of the FR-63(b) stamp", () => {
    expect(hasPendingDeletionMarker({ pendingDeletionRequestedBy: "p" })).toBe(true);
    expect(hasPendingDeletionMarker({ pendingDeletionRequestedAtMillis: 1 })).toBe(true);
    expect(hasPendingDeletionMarker({ pendingDeletionRequestedBy: null })).toBe(false);
    expect(hasPendingDeletionMarker({ userName: "x" })).toBe(false);
    expect(hasPendingDeletionMarker(undefined)).toBe(false);
  });
});

describe("OD-3 inactivity window plumbing", () => {
  const originalEnv = process.env.INACTIVE_ACCOUNT_RETENTION_DAYS;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.INACTIVE_ACCOUNT_RETENTION_DAYS;
    } else {
      process.env.INACTIVE_ACCOUNT_RETENTION_DAYS = originalEnv;
    }
  });

  it("defaults to the OD-3 ruling and honors the dev knob", () => {
    delete process.env.INACTIVE_ACCOUNT_RETENTION_DAYS;
    expect(inactiveAccountRetentionDays()).toBe(INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT);
    expect(INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT).toBe(1095);

    process.env.INACTIVE_ACCOUNT_RETENTION_DAYS = "0";
    expect(inactiveAccountRetentionDays()).toBe(0);

    process.env.INACTIVE_ACCOUNT_RETENTION_DAYS = "not-a-number";
    expect(inactiveAccountRetentionDays()).toBe(INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT);

    expect(inactiveAccountDeletionCutoffMillis(NOW, 1095)).toBe(CUTOFF);
  });

  it("an unset-but-present knob falls to the default, not to zero", () => {
    // `Number("")` is 0, and a 0-day window would delete every account with a login stamp on
    // the first nightly run. This is the trap the parser exists to close.
    process.env.INACTIVE_ACCOUNT_RETENTION_DAYS = "";
    expect(inactiveAccountRetentionDays()).toBe(INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT);

    process.env.INACTIVE_ACCOUNT_RETENTION_DAYS = "   ";
    expect(inactiveAccountRetentionDays()).toBe(INACTIVE_ACCOUNT_RETENTION_DAYS_DEFAULT);
  });
});
