/**
 * COPPA FR-60(c) / FR-77 — redemption-window account cleanup.
 *
 * The property that matters most here is the NEGATIVE one. Two populations look identical on
 * the two fields the FR-28 gate reads (`isChildAccount: true`, no `activeFamilyId`):
 *
 *   - the never-consented provisional child, whose account exists only because they entered a
 *     share code, and which FR-60(c) says must be deleted when consent is refused or lapses;
 *   - the STICKY POST-REVOCATION child, who WAS consented and then had it revoked, and whose
 *     data FR-28 preserves in the restricted state for the OD-3 window so the parent's
 *     deletion offer (FR-63(a)) still has something to offer.
 *
 * Deleting the second population as "transient residue" would destroy the very history the
 * parent is entitled to decide about. `wasEverInFamily` is the discrimination, and the tests
 * below drive it from both sides.
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
  // Raw millis, not Timestamp objects: FakeFirestore JSON-clones every write, so a
  // `{ toMillis() }` object would come back as `{}` and the range filter would never match.
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  CHILD_DECLARED_AT_FIELD,
  PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS,
  deleteProvisionalChildAccountIfNeverConsented,
  isNeverConsentedProvisionalChildUserData,
  provisionalChildDeletionCutoffMillis,
  sweepExpiredProvisionalChildAccounts,
} from "./provisionalChildAccounts";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 7, 14, 12, 0, 0);

const deletedAuthUsers: string[] = [];
const deps = {
  deleteAuthUser: async (userId: string) => {
    deletedAuthUsers.push(userId);
  },
  accountDeletionDeps: {
    clearSearchIndexes: async () => undefined,
    deleteRevenueCatCustomer: async () => "deleted" as const,
  },
};

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  deletedAuthUsers.length = 0;
});

// ---------------------------------------------------------------------------
// The predicate
// ---------------------------------------------------------------------------

describe("isNeverConsentedProvisionalChildUserData", () => {
  it("is true only for a flagged child with no family and no family history", () => {
    expect(isNeverConsentedProvisionalChildUserData({ isChildAccount: true })).toBe(true);
    expect(
      isNeverConsentedProvisionalChildUserData({ isChildAccount: true, wasEverInFamily: false })
    ).toBe(true);
  });

  it("is false for the sticky post-revocation child (FR-28 restricted state)", () => {
    expect(
      isNeverConsentedProvisionalChildUserData({ isChildAccount: true, wasEverInFamily: true })
    ).toBe(false);
  });

  it("is false for consented children, adults, and missing docs", () => {
    expect(
      isNeverConsentedProvisionalChildUserData({ isChildAccount: true, activeFamilyId: "fam1" })
    ).toBe(false);
    expect(isNeverConsentedProvisionalChildUserData({ userName: "Grown" })).toBe(false);
    expect(isNeverConsentedProvisionalChildUserData({ isChildAccount: false })).toBe(false);
    expect(isNeverConsentedProvisionalChildUserData(undefined)).toBe(false);
  });
});

describe("provisionalChildDeletionCutoffMillis", () => {
  it("is the declared-at cutoff for the FR-77 seven-day window", () => {
    expect(PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS).toBe(7);
    expect(provisionalChildDeletionCutoffMillis(NOW)).toBe(NOW - 7 * MS_PER_DAY);
  });
});

// ---------------------------------------------------------------------------
// Inline cleanup (decline / invite expiry)
// ---------------------------------------------------------------------------

describe("deleteProvisionalChildAccountIfNeverConsented", () => {
  it("deletes a never-consented provisional child outright, Firestore then Auth", async () => {
    db().seed("users/kid", {
      userName: "Kid",
      isChildAccount: true,
      [CHILD_DECLARED_AT_FIELD]: NOW,
    });
    db().seed("user_progression/kid", { totalXp: 40 });
    db().seed("public_lifetime_stats/kid", { totalDiscoveries: 3 });
    db().seed("users/kid/private/contact", { email: "unused@example.com" });

    const result = await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "kid", actorId: "captain", clientMetadata: null },
      deps
    );

    expect(result).toEqual({ deleted: true, reason: "deleted" });
    expect(db().store.has("users/kid")).toBe(false);
    expect(db().store.has("user_progression/kid")).toBe(false);
    expect(db().store.has("public_lifetime_stats/kid")).toBe(false);
    expect(db().store.has("users/kid/private/contact")).toBe(false);
    expect(deletedAuthUsers).toEqual(["kid"]);
  });

  /**
   * The load-bearing carve-out. A revoked child keeps `isChildAccount: true` and has no
   * `activeFamilyId`, so on the FR-28 fields alone they are indistinguishable from the
   * account above — and they must survive untouched.
   */
  it("NEVER touches a sticky post-revocation child (wasEverInFamily)", async () => {
    db().seed("users/revoked-kid", {
      userName: "Revoked",
      isChildAccount: true,
      wasEverInFamily: true,
    });
    db().seed("user_progression/revoked-kid", { totalXp: 900 });

    const result = await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "revoked-kid", actorId: "captain", clientMetadata: null },
      deps
    );

    expect(result).toEqual({ deleted: false, reason: "not_provisional_child" });
    expect(db().store.get("users/revoked-kid")).toBeDefined();
    expect(db().store.get("user_progression/revoked-kid")).toBeDefined();
    expect(deletedAuthUsers).toEqual([]);
  });

  it("leaves consented children, adults and missing docs alone", async () => {
    db().seed("users/consented", { isChildAccount: true, activeFamilyId: "fam1" });
    db().seed("users/adult", { userName: "Grown" });

    expect(
      await deleteProvisionalChildAccountIfNeverConsented(
        db() as never,
        { userId: "consented", actorId: "a", clientMetadata: null },
        deps
      )
    ).toEqual({ deleted: false, reason: "not_provisional_child" });
    expect(
      await deleteProvisionalChildAccountIfNeverConsented(
        db() as never,
        { userId: "adult", actorId: "a", clientMetadata: null },
        deps
      )
    ).toEqual({ deleted: false, reason: "not_provisional_child" });
    expect(
      await deleteProvisionalChildAccountIfNeverConsented(
        db() as never,
        { userId: "ghost", actorId: "a", clientMetadata: null },
        deps
      )
    ).toEqual({ deleted: false, reason: "no_user_doc" });

    expect(db().store.get("users/consented")).toBeDefined();
    expect(db().store.get("users/adult")).toBeDefined();
    expect(deletedAuthUsers).toEqual([]);
  });

  it("is idempotent — a second run finds nothing and does not re-delete the auth user", async () => {
    db().seed("users/kid", { isChildAccount: true });

    await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "kid", actorId: "captain", clientMetadata: null },
      deps
    );
    const second = await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "kid", actorId: "captain", clientMetadata: null },
      deps
    );

    expect(second).toEqual({ deleted: false, reason: "no_user_doc" });
    expect(deletedAuthUsers).toEqual(["kid"]);
  });

  /**
   * FR-77 keeps the consent/lifecycle audit types exempt from every retention path. The
   * DECLARED row is uid-only §312.5 evidence that the declaration happened — deleting it
   * would erase the record of the thing being cleaned up.
   */
  it("preserves the uid-only DECLARED audit row and writes the deletion record", async () => {
    db().seed("users/kid", { isChildAccount: true });
    db().seed("audit_logs/declared-row", {
      eventType: "AUDIT_CHILD_REGISTRATION_DECLARED",
      subjectId: "kid",
    });

    await deleteProvisionalChildAccountIfNeverConsented(
      db() as never,
      { userId: "kid", actorId: "captain", clientMetadata: null },
      deps
    );

    expect(db().store.get("audit_logs/declared-row")).toBeDefined();
    const deletionRows = db()
      .docPathsMatching((path) => path.startsWith("audit_logs/"))
      .map((path) => db().store.get(path)!)
      .filter((row) => row.eventType === "AUDIT_ACCOUNT_DELETED");
    expect(deletionRows).toHaveLength(1);
    expect(deletionRows[0].subjectId).toBe("kid");
    expect(deletionRows[0].actorId).toBe("captain");
  });
});

// ---------------------------------------------------------------------------
// FR-77 backstop sweep
// ---------------------------------------------------------------------------

describe("sweepExpiredProvisionalChildAccounts (FR-77 backstop)", () => {
  const aged = NOW - 10 * MS_PER_DAY;
  const fresh = NOW - 1 * MS_PER_DAY;

  function seedPopulation(): void {
    // Swept: declared 10 days ago, nobody ever answered.
    db().seed("users/aged-kid", { isChildAccount: true, [CHILD_DECLARED_AT_FIELD]: aged });
    // Not swept: still inside the redemption window.
    db().seed("users/fresh-kid", { isChildAccount: true, [CHILD_DECLARED_AT_FIELD]: fresh });
    // Not swept: sticky post-revocation. The marker would normally be gone (admission
    // deletes it) — seeded here anyway so the predicate is the thing under test, not the
    // query's happy path.
    db().seed("users/revoked-kid", {
      isChildAccount: true,
      wasEverInFamily: true,
      [CHILD_DECLARED_AT_FIELD]: aged,
    });
    // Not swept: admitted, so the marker was cleared by the grant batch.
    db().seed("users/consented-kid", { isChildAccount: true, activeFamilyId: "fam1" });
    // Not swept: no marker at all.
    db().seed("users/adult", { userName: "Grown" });
  }

  it("deletes only aged never-consented accounts", async () => {
    seedPopulation();

    const result = await sweepExpiredProvisionalChildAccounts(
      db() as never,
      { cutoffMillis: provisionalChildDeletionCutoffMillis(NOW), actorId: "system_retention" },
      deps
    );

    expect(result.deleted).toBe(1);
    expect(deletedAuthUsers).toEqual(["aged-kid"]);
    expect(db().store.has("users/aged-kid")).toBe(false);
    expect(db().store.get("users/fresh-kid")).toBeDefined();
    expect(db().store.get("users/revoked-kid")).toBeDefined();
    expect(db().store.get("users/consented-kid")).toBeDefined();
    expect(db().store.get("users/adult")).toBeDefined();
  });

  it("counts the aged-but-protected rows as skipped, not deleted", async () => {
    seedPopulation();

    const result = await sweepExpiredProvisionalChildAccounts(
      db() as never,
      { cutoffMillis: provisionalChildDeletionCutoffMillis(NOW), actorId: "system_retention" },
      deps
    );

    // Only the two rows with an aged marker are visible to the query at all.
    expect(result.scanned).toBe(2);
    expect(result.skipped).toBe(1);
    expect(result.truncated).toBe(false);
  });

  it("is idempotent — a second sweep over a clean population deletes nothing", async () => {
    seedPopulation();
    const cutoffMillis = provisionalChildDeletionCutoffMillis(NOW);

    await sweepExpiredProvisionalChildAccounts(
      db() as never,
      { cutoffMillis, actorId: "system_retention" },
      deps
    );
    deletedAuthUsers.length = 0;

    const second = await sweepExpiredProvisionalChildAccounts(
      db() as never,
      { cutoffMillis, actorId: "system_retention" },
      deps
    );

    expect(second.deleted).toBe(0);
    expect(deletedAuthUsers).toEqual([]);
  });

  it("stops at the per-run delete bound and reports it, leaving the rest for the next run", async () => {
    for (let i = 0; i < 5; i += 1) {
      db().seed(`users/kid-${i}`, {
        isChildAccount: true,
        [CHILD_DECLARED_AT_FIELD]: aged,
      });
    }

    const result = await sweepExpiredProvisionalChildAccounts(
      db() as never,
      {
        cutoffMillis: provisionalChildDeletionCutoffMillis(NOW),
        actorId: "system_retention",
        maxDeletes: 2,
        pageSize: 2,
      },
      deps
    );

    expect(result.deleted).toBe(2);
    expect(result.truncated).toBe(true);
    expect(
      db().docPathsMatching((path) => path.startsWith("users/")).length
    ).toBe(3);
  });
});
