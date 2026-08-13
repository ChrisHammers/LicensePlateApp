/**
 * COPPA F-5a — FR-6 / FR-40 coverage for the account-deletion membership exits:
 *  - the previously audit-less `remove_member` branch now writes
 *    AUDIT_FAMILY_MEMBER_REMOVED, and REVOKED (`member_account_deleted`) when the
 *    departing member is a flagged child (child self-deletion, FR-40);
 *  - the `inactivate_family` branch (creator deletes account) writes REVOKED
 *    (`creator_account_deleted`) for every other flagged child, whose sticky
 *    `isChildAccount` flag remains true.
 */

import { describe, it, expect } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { executeAccountDeletionForUser } from "./accountDeletion";
import {
  INVITE_RATE_LIMIT_COLLECTION,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

const noopDeps = { clearSearchIndexes: async () => undefined };

function auditRowsOfType(db: FakeFirestore, eventType: string) {
  return db
    .docPathsMatching((path) => path.startsWith("audit_logs/"))
    .map((path) => db.store.get(path)!)
    .filter((row) => row.eventType === eventType);
}

describe("executeAccountDeletionForUser — child membership exits", () => {
  it("child self-deletion: remove_member branch audits and revokes (FR-40)", async () => {
    const db = new FakeFirestore();
    db.seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
    db.seed("families/fam1/members/parent", { role: "creator" });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    db.seed("users/parent", { activeFamilyId: "fam1" });
    db.seed("users/kid", { activeFamilyId: "fam1", isChildAccount: true });

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "kid", actorId: "kid", clientMetadata: null },
      noopDeps
    );
    expect(result.familyAction).toBe("remove_member");

    // The branch's previously missing generic audit now exists.
    const removed = auditRowsOfType(db, "AUDIT_FAMILY_MEMBER_REMOVED");
    expect(removed).toHaveLength(1);
    expect(removed[0].metadata).toEqual({
      removedMemberId: "kid",
      role: "scout",
      reason: "account_deleted",
    });

    // FR-40: REVOKED with member_account_deleted, plus the deletion record.
    const revoked = auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_REVOKED");
    expect(revoked).toHaveLength(1);
    expect((revoked[0].metadata as Record<string, unknown>).reason).toBe(
      "member_account_deleted"
    );
    expect(revoked[0].subjectId).toBe("kid");
    expect(auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED")).toHaveLength(1);

    // Family survives; the deleted member is gone.
    expect(db.store.has("families/fam1/members/kid")).toBe(false);
    expect(db.store.has("families/fam1/members/parent")).toBe(true);
    expect(db.store.has("users/kid")).toBe(false);
  });

  it("creator deletion inactivates the family and revokes for surviving children — flag stays true", async () => {
    const db = new FakeFirestore();
    db.seed("families/fam1", { name: "Fam", creatorId: "creator", status: "active" });
    db.seed("families/fam1/members/creator", { role: "creator" });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    db.seed("families/fam1/members/adult", { role: "sergeant" });
    db.seed("users/creator", { activeFamilyId: "fam1" });
    db.seed("users/kid", { activeFamilyId: "fam1", isChildAccount: true });
    db.seed("users/adult", { activeFamilyId: "fam1" });

    const result = await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "creator", actorId: "creator", clientMetadata: null },
      noopDeps
    );
    expect(result.familyAction).toBe("inactivate_family");

    const revoked = auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_REVOKED");
    expect(revoked).toHaveLength(1);
    expect(revoked[0].subjectId).toBe("kid");
    expect((revoked[0].metadata as Record<string, unknown>).reason).toBe(
      "creator_account_deleted"
    );

    // Sticky flag: the child's user doc keeps isChildAccount true after the exit.
    expect(db.store.get("users/kid")!.isChildAccount).toBe(true);
    // The adult member produced no revocation.
    expect(
      revoked.filter((row) => row.subjectId === "adult")
    ).toHaveLength(0);
    expect(db.store.get("families/fam1")!.status).toBe("inactive");
  });

  it("adult deletion writes no consent records at all", async () => {
    const db = new FakeFirestore();
    db.seed("families/fam1", { name: "Fam", creatorId: "parent", status: "active" });
    db.seed("families/fam1/members/parent", { role: "creator" });
    db.seed("families/fam1/members/adult", { role: "scout" });
    db.seed("users/parent", { activeFamilyId: "fam1" });
    db.seed("users/adult", { activeFamilyId: "fam1" });

    await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "adult", actorId: "adult", clientMetadata: null },
      noopDeps
    );

    expect(auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_REVOKED")).toHaveLength(0);
    expect(auditRowsOfType(db, "AUDIT_FAMILY_MEMBER_REMOVED")).toHaveLength(1);
    expect(auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED")).toHaveLength(1);
  });

  /**
   * FR-47's rate-limit counters are keyed by uid in their document id, so FR-50's
   * "no document anywhere still names the deleted user" claim covers them too.
   */
  it("FR-47/FR-50: deletes the user's invite rate-limit counters, leaving others alone", async () => {
    const db = new FakeFirestore();
    db.seed("users/adult", {});
    db.seed("users/bystander", {});
    for (const scope of ["trip_invite", "friend_invite"] as const) {
      db.seed(`${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId(scope, "adult")}`, {
        userId: "adult",
        scope,
        windowStartAtMs: 1,
        count: 3,
      });
      db.seed(
        `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId(scope, "bystander")}`,
        { userId: "bystander", scope, windowStartAtMs: 1, count: 3 }
      );
    }

    await executeAccountDeletionForUser(
      asFirestore(db),
      { userId: "adult", actorId: "adult", clientMetadata: null },
      noopDeps
    );

    const remaining = db.docPathsMatching((path) =>
      path.startsWith(`${INVITE_RATE_LIMIT_COLLECTION}/`)
    );
    expect(remaining.some((path) => path.includes("adult"))).toBe(false);
    expect(remaining).toHaveLength(2); // both of the bystander's counters survive
  });
});
