import { describe, it, expect } from "vitest";
import {
  AUDIT_CHILD_REGISTRATION_DECLARED,
  AUDIT_PARENTAL_CONSENT_CORRECTED,
  AUDIT_PARENTAL_CONSENT_GRANTED,
  AUDIT_PARENTAL_CONSENT_REVOKED,
  CHILD_CONSENT_EVENT_TYPES,
  CHILD_CONSENT_REVOCATION_REASONS,
  CHILD_CONSENT_SCOPE,
  CHILD_STATUS_CORRECTION_REASONS,
  buildChildRegistrationDeclaredMetadata,
  buildConsentCorrectedMetadata,
  buildConsentGrantedMetadata,
  buildConsentRevokedMetadata,
  consentMetadataPiiViolations,
  evaluateApprovalChildDeclaration,
  isChildAccountUserData,
  isUnconsentedChildUserData,
  sanitizedChildLinkedPlatforms,
  validateExpectedAgeOutYear,
  validateSetChildStatusInput,
} from "./childAccountCore";
import { AUDIT_RETENTION_EXEMPT_EVENT_TYPES } from "./retentionCore";

const NOW_YEAR = 2026;

describe("consent event types", () => {
  it("every consent/lifecycle event type is exempt from audit-log retention (G-7)", () => {
    for (const eventType of CHILD_CONSENT_EVENT_TYPES) {
      expect(AUDIT_RETENTION_EXEMPT_EVENT_TYPES).toContain(eventType);
    }
  });

  it("pins the literal event type strings the SRS names", () => {
    expect(AUDIT_PARENTAL_CONSENT_GRANTED).toBe("AUDIT_PARENTAL_CONSENT_GRANTED");
    expect(AUDIT_PARENTAL_CONSENT_CORRECTED).toBe("AUDIT_PARENTAL_CONSENT_CORRECTED");
    expect(AUDIT_PARENTAL_CONSENT_REVOKED).toBe("AUDIT_PARENTAL_CONSENT_REVOKED");
    expect(AUDIT_CHILD_REGISTRATION_DECLARED).toBe("AUDIT_CHILD_REGISTRATION_DECLARED");
  });

  it("consentScope covers gameplay/search/analytics and NEVER location or ads (§11.1)", () => {
    expect([...CHILD_CONSENT_SCOPE]).toEqual([
      "gameplay",
      "search_excluded",
      "analytics_limited",
    ]);
    expect(CHILD_CONSENT_SCOPE.join(" ")).not.toMatch(/location|ads/);
  });
});

describe("child flag predicates", () => {
  it("missing flag or missing doc means adult", () => {
    expect(isChildAccountUserData(undefined)).toBe(false);
    expect(isChildAccountUserData(null)).toBe(false);
    expect(isChildAccountUserData({})).toBe(false);
    expect(isChildAccountUserData({ isChildAccount: false })).toBe(false);
    expect(isChildAccountUserData({ isChildAccount: "true" })).toBe(false);
    expect(isChildAccountUserData({ isChildAccount: true })).toBe(true);
  });

  it("unconsented = flag true with no active family", () => {
    expect(isUnconsentedChildUserData(undefined)).toBe(false);
    expect(isUnconsentedChildUserData({})).toBe(false);
    expect(isUnconsentedChildUserData({ isChildAccount: true })).toBe(true);
    expect(
      isUnconsentedChildUserData({ isChildAccount: true, activeFamilyId: "" })
    ).toBe(true);
    expect(
      isUnconsentedChildUserData({ isChildAccount: true, activeFamilyId: "fam1" })
    ).toBe(false);
    expect(isUnconsentedChildUserData({ activeFamilyId: "fam1" })).toBe(false);
  });
});

describe("validateExpectedAgeOutYear", () => {
  it("accepts absent, rejects out-of-range and non-integers", () => {
    expect(validateExpectedAgeOutYear(undefined, NOW_YEAR)).toEqual({
      ok: true,
      year: undefined,
    });
    expect(validateExpectedAgeOutYear(null, NOW_YEAR)).toEqual({
      ok: true,
      year: undefined,
    });
    expect(validateExpectedAgeOutYear(NOW_YEAR + 5, NOW_YEAR)).toEqual({
      ok: true,
      year: NOW_YEAR + 5,
    });
    expect(validateExpectedAgeOutYear(NOW_YEAR - 1, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYear(NOW_YEAR + 14, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYear(2030.5, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYear("2030", NOW_YEAR).ok).toBe(false);
  });
});

describe("validateSetChildStatusInput (FR-2)", () => {
  const base = {
    actorRole: "creator",
    actorUserId: "parent",
    targetUserId: "kid",
    targetRole: "scout",
    isChild: true,
    correctionReason: undefined,
    consentAcknowledged: true,
    guardianAffirmed: true,
    expectedAgeOutYear: undefined,
    nowYear: NOW_YEAR,
  };

  it("rejects non-manager actors", () => {
    for (const actorRole of ["scout", "sergeant", "retired_general", undefined]) {
      const decision = validateSetChildStatusInput({ ...base, actorRole });
      expect(decision.kind).toBe("reject");
      expect(decision.kind === "reject" && decision.code).toBe("permission-denied");
    }
  });

  it("allows captain actors", () => {
    expect(validateSetChildStatusInput({ ...base, actorRole: "captain" }).kind).toBe(
      "set"
    );
  });

  it("rejects self-targets and creator targets", () => {
    const self = validateSetChildStatusInput({ ...base, targetUserId: "parent" });
    expect(self.kind === "reject" && self.code).toBe("failed-precondition");

    const creator = validateSetChildStatusInput({ ...base, targetRole: "creator" });
    expect(creator.kind === "reject" && creator.code).toBe("failed-precondition");
  });

  it("set-true is a consent capture: both acknowledgments required (FR-31)", () => {
    for (const patch of [
      { consentAcknowledged: false },
      { guardianAffirmed: false },
      { consentAcknowledged: undefined },
      { guardianAffirmed: "yes" },
    ]) {
      const decision = validateSetChildStatusInput({ ...base, ...patch });
      expect(decision.kind === "reject" && decision.code).toBe("failed-precondition");
    }
  });

  it("set-true carries a validated expectedAgeOutYear through", () => {
    const decision = validateSetChildStatusInput({
      ...base,
      expectedAgeOutYear: NOW_YEAR + 3,
    });
    expect(decision).toEqual({ kind: "set", expectedAgeOutYear: NOW_YEAR + 3 });

    const invalid = validateSetChildStatusInput({
      ...base,
      expectedAgeOutYear: NOW_YEAR - 2,
    });
    expect(invalid.kind === "reject" && invalid.code).toBe("invalid-argument");
  });

  it("clear requires an enumerated correction reason — withdrawal is never a clear", () => {
    for (const correctionReason of CHILD_STATUS_CORRECTION_REASONS) {
      expect(
        validateSetChildStatusInput({ ...base, isChild: false, correctionReason })
      ).toEqual({ kind: "clear", correctionReason });
    }
    for (const correctionReason of [undefined, "", "withdrawn", "parent_removed_child"]) {
      const decision = validateSetChildStatusInput({
        ...base,
        isChild: false,
        correctionReason,
      });
      expect(decision.kind === "reject" && decision.code).toBe("invalid-argument");
    }
  });

  it("rejects non-boolean isChild", () => {
    const decision = validateSetChildStatusInput({ ...base, isChild: "true" });
    expect(decision.kind === "reject" && decision.code).toBe("invalid-argument");
  });
});

describe("evaluateApprovalChildDeclaration (FR-1 / FR-25)", () => {
  const base = {
    payloadIsChild: undefined as unknown,
    consentAcknowledged: undefined as unknown,
    guardianAffirmed: undefined as unknown,
    correctionReason: undefined as unknown,
    expectedAgeOutYear: undefined as unknown,
    targetIsChildAccount: false,
    nowYear: NOW_YEAR,
  };

  it("absent isChild on a non-sticky target is a plain approval", () => {
    expect(evaluateApprovalChildDeclaration(base)).toEqual({ kind: "none" });
  });

  it("sticky target without an explicit isChild is rejected — no silent laundering", () => {
    const decision = evaluateApprovalChildDeclaration({
      ...base,
      targetIsChildAccount: true,
    });
    expect(decision.kind === "reject" && decision.code).toBe("failed-precondition");
  });

  it("isChild true without both acknowledgments is rejected (FR-31)", () => {
    for (const patch of [
      { consentAcknowledged: true },
      { guardianAffirmed: true },
      {},
    ]) {
      const decision = evaluateApprovalChildDeclaration({
        ...base,
        payloadIsChild: true,
        ...patch,
      });
      expect(decision.kind === "reject" && decision.code).toBe("failed-precondition");
    }
  });

  it("isChild true with both acknowledgments grants (fresh grant even for sticky targets)", () => {
    for (const targetIsChildAccount of [false, true]) {
      expect(
        evaluateApprovalChildDeclaration({
          ...base,
          payloadIsChild: true,
          consentAcknowledged: true,
          guardianAffirmed: true,
          expectedAgeOutYear: NOW_YEAR + 4,
          targetIsChildAccount,
        })
      ).toEqual({ kind: "grant", expectedAgeOutYear: NOW_YEAR + 4 });
    }
  });

  it("isChild false clears sticky targets with full evidence, and is a no-op otherwise", () => {
    expect(
      evaluateApprovalChildDeclaration({
        ...base,
        payloadIsChild: false,
        targetIsChildAccount: true,
        consentAcknowledged: true,
        guardianAffirmed: true,
        correctionReason: "child_turned_13",
      })
    ).toEqual({ kind: "clear_new_guardian", correctionReason: "child_turned_13" });
    expect(
      evaluateApprovalChildDeclaration({ ...base, payloadIsChild: false })
    ).toEqual({ kind: "none" });
  });

  /**
   * FR-66(b). This branch used to return `clear_new_guardian` from a bare `isChild: false`
   * with no reason and no acknowledgment — strictly weaker than the in-family clear, and the
   * middle link of the self-made-captain laundering chain. Every way of arriving with
   * incomplete evidence must now be refused.
   */
  it("FR-66(b): an attestation-free clear on a sticky target is refused", () => {
    const clearAttempt = (patch: Record<string, unknown>) =>
      evaluateApprovalChildDeclaration({
        ...base,
        payloadIsChild: false,
        targetIsChildAccount: true,
        ...patch,
      });

    // The exact shape the pre-FR-66 chain relied on: nothing but `isChild: false`.
    expect(clearAttempt({}).kind).toBe("reject");

    // Acknowledgments missing or half-supplied.
    for (const patch of [
      { correctionReason: "child_turned_13" },
      { correctionReason: "child_turned_13", consentAcknowledged: true },
      { correctionReason: "child_turned_13", guardianAffirmed: true },
    ]) {
      const decision = clearAttempt(patch);
      expect(decision.kind === "reject" && decision.code).toBe("failed-precondition");
    }

    // Acknowledged, but the reason is absent or outside the enumerated set — same set the
    // in-family clear (`validateSetChildStatusInput`) has always required.
    for (const correctionReason of [undefined, "", "because_i_said_so", "new_guardian_cleared"]) {
      const decision = clearAttempt({
        consentAcknowledged: true,
        guardianAffirmed: true,
        correctionReason,
      });
      expect(decision.kind === "reject" && decision.code).toBe("invalid-argument");
    }

    // Both enumerated reasons are accepted, and the chosen one is carried out for the audit.
    for (const correctionReason of CHILD_STATUS_CORRECTION_REASONS) {
      expect(
        clearAttempt({
          consentAcknowledged: true,
          guardianAffirmed: true,
          correctionReason,
        })
      ).toEqual({ kind: "clear_new_guardian", correctionReason });
    }
  });

  it("FR-66(b): an unflagged target is still a no-op, evidence or not", () => {
    // The clear gate must not start demanding ceremony for the ordinary adult approval,
    // which is the overwhelming majority of traffic.
    expect(
      evaluateApprovalChildDeclaration({
        ...base,
        payloadIsChild: false,
        targetIsChildAccount: false,
      })
    ).toEqual({ kind: "none" });
  });

  it("rejects non-boolean isChild", () => {
    const decision = evaluateApprovalChildDeclaration({
      ...base,
      payloadIsChild: "yes",
    });
    expect(decision.kind === "reject" && decision.code).toBe("invalid-argument");
  });
});

describe("sanitizedChildLinkedPlatforms (FR-35b)", () => {
  it("strips email/phoneNumber/displayName, keeps identity keys", () => {
    const result = sanitizedChildLinkedPlatforms([
      {
        platform: "google",
        platformUserId: "g-1",
        linkedAt: 123,
        email: "kid@example.com",
        displayName: "Kid Name",
      },
      { platform: "apple", platformUserId: "a-1", linkedAt: 456 },
    ]);
    expect(result).not.toBeNull();
    expect(result!.changed).toBe(true);
    expect(result!.sanitized).toEqual([
      { platform: "google", platformUserId: "g-1", linkedAt: 123 },
      { platform: "apple", platformUserId: "a-1", linkedAt: 456 },
    ]);
  });

  it("reports unchanged for already-clean arrays and null for non-arrays", () => {
    const clean = sanitizedChildLinkedPlatforms([
      { platform: "apple", platformUserId: "a-1", linkedAt: 456 },
    ]);
    expect(clean!.changed).toBe(false);
    expect(sanitizedChildLinkedPlatforms(undefined)).toBeNull();
    expect(sanitizedChildLinkedPlatforms("google")).toBeNull();
  });
});

describe("consent metadata (§11.1) — uid-only, no PII ever", () => {
  const granted = buildConsentGrantedMetadata({
    familyId: "fam1",
    childUserId: "kid",
    actorRole: "creator",
    method: "manager_set",
    expectedAgeOutYear: 2031,
    removedFriendEdgeCount: 2,
  });

  it("GRANTED carries exactly the schema keys", () => {
    expect(Object.keys(granted).sort()).toEqual(
      [
        "familyId",
        "childUserId",
        "actorRole",
        "consentScope",
        "policyVersions",
        "consentTextVersion",
        "affirmationVersion",
        "guardianAffirmed",
        "method",
        "expectedAgeOutYear",
        "removedFriendEdgeCount",
      ].sort()
    );
    expect(granted.guardianAffirmed).toBe(true);
    expect(granted.consentScope).toEqual([...CHILD_CONSENT_SCOPE]);
  });

  it("GRANTED omits optional keys when absent", () => {
    const minimal = buildConsentGrantedMetadata({
      familyId: "fam1",
      childUserId: "kid",
      actorRole: "creator",
      method: "family_admission",
    });
    expect(minimal).not.toHaveProperty("expectedAgeOutYear");
    expect(minimal).not.toHaveProperty("removedFriendEdgeCount");
  });

  it("no builder output ever contains name/email/birthdate/phone keys", () => {
    const rows = [
      granted,
      buildConsentCorrectedMetadata({
        familyId: "fam1",
        childUserId: "kid",
        actorRole: "captain",
        method: "manager_correction",
        reason: "child_turned_13",
      }),
      buildConsentRevokedMetadata({
        familyId: "fam1",
        childUserId: "kid",
        actorRole: "creator",
        method: "remove_family_member",
        reason: "parent_removed_child",
      }),
      buildChildRegistrationDeclaredMetadata({ childUserId: "kid" }),
    ];
    for (const row of rows) {
      expect(consentMetadataPiiViolations(row)).toEqual([]);
      for (const forbidden of ["name", "email", "birthdate", "phoneNumber"]) {
        expect(row).not.toHaveProperty(forbidden);
      }
    }
  });

  it("the PII detector flags forbidden keys and email-like values", () => {
    expect(
      consentMetadataPiiViolations({ email: "kid@example.com" })
    ).toHaveLength(2);
    expect(
      consentMetadataPiiViolations({ actorRole: "parent@example.com" })
    ).toEqual(["email-like value under key: actorRole"]);
    expect(consentMetadataPiiViolations({ familyId: "fam1" })).toEqual([]);
  });

  it("every §8.3 exit path has an enumerated revocation reason", () => {
    expect([...CHILD_CONSENT_REVOCATION_REASONS].sort()).toEqual(
      [
        "parent_removed_child",
        "member_left_family",
        "family_inactivated",
        "creator_account_deleted",
        "member_account_deleted",
        "auth_user_deleted",
        "parent_requested_deletion",
      ].sort()
    );
  });
});
