import { describe, it, expect } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  applyChildProtectionsAfterFlagSet,
  declareChildRegistrationFlow,
  getParentalConsentStatusFlow,
  requestChildDataDeletionFlow,
  setFamilyMemberChildStatusFlow,
} from "./familyChildStatusFlows";
import { consentMetadataPiiViolations } from "./childAccountCore";
import type { ClientMetadata } from "./clientMetadata";
import type { SearchIndexHints } from "./userResidueCleanup";

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

interface RecordedPurge {
  userId: string;
  hints: SearchIndexHints;
}

function stubDeps(purges: RecordedPurge[]) {
  return {
    clearSearchIndexes: async (
      userId: string,
      hints: { userNameLower?: string | null; emailLower?: string | null; phoneE164?: string | null }
    ) => {
      purges.push({
        userId,
        hints: {
          userNameLower: hints.userNameLower ?? null,
          emailLower: hints.emailLower ?? null,
          phoneE164: hints.phoneE164 ?? null,
        },
      });
    },
  };
}

function auditRows(db: FakeFirestore): Array<Record<string, unknown>> {
  return db
    .docPathsMatching((path) => path.startsWith("audit_logs/"))
    .map((path) => db.store.get(path)!);
}

function auditRowsOfType(db: FakeFirestore, eventType: string) {
  return auditRows(db).filter((row) => row.eventType === eventType);
}

/** A family with a creator, a captain, and the target scout "kid". */
function seedFamily(db: FakeFirestore): void {
  db.seed("families/fam1", { name: "Testers", creatorId: "parent", status: "active" });
  db.seed("families/fam1/members/parent", { role: "creator" });
  db.seed("families/fam1/members/cap", { role: "captain" });
  db.seed("families/fam1/members/kid", { role: "scout" });

  db.seed("users/parent", { activeFamilyId: "fam1", userName: "Parent" });
  db.seed("users/cap", { activeFamilyId: "fam1", userName: "Cap" });
  db.seed("users/kid", {
    activeFamilyId: "fam1",
    userName: "KidUser",
    userNameLower: "kiduser",
    linkedPlatforms: [
      {
        platform: "google",
        platformUserId: "g-kid",
        linkedAt: 1,
        email: "kid@example.com",
        displayName: "Kid",
      },
    ],
  });
  db.seed("users/kid/private/contact", {
    email: "kid@example.com",
    emailLower: "kid@example.com",
    phoneE164: "+15550001111",
  });
  db.seed("users/stranger", { userName: "Stranger", friendCount: 3 });
}

function seedChildSocialResidue(db: FakeFirestore): void {
  // Friend edge with a stranger (FR-36 removes it, decrementing the stranger's count).
  db.seed("friends/edge1", { userA: "kid", userB: "stranger", status: "accepted" });
  // Pending invite from OUTSIDE the family — must expire.
  db.seed("invites/out1", {
    type: "friend",
    fromUserId: "stranger",
    toUserId: "kid",
    status: "pending",
  });
  // Pending invite from INSIDE the family — must stay pending.
  db.seed("invites/in1", {
    type: "family",
    fromUserId: "parent",
    toUserId: "kid",
    status: "pending",
  });
  // Pending trip invite from outside — must expire.
  db.seed("trip_invites/tout1", {
    fromUserId: "stranger",
    toUserId: "kid",
    status: "pending",
  });
  // Already-resolved invite — untouched.
  db.seed("invites/done1", {
    type: "friend",
    fromUserId: "stranger",
    toUserId: "kid",
    status: "declined",
  });
}

describe("setFamilyMemberChildStatusFlow", () => {
  const baseInput = {
    actorId: "parent",
    familyId: "fam1",
    targetUserId: "kid",
    isChild: true as unknown,
    consentAcknowledged: true as unknown,
    guardianAffirmed: true as unknown,
    clientMetadata: CLIENT_METADATA,
  };

  it("rejects non-member and non-manager actors, self-targets, and creator targets", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    db.seed("families/fam1/members/scout2", { role: "scout" });

    await expect(
      setFamilyMemberChildStatusFlow(asFirestore(db), { ...baseInput, actorId: "nobody" }, stubDeps([]))
    ).rejects.toThrow(/family member/i);

    await expect(
      setFamilyMemberChildStatusFlow(asFirestore(db), { ...baseInput, actorId: "scout2" }, stubDeps([]))
    ).rejects.toThrow(/Captains/i);

    await expect(
      setFamilyMemberChildStatusFlow(
        asFirestore(db),
        { ...baseInput, actorId: "parent", targetUserId: "parent" },
        stubDeps([])
      )
    ).rejects.toThrow(/own child status/i);

    await expect(
      setFamilyMemberChildStatusFlow(
        asFirestore(db),
        { ...baseInput, actorId: "cap", targetUserId: "parent" },
        stubDeps([])
      )
    ).rejects.toThrow(/creator/i);
  });

  it("rejects set-true without both acknowledgments and clear without a valid reason", async () => {
    const db = new FakeFirestore();
    seedFamily(db);

    await expect(
      setFamilyMemberChildStatusFlow(
        asFirestore(db),
        { ...baseInput, guardianAffirmed: false },
        stubDeps([])
      )
    ).rejects.toThrow(/guardianAffirmed/);

    await expect(
      setFamilyMemberChildStatusFlow(
        asFirestore(db),
        { ...baseInput, isChild: false, correctionReason: "felt_like_it" },
        stubDeps([])
      )
    ).rejects.toThrow(/correctionReason/);
  });

  it("set-true: FR-4 batch + follow-ons + GRANTED record", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    seedChildSocialResidue(db);
    const purges: RecordedPurge[] = [];

    const result = await setFamilyMemberChildStatusFlow(
      asFirestore(db),
      { ...baseInput, expectedAgeOutYear: new Date().getUTCFullYear() + 3 },
      stubDeps(purges)
    );
    expect(result.success).toBe(true);
    expect(result.removedFriendEdgeCount).toBe(1);

    // Batch: authoritative flag + member projection + linkedPlatforms strip.
    const kid = db.store.get("users/kid")!;
    expect(kid.isChildAccount).toBe(true);
    expect(kid.linkedPlatforms).toEqual([
      { platform: "google", platformUserId: "g-kid", linkedAt: 1 },
    ]);
    expect(db.store.get("families/fam1/members/kid")!.isChild).toBe(true);

    // Follow-on: search-index purge with resolved hints.
    expect(purges).toEqual([
      {
        userId: "kid",
        hints: {
          userNameLower: "kiduser",
          emailLower: "kid@example.com",
          phoneE164: "+15550001111",
        },
      },
    ]);

    // Follow-on: FR-36 — outside invites expired, in-family invite kept, edges removed.
    expect(db.store.get("invites/out1")!.status).toBe("expired");
    expect(db.store.get("trip_invites/tout1")!.status).toBe("expired");
    expect(db.store.get("invites/in1")!.status).toBe("pending");
    expect(db.store.get("invites/done1")!.status).toBe("declined");
    expect(db.store.has("friends/edge1")).toBe(false);
    expect(db.store.get("users/stranger")!.friendCount).toBe(2);

    // GRANTED record: uid-only metadata + clientMetadata sibling.
    const granted = auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_GRANTED");
    expect(granted).toHaveLength(1);
    const row = granted[0];
    expect(row.actorId).toBe("parent");
    expect(row.subjectId).toBe("kid");
    expect(row.clientMetadata).toEqual(CLIENT_METADATA);
    const metadata = row.metadata as Record<string, unknown>;
    expect(consentMetadataPiiViolations(metadata)).toEqual([]);
    expect(metadata.method).toBe("manager_set");
    expect(metadata.actorRole).toBe("creator");
    expect(metadata.removedFriendEdgeCount).toBe(1);
    expect(metadata.expectedAgeOutYear).toBe(new Date().getUTCFullYear() + 3);
    expect(metadata).not.toHaveProperty("email");
    expect(metadata).not.toHaveProperty("name");
    expect(metadata).not.toHaveProperty("birthdate");
  });

  it("set-true is retry-safe: a second run finds nothing left to clean", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    seedChildSocialResidue(db);

    await setFamilyMemberChildStatusFlow(asFirestore(db), baseInput, stubDeps([]));
    const second = await setFamilyMemberChildStatusFlow(
      asFirestore(db),
      baseInput,
      stubDeps([])
    );
    expect(second.removedFriendEdgeCount).toBe(0);
    expect(db.store.get("users/kid")!.isChildAccount).toBe(true);
  });

  it("clear: correction sets both fields false and writes CORRECTED with the reason", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    db.seed("users/kid", { activeFamilyId: "fam1", isChildAccount: true });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });

    const result = await setFamilyMemberChildStatusFlow(
      asFirestore(db),
      {
        ...baseInput,
        actorId: "cap",
        isChild: false,
        correctionReason: "child_turned_13",
      },
      stubDeps([])
    );
    expect(result.isChildAccount).toBe(false);
    expect(db.store.get("users/kid")!.isChildAccount).toBe(false);
    expect(db.store.get("families/fam1/members/kid")!.isChild).toBe(false);

    const corrected = auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_CORRECTED");
    expect(corrected).toHaveLength(1);
    const metadata = corrected[0].metadata as Record<string, unknown>;
    expect(metadata.reason).toBe("child_turned_13");
    expect(metadata.method).toBe("manager_correction");
    expect(metadata.actorRole).toBe("captain");
    expect(consentMetadataPiiViolations(metadata)).toEqual([]);
  });
});

describe("declareChildRegistrationFlow (FR-27 server half)", () => {
  it("is safe before any profile write exists and writes the uid-only DECLARED record", async () => {
    const db = new FakeFirestore();

    const result = await declareChildRegistrationFlow(asFirestore(db), {
      userId: "newkid",
      clientMetadata: CLIENT_METADATA,
    });
    expect(result).toEqual({ success: true, isChildAccount: true, alreadyDeclared: false });

    // The users doc now exists with ONLY the flag — nothing else was invented.
    expect(db.store.get("users/newkid")).toEqual({ isChildAccount: true });

    const declared = auditRowsOfType(db, "AUDIT_CHILD_REGISTRATION_DECLARED");
    expect(declared).toHaveLength(1);
    expect(declared[0].actorId).toBe("newkid");
    expect(declared[0].subjectId).toBe("newkid");
    const metadata = declared[0].metadata as Record<string, unknown>;
    expect(consentMetadataPiiViolations(metadata)).toEqual([]);
    expect(metadata.childUserId).toBe("newkid");

    // No search-index entries were created anywhere.
    expect(
      db.docPathsMatching(
        (path) =>
          path.startsWith("usernames/") ||
          path.startsWith("user_lookup_email/") ||
          path.startsWith("user_lookup_phone/")
      )
    ).toEqual([]);
  });

  it("preserves an existing profile via merge and never clears the flag", async () => {
    const db = new FakeFirestore();
    db.seed("users/guest", { userName: "Guesty" });

    await declareChildRegistrationFlow(asFirestore(db), {
      userId: "guest",
      clientMetadata: null,
    });
    expect(db.store.get("users/guest")).toEqual({
      userName: "Guesty",
      isChildAccount: true,
    });
  });

  it("is idempotent: a repeat declaration writes no duplicate DECLARED row", async () => {
    const db = new FakeFirestore();
    await declareChildRegistrationFlow(asFirestore(db), {
      userId: "kid",
      clientMetadata: null,
    });
    const second = await declareChildRegistrationFlow(asFirestore(db), {
      userId: "kid",
      clientMetadata: null,
    });
    expect(second.alreadyDeclared).toBe(true);
    expect(auditRowsOfType(db, "AUDIT_CHILD_REGISTRATION_DECLARED")).toHaveLength(1);
  });
});

describe("requestChildDataDeletionFlow (FR-30)", () => {
  function seedFlaggedChild(db: FakeFirestore): void {
    seedFamily(db);
    db.seed("users/kid", {
      activeFamilyId: "fam1",
      isChildAccount: true,
      userName: "KidUser",
      userNameLower: "kiduser",
    });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    db.seed("user_progression/kid", { totalXp: 100 });
    db.seed("public_lifetime_stats/kid", { platesFound: 5 });
  }

  it("rejects non-managers, self-targets, and non-child targets", async () => {
    const db = new FakeFirestore();
    seedFlaggedChild(db);
    db.seed("families/fam1/members/scout2", { role: "scout" });

    await expect(
      requestChildDataDeletionFlow(asFirestore(db), {
        actorId: "scout2",
        familyId: "fam1",
        childUserId: "kid",
        clientMetadata: null,
      })
    ).rejects.toThrow(/Captains/i);

    await expect(
      requestChildDataDeletionFlow(asFirestore(db), {
        actorId: "parent",
        familyId: "fam1",
        childUserId: "parent",
        clientMetadata: null,
      })
    ).rejects.toThrow(/own account/i);

    await expect(
      requestChildDataDeletionFlow(asFirestore(db), {
        actorId: "parent",
        familyId: "fam1",
        childUserId: "cap", // not flagged
        clientMetadata: null,
      })
    ).rejects.toThrow(/not marked as a child/i);
  });

  it("removes the member, then deletes the child's data with parent as audit actor", async () => {
    const db = new FakeFirestore();
    seedFlaggedChild(db);
    const purges: RecordedPurge[] = [];

    const result = await requestChildDataDeletionFlow(
      asFirestore(db),
      {
        actorId: "parent",
        familyId: "fam1",
        childUserId: "kid",
        clientMetadata: CLIENT_METADATA,
      },
      stubDeps(purges)
    );
    expect(result.success).toBe(true);

    // Membership and personal data are gone.
    expect(db.store.has("families/fam1/members/kid")).toBe(false);
    expect(db.store.has("users/kid")).toBe(false);
    expect(db.store.has("users/kid/private/contact")).toBe(false);
    expect(db.store.has("user_progression/kid")).toBe(false);
    expect(db.store.has("public_lifetime_stats/kid")).toBe(false);
    expect(purges.map((p) => p.userId)).toEqual(["kid"]);

    // Exactly ONE revocation — parent_requested_deletion — plus the deletion record.
    const revoked = auditRowsOfType(db, "AUDIT_PARENTAL_CONSENT_REVOKED");
    expect(revoked).toHaveLength(1);
    const revokedMetadata = revoked[0].metadata as Record<string, unknown>;
    expect(revokedMetadata.reason).toBe("parent_requested_deletion");
    expect(revoked[0].actorId).toBe("parent");
    expect(revoked[0].subjectId).toBe("kid");
    expect(consentMetadataPiiViolations(revokedMetadata)).toEqual([]);

    const deleted = auditRowsOfType(db, "AUDIT_ACCOUNT_DELETED");
    expect(deleted).toHaveLength(1);
    expect(deleted[0].actorId).toBe("parent");
    expect(deleted[0].subjectId).toBe("kid");

    // The rest of the family is untouched.
    expect(db.store.has("families/fam1/members/parent")).toBe(true);
    expect(db.store.has("users/parent")).toBe(true);
  });
});

describe("getParentalConsentStatusFlow (FR-29)", () => {
  it("is manager-gated and returns only curated consent rows", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    db.seed("users/kid", { activeFamilyId: "fam1", isChildAccount: true });
    db.seed("families/fam1/members/kid", { role: "scout", isChild: true });
    db.seed("families/fam1/members/scout2", { role: "scout" });

    db.seed("audit_logs/r1", {
      eventType: "AUDIT_CHILD_REGISTRATION_DECLARED",
      actorId: "kid",
      subjectType: "user",
      subjectId: "kid",
      metadata: { childUserId: "kid", method: "self_declared" },
    });
    db.seed("audit_logs/r2", {
      eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
      actorId: "parent",
      subjectType: "user",
      subjectId: "kid",
      metadata: {
        familyId: "fam1",
        childUserId: "kid",
        actorRole: "creator",
        method: "family_admission",
        guardianAffirmed: true,
        consentTextVersion: "2026-08.1",
        affirmationVersion: "2026-08.1",
        expectedAgeOutYear: 2031,
      },
      clientMetadata: CLIENT_METADATA,
    });
    // Non-consent row about the same subject — must not leak into the response.
    db.seed("audit_logs/r3", {
      eventType: "AUDIT_ACCOUNT_DELETED",
      actorId: "kid",
      subjectType: "user",
      subjectId: "kid",
      metadata: {},
    });

    await expect(
      getParentalConsentStatusFlow(asFirestore(db), {
        actorId: "scout2",
        familyId: "fam1",
        childUserId: "kid",
      })
    ).rejects.toThrow(/Captains/i);

    const result = await getParentalConsentStatusFlow(asFirestore(db), {
      actorId: "parent",
      familyId: "fam1",
      childUserId: "kid",
    });
    expect(result.isChildAccount).toBe(true);
    expect(result.records).toHaveLength(2);
    const granted = result.records.find(
      (r) => r.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    )!;
    expect(granted.method).toBe("family_admission");
    expect(granted.guardianAffirmed).toBe(true);
    expect(granted.expectedAgeOutYear).toBe(2031);
    // Curated shape only — no actor uid, no clientMetadata.
    expect(granted).not.toHaveProperty("actorId");
    expect(granted).not.toHaveProperty("clientMetadata");
  });

  it("rejects when the target is not a flagged child member", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    await expect(
      getParentalConsentStatusFlow(asFirestore(db), {
        actorId: "parent",
        familyId: "fam1",
        childUserId: "cap",
      })
    ).rejects.toThrow(/not marked as a child/i);
  });
});

describe("applyChildProtectionsAfterFlagSet purge failure (FR-4)", () => {
  it("propagates a purge failure so the callable retries — the syncer exclusion is the backstop", async () => {
    const db = new FakeFirestore();
    seedFamily(db);
    await expect(
      applyChildProtectionsAfterFlagSet(
        asFirestore(db),
        { childUserId: "kid", familyMemberIds: ["parent"], childUserData: {} },
        {
          clearSearchIndexes: async () => {
            throw new Error("index purge unavailable");
          },
        }
      )
    ).rejects.toThrow(/index purge unavailable/);
  });
});
