/**
 * FR-63(c) / OD-3 (12 months, owner 2026-08-30) — the abandoned-revoked-child sweep.
 *
 * Every skip direction is a pinned case: the sweep may delete ONLY a flagged child
 * whose guardianship ENDED before the cutoff, with no live membership and no live
 * join request (awaiting_guardian included — the guardian-email-unread child is the
 * last account any sweep may touch).
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type * as adminTypes from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  REVOKED_CHILD_RETENTION_DAYS_DEFAULT,
  revokedChildDeletionCutoffMillis,
  revokedChildRetentionDays,
  sweepAbandonedRevokedChildAccounts,
} from "./revokedChildRetention";

const NOW = 1_800_000_000_000;
const DAY = 24 * 60 * 60 * 1000;
const CUTOFF = NOW - 365 * DAY;
const OLD = CUTOFF - 30 * DAY; // ended ~13 months ago
const RECENT = CUTOFF + 30 * DAY; // ended ~11 months ago

function asFirestore(db: FakeFirestore): adminTypes.firestore.Firestore {
  return db as unknown as adminTypes.firestore.Firestore;
}

let db: FakeFirestore;
let authDeleted: string[];

beforeEach(() => {
  db = new FakeFirestore();
  authDeleted = [];
});

function deps() {
  return {
    deleteAuthUser: async (userId: string) => {
      authDeleted.push(userId);
    },
    // Global-bound helpers (admin.firestore()) crash in the no-vi.mock harness —
    // same injected fakes as provisionalChildAccounts.test.ts.
    accountDeletionDeps: {
      clearSearchIndexes: async () => undefined,
      deleteRevenueCatCustomer: async () => "deleted" as const,
    },
  };
}

function seedRevokedChild(
  uid: string,
  endedAtMillis: number,
  userData: Record<string, unknown> = {}
): void {
  db.seed(`users/${uid}`, { userName: `u-${uid}`, isChildAccount: true, ...userData });
  db.seed(`users/${uid}/private/guardianship`, {
    guardianUid: "guardian-1",
    familyId: "fam-1",
    endedAtMillis,
    endedReason: "parent_removed_child",
  });
}

async function sweep(options: Partial<Parameters<typeof sweepAbandonedRevokedChildAccounts>[1]> = {}) {
  return sweepAbandonedRevokedChildAccounts(
    asFirestore(db),
    { cutoffMillis: CUTOFF, actorId: "system_retention", ...options },
    deps()
  );
}

describe("OD-3 sweep: the delete case", () => {
  it("deletes a revoked child abandoned past the window, through the shared machinery", async () => {
    seedRevokedChild("kid-old", OLD);
    db.seed("user_progression/kid-old", { totalXp: 10 });
    db.seed("public_lifetime_stats/kid-old", { platesFound: 3 });

    const result = await sweep();

    expect(result.deleted).toBe(1);
    expect(result.deletedUids).toEqual(["kid-old"]);
    expect(db.store.has("users/kid-old")).toBe(false);
    expect(db.store.has("users/kid-old/private/guardianship")).toBe(false);
    expect(db.store.has("user_progression/kid-old")).toBe(false);
    expect(db.store.has("public_lifetime_stats/kid-old")).toBe(false);
    expect(authDeleted).toEqual(["kid-old"]);
    // The deletion is evidenced with the schedule as the uid-only actor.
    const auditRows = db.docPathsMatching(
      (path, data) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_ACCOUNT_DELETED" &&
        data.subjectId === "kid-old" &&
        data.actorId === "system_retention"
    );
    expect(auditRows.length).toBe(1);
  });
});

describe("OD-3 sweep: every skip fails safe toward retention", () => {
  it("keeps a revocation younger than the window", async () => {
    seedRevokedChild("kid-recent", RECENT);
    const result = await sweep();
    expect(result.deleted).toBe(0);
    expect(db.store.has("users/kid-recent")).toBe(true);
  });

  it("cannot even see a LIVE guardianship (re-grant superseded the ended record)", async () => {
    db.seed("users/kid-regranted", { isChildAccount: true });
    db.seed("users/kid-regranted/private/guardianship", {
      guardianUid: "guardian-1",
      familyId: "fam-1",
      // No endedAtMillis: a re-grant replaces the doc wholesale. The range query
      // structurally cannot match a missing field.
    });
    const result = await sweep();
    expect(result.scanned).toBe(0);
    expect(db.store.has("users/kid-regranted")).toBe(true);
  });

  it("skips a corrected adult even with an old ended guardianship", async () => {
    seedRevokedChild("now-adult", OLD, { isChildAccount: false });
    const result = await sweep();
    expect(result.skipped.notChild).toBe(1);
    expect(db.store.has("users/now-adult")).toBe(true);
  });

  it("skips a child who is back in a family", async () => {
    seedRevokedChild("kid-back", OLD, { activeFamilyId: "fam-2" });
    const result = await sweep();
    expect(result.skipped.liveMembership).toBe(1);
    expect(db.store.has("users/kid-back")).toBe(true);
  });

  it("skips a child whose re-admission awaits the guardian's email", async () => {
    seedRevokedChild("kid-waiting", OLD);
    db.seed("families/fam-3/pending/req-1", {
      userId: "kid-waiting",
      status: "awaiting_guardian",
    });
    const result = await sweep();
    expect(result.skipped.liveJoinRequest).toBe(1);
    expect(db.store.has("users/kid-waiting")).toBe(true);
  });

  it("skips a child with a captain-undecided join request too", async () => {
    seedRevokedChild("kid-pending", OLD);
    db.seed("families/fam-3/pending/req-2", {
      userId: "kid-pending",
      status: "pending",
    });
    const result = await sweep();
    expect(result.skipped.liveJoinRequest).toBe(1);
    expect(db.store.has("users/kid-pending")).toBe(true);
  });

  it("tolerates an orphaned guardianship whose user doc is already gone", async () => {
    db.seed("users/ghost/private/guardianship", {
      guardianUid: "guardian-1",
      familyId: "fam-1",
      endedAtMillis: OLD,
    });
    const result = await sweep();
    expect(result.skipped.userGone).toBe(1);
    expect(result.deleted).toBe(0);
  });
});

describe("OD-3 sweep: caps are loud, never silent", () => {
  it("stops at maxDeletes and reports truncation", async () => {
    seedRevokedChild("kid-a", OLD);
    seedRevokedChild("kid-b", OLD + 1);
    const result = await sweep({ maxDeletes: 1 });
    expect(result.deleted).toBe(1);
    expect(result.truncated).toBe(true);
    // The nightly re-run finishes the remainder.
    const second = await sweep({ maxDeletes: 25 });
    expect(second.deleted).toBe(1);
  });
});

describe("OD-3 window plumbing", () => {
  const originalEnv = process.env.REVOKED_CHILD_RETENTION_DAYS;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.REVOKED_CHILD_RETENTION_DAYS;
    } else {
      process.env.REVOKED_CHILD_RETENTION_DAYS = originalEnv;
    }
  });

  it("defaults to the OD-3 ruling and honors the dev knob", () => {
    delete process.env.REVOKED_CHILD_RETENTION_DAYS;
    expect(revokedChildRetentionDays()).toBe(REVOKED_CHILD_RETENTION_DAYS_DEFAULT);
    expect(REVOKED_CHILD_RETENTION_DAYS_DEFAULT).toBe(365);

    process.env.REVOKED_CHILD_RETENTION_DAYS = "0";
    expect(revokedChildRetentionDays()).toBe(0);

    process.env.REVOKED_CHILD_RETENTION_DAYS = "not-a-number";
    expect(revokedChildRetentionDays()).toBe(REVOKED_CHILD_RETENTION_DAYS_DEFAULT);

    expect(revokedChildDeletionCutoffMillis(NOW, 365)).toBe(CUTOFF);
  });
});
