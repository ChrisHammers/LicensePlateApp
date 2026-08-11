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
      expectedAgeOutYear: 2031,
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
