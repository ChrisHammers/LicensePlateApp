/**
 * COPPA FR-78 (F-34) — third-party deletion propagation (§312.6: operators are responsible
 * for vendors' handling of children's data too).
 *
 * `executeAccountDeletionForUser` gains a RevenueCat customer-deletion phase. These tests
 * mock the vendor HTTP layer via `AccountDeletionDeps.deleteRevenueCatCustomer` (never touch
 * the network) and pin the FR-78(a) acceptance cases: a missing secret is an inert no-op, a
 * never-purchasing/child account's vendor 404 does not fail the cascade, and a genuine vendor
 * error is retryable without re-running the already-completed local phases.
 *
 * FR-78(b) (GA4 user deletion) has no server-side call — the decision (documented mechanism:
 * client-side `Analytics.resetAnalyticsData()` + Google's own GA4 retention window) is
 * recorded as a comment in accountDeletion.ts next to the RevenueCat cascade, not tested here.
 */

import { describe, it, expect, vi } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { executeAccountDeletionForUser } from "./accountDeletion";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

function auditRowsOfType(db: FakeFirestore, eventType: string) {
  return db
    .docPathsMatching((path) => path.startsWith("audit_logs/"))
    .map((path) => db.store.get(path)!)
    .filter((row) => row.eventType === eventType);
}

const noClearSearchIndexes = { clearSearchIndexes: async () => undefined };

/** A plain (non-child) user with family membership + progression residue to delete. */
function seedDeletableUser(db: FakeFirestore, uid: string): void {
  db.seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
  db.seed("families/fam1/members/parent", { role: "creator" });
  db.seed(`families/fam1/members/${uid}`, { role: "scout" });
  db.seed("users/parent", { activeFamilyId: "fam1" });
  db.seed(`users/${uid}`, { activeFamilyId: "fam1" });
  db.seed(`user_progression/${uid}`, { totalXp: 42 });
}

describe("executeAccountDeletionForUser — FR-78(a): RevenueCat secret not configured", () => {
  it("is a logged no-op that never touches the vendor, and the rest of the cascade still fully succeeds", async () => {
    const db = new FakeFirestore();
    seedDeletableUser(db, "uid1");
    const deleteRevenueCatCustomer = vi.fn(async () => {
      throw new Error("must not be called when no API key is configured");
    });

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "uid1", actorId: "uid1", clientMetadata: null },
      { ...noClearSearchIndexes, deleteRevenueCatCustomer }
    );

    expect(deleteRevenueCatCustomer).not.toHaveBeenCalled();
    expect(result.revenueCatDeletionOutcome).toBe("skipped_no_key");

    // The cascade did not stop early — every other local phase still ran.
    expect(db.store.has("users/uid1")).toBe(false);
    expect(db.store.has("families/fam1/members/uid1")).toBe(false);
    expect(db.store.has("user_progression/uid1")).toBe(false);

    const rows = auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED");
    expect(rows).toHaveLength(1);
    expect((rows[0].metadata as Record<string, unknown>).revenueCatDeletionOutcome).toBe(
      "skipped_no_key"
    );
  });

  it("also skips (rather than crashing) when the caller explicitly passes null", async () => {
    const db = new FakeFirestore();
    seedDeletableUser(db, "uid1");
    const deleteRevenueCatCustomer = vi.fn();

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "uid1", actorId: "uid1", clientMetadata: null, revenueCatApiKey: null },
      { ...noClearSearchIndexes, deleteRevenueCatCustomer }
    );

    expect(deleteRevenueCatCustomer).not.toHaveBeenCalled();
    expect(result.revenueCatDeletionOutcome).toBe("skipped_no_key");
  });
});

describe("executeAccountDeletionForUser — FR-78(a): RevenueCat vendor outcomes", () => {
  it("vendor 200: outcome recorded as deleted, key/uid passed through correctly", async () => {
    const db = new FakeFirestore();
    seedDeletableUser(db, "uid1");
    const deleteRevenueCatCustomer = vi.fn(async (params: { apiKey: string; appUserId: string }) => {
      expect(params).toEqual({ apiKey: "sk_test_123", appUserId: "uid1" });
      return { outcome: "deleted" as const };
    });

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      {
        userId: "uid1",
        actorId: "uid1",
        clientMetadata: null,
        revenueCatApiKey: "sk_test_123",
      },
      { ...noClearSearchIndexes, deleteRevenueCatCustomer }
    );

    expect(deleteRevenueCatCustomer).toHaveBeenCalledTimes(1);
    expect(result.revenueCatDeletionOutcome).toBe("deleted");
    const rows = auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED");
    expect((rows[0].metadata as Record<string, unknown>).revenueCatDeletionOutcome).toBe(
      "deleted"
    );
  });

  it("vendor 404 (never-purchasing flagged child): treated as success, cascade completes and child-exit machinery is unaffected", async () => {
    const db = new FakeFirestore();
    db.seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
    db.seed("families/fam1/members/parent", { role: "creator" });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    db.seed("users/parent", { activeFamilyId: "fam1" });
    db.seed("users/kid", { activeFamilyId: "fam1", isChildAccount: true });

    const deleteRevenueCatCustomer = vi.fn(async () => ({ outcome: "not_found" as const }));

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "kid", actorId: "kid", clientMetadata: null, revenueCatApiKey: "sk_test_123" },
      { ...noClearSearchIndexes, deleteRevenueCatCustomer }
    );

    expect(result.revenueCatDeletionOutcome).toBe("not_found");
    expect(db.store.has("users/kid")).toBe(false);
    // FR-40's revocation record still fires — the new vendor phase does not disturb it.
    expect(auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_REVOKED")).toHaveLength(1);
    const rows = auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED");
    expect(rows).toHaveLength(1);
    expect((rows[0].metadata as Record<string, unknown>).revenueCatDeletionOutcome).toBe(
      "not_found"
    );
  });
});

describe("executeAccountDeletionForUser — FR-78(a): vendor failure is retryable", () => {
  it("throws on a vendor error after every local phase already committed, and a retry completes without re-doing local work", async () => {
    const db = new FakeFirestore();
    seedDeletableUser(db, "uid1");

    const failingDelete = vi.fn(async () => {
      throw new Error("RevenueCat customer deletion failed (500): internal error");
    });

    await expect(
      executeAccountDeletionForUser(
        asFirestore(db),
        {
          userId: "uid1",
          actorId: "uid1",
          clientMetadata: null,
          revenueCatApiKey: "sk_test_123",
        },
        { ...noClearSearchIndexes, deleteRevenueCatCustomer: failingDelete }
      )
    ).rejects.toThrow(/500/);

    expect(failingDelete).toHaveBeenCalledTimes(1);

    // Every local phase already committed and is durable — a vendor failure does not
    // undo, and does not need to redo, any of it.
    expect(db.store.has("users/uid1")).toBe(false);
    expect(db.store.has("families/fam1/members/uid1")).toBe(false);
    expect(db.store.has("user_progression/uid1")).toBe(false);
    expect(auditRowsOfType(db, "AUDIT_FAMILY_MEMBER_REMOVED")).toHaveLength(1);
    // The audit row bundles the vendor outcome and is written AFTER the vendor call, so a
    // vendor failure means no row yet — nothing false is ever recorded as "deleted".
    expect(auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED")).toHaveLength(0);

    // Retry: the caller (deleteAccount/requestChildDataDeletion) never reached
    // admin.auth().deleteUser after the throw above, so the Firebase Auth user — and the
    // ability to retry the whole request — survives. Simulate that retry re-entering here.
    const succeedingDelete = vi.fn(async () => ({ outcome: "deleted" as const }));

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "uid1", actorId: "uid1", clientMetadata: null, revenueCatApiKey: "sk_test_123" },
      { ...noClearSearchIndexes, deleteRevenueCatCustomer: succeedingDelete }
    );

    expect(succeedingDelete).toHaveBeenCalledTimes(1);
    expect(result).toEqual({
      removedFriendEdgeCount: 0,
      familyAction: "none", // recomputed fresh: the membership is already gone, not re-removed
      revenueCatDeletionOutcome: "deleted",
    });
    // No duplicate family-removal audit row: the retry found nothing left to do there.
    expect(auditRowsOfType(db, "AUDIT_FAMILY_MEMBER_REMOVED")).toHaveLength(1);
    // Exactly one AUDIT_ACCOUNT_DELETED row now exists — the retry's own, first-ever write.
    expect(auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED")).toHaveLength(1);
  });
});
