import { describe, it, expect } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  writeChildConsentCorrected,
  writeChildConsentGranted,
  writeChildMembershipRevocation,
  writeChildRegistrationDeclared,
} from "./childConsent";
import {
  CHILD_CONSENT_REVOCATION_REASONS,
  consentMetadataPiiViolations,
} from "./childAccountCore";
import type { ClientMetadata } from "./clientMetadata";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

const CLIENT_METADATA: ClientMetadata = {
  phoneModel: "iPhone 16",
  phoneModelIdentifier: "iPhone17,3",
  phoneOSVersion: "19.0",
  clientAppVersion: "1.0",
  clientAppBuild: "42",
};

function auditRows(db: FakeFirestore): Array<Record<string, unknown>> {
  return db
    .docPathsMatching((path) => path.startsWith("audit_logs/"))
    .map((path) => db.store.get(path)!);
}

describe("childConsent writers", () => {
  it("GRANTED row: event type, actor/subject, uid-only metadata, clientMetadata sibling", async () => {
    const db = new FakeFirestore();
    await writeChildConsentGranted(asFirestore(db), {
      familyId: "fam1",
      childUserId: "kid",
      actorId: "parent",
      actorRole: "creator",
      method: "manager_set",
      expectedAgeOutYearMonth: 2031,
      removedFriendEdgeCount: 1,
      clientMetadata: CLIENT_METADATA,
    });

    const rows = auditRows(db);
    expect(rows).toHaveLength(1);
    const row = rows[0];
    expect(row.eventType).toBe("AUDIT_PARENTAL_CONSENT_GRANTED");
    expect(row.actorId).toBe("parent");
    expect(row.subjectType).toBe("user");
    expect(row.subjectId).toBe("kid");
    // clientMetadata is a SIBLING field, never nested inside metadata.
    expect(row.clientMetadata).toEqual(CLIENT_METADATA);
    const metadata = row.metadata as Record<string, unknown>;
    expect(metadata).not.toHaveProperty("clientMetadata");
    expect(consentMetadataPiiViolations(metadata)).toEqual([]);
    expect(metadata.guardianAffirmed).toBe(true);
    expect(metadata.consentTextVersion).toBeTruthy();
    expect(metadata.affirmationVersion).toBeTruthy();
  });

  it("REVOKED rows accept every enumerated exit reason and omit clientMetadata on background paths", async () => {
    const db = new FakeFirestore();
    for (const reason of CHILD_CONSENT_REVOCATION_REASONS) {
      await writeChildMembershipRevocation(asFirestore(db), {
        familyId: "fam1",
        childUserId: "kid",
        actorId: "actor",
        actorRole: "creator",
        method: "test_path",
        reason,
        clientMetadata: null,
      });
    }

    const rows = auditRows(db);
    expect(rows).toHaveLength(CHILD_CONSENT_REVOCATION_REASONS.length);
    const reasons = rows.map((row) => (row.metadata as Record<string, unknown>).reason);
    expect(reasons.sort()).toEqual([...CHILD_CONSENT_REVOCATION_REASONS].sort());
    for (const row of rows) {
      expect(row.eventType).toBe("AUDIT_PARENTAL_CONSENT_REVOKED");
      expect(row).not.toHaveProperty("clientMetadata");
    }
  });

  it("CORRECTED and DECLARED rows carry their reasons/methods", async () => {
    const db = new FakeFirestore();
    await writeChildConsentCorrected(asFirestore(db), {
      familyId: "fam1",
      childUserId: "kid",
      actorId: "parent",
      actorRole: "captain",
      method: "manager_correction",
      reason: "child_turned_13",
      clientMetadata: null,
    });
    await writeChildRegistrationDeclared(asFirestore(db), {
      childUserId: "kid",
      clientMetadata: CLIENT_METADATA,
    });

    const rows = auditRows(db);
    const corrected = rows.find((r) => r.eventType === "AUDIT_PARENTAL_CONSENT_CORRECTED")!;
    expect((corrected.metadata as Record<string, unknown>).reason).toBe("child_turned_13");

    const declared = rows.find((r) => r.eventType === "AUDIT_CHILD_REGISTRATION_DECLARED")!;
    expect(declared.actorId).toBe("kid");
    expect(declared.subjectId).toBe("kid");
    expect((declared.metadata as Record<string, unknown>).method).toBe("self_declared");
  });

  it("refuses to persist metadata carrying an email-like value (runtime PII guard)", async () => {
    const db = new FakeFirestore();
    await expect(
      writeChildMembershipRevocation(asFirestore(db), {
        familyId: "fam1",
        childUserId: "kid",
        actorId: "actor",
        actorRole: "parent@example.com",
        method: "remove_family_member",
        reason: "parent_removed_child",
        clientMetadata: null,
      })
    ).rejects.toThrow(/uid-only/);
    expect(auditRows(db)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// FR-73 / v2.1 FR-53(b) — the push token dies with the consent that covered it
// ---------------------------------------------------------------------------

describe("FR-73: REVOKED deletes the child's push routing doc", () => {
  const FCM_PATH = "users/kid/private/fcm";

  async function revoke(
    db: FakeFirestore,
    reason: (typeof CHILD_CONSENT_REVOCATION_REASONS)[number] = "parent_removed_child"
  ): Promise<void> {
    await writeChildMembershipRevocation(asFirestore(db), {
      familyId: "fam1",
      childUserId: "kid",
      actorId: "parent",
      actorRole: "captain",
      method: "remove_family_member",
      reason,
      clientMetadata: null,
    });
  }

  it("deletes users/{uid}/private/fcm on revocation", async () => {
    const db = new FakeFirestore();
    db.store.set(FCM_PATH, { token: "child-token", updatedAt: 1 });

    await revoke(db);

    expect(db.store.has(FCM_PATH)).toBe(false);
  });

  /**
   * The revocation record is the §312.5 evidence and must still land — the token deletion
   * rides along, it does not gate.
   */
  it("still writes the REVOKED audit row", async () => {
    const db = new FakeFirestore();
    db.store.set(FCM_PATH, { token: "child-token" });

    await revoke(db);

    const rows = auditRows(db);
    expect(rows).toHaveLength(1);
    expect(rows[0].eventType).toBe("AUDIT_PARENTAL_CONSENT_REVOKED");
    expect(rows[0].subjectId).toBe("kid");
  });

  /** Most revocations have no token to remove (the FR-73 guard kept one from existing). */
  it("is a no-op when no token doc exists", async () => {
    const db = new FakeFirestore();

    await revoke(db);

    expect(db.store.has(FCM_PATH)).toBe(false);
    expect(auditRows(db)).toHaveLength(1);
  });

  /**
   * `writeChildMembershipRevocation` is the chokepoint EVERY membership-exit path calls
   * (family removal, family inactivation, account deletion, the OD-3 sweep), which is the
   * whole reason the deletion lives here rather than in one caller. Pinning every enumerated
   * reason is what stops a new exit path shipping without the token cleanup.
   */
  it("removes the token on every enumerated exit reason", async () => {
    for (const reason of CHILD_CONSENT_REVOCATION_REASONS) {
      const db = new FakeFirestore();
      db.store.set(FCM_PATH, { token: "child-token" });

      await revoke(db, reason);

      expect(db.store.has(FCM_PATH)).toBe(false);
    }
  });

  /** Only the revoked child's doc — a sibling's routing must survive untouched. */
  it("does not touch another user's token", async () => {
    const db = new FakeFirestore();
    db.store.set(FCM_PATH, { token: "child-token" });
    db.store.set("users/sibling/private/fcm", { token: "sibling-token" });

    await revoke(db);

    expect(db.store.has(FCM_PATH)).toBe(false);
    expect(db.store.get("users/sibling/private/fcm")).toEqual({ token: "sibling-token" });
  });

  /**
   * FR-62's guardianship end and FR-73's token deletion share this writer; neither may
   * displace the other.
   */
  it("ends the guardianship record and deletes the token in the same pass", async () => {
    const db = new FakeFirestore();
    db.store.set(FCM_PATH, { token: "child-token" });
    db.store.set("users/kid/private/guardianship", {
      familyId: "fam1",
      guardianUid: "parent",
    });

    await revoke(db);

    expect(db.store.has(FCM_PATH)).toBe(false);
    const guardianship = db.store.get("users/kid/private/guardianship")!;
    expect(typeof guardianship.endedAtMillis).toBe("number");
    expect(guardianship.endedReason).toBe("parent_removed_child");
  });
});
