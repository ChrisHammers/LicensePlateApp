import { describe, it, expect } from "vitest";
import {
  CONSENT_SCOPES_INVALID_MESSAGE,
  CONSENT_TEXT_OUTDATED_MESSAGE,
} from "./consentNoticeStrings";
import {
  AUDIT_CHILD_REGISTRATION_DECLARED,
  AUDIT_PARENTAL_CONSENT_CORRECTED,
  AUDIT_PARENTAL_CONSENT_GRANTED,
  AUDIT_PARENTAL_CONSENT_REVOKED,
  CHILD_CONSENT_EVENT_TYPES,
  CHILD_CONSENT_REVOCATION_REASONS,
  CHILD_STATUS_CORRECTION_REASONS,
  CONSENT_NOTICE_TEXT_VERSION,
  CONSENT_POLICY_VERSIONS,
  CONSENT_SCOPES_INVALID_REASON,
  CONSENT_SCOPE_CATALOG,
  CONSENT_SCOPE_IDS,
  CONSENT_SCOPE_PRACTICE_VERSIONS,
  CONSENT_TEXT_OUTDATED_REASON,
  CONSENT_TEXT_VERSION,
  buildChildRegistrationDeclaredMetadata,
  buildConsentCorrectedMetadata,
  buildConsentGrantedMetadata,
  buildConsentRevokedMetadata,
  buildScopeVector,
  consentMetadataPiiViolations,
  evaluateApprovalChildDeclaration,
  isChildAccountUserData,
  isUnconsentedChildUserData,
  sanitizedChildLinkedPlatforms,
  validateConsentScopeSelection,
  validateExpectedAgeOutYearMonth,
  validateSetChildStatusInput,
  validateStoredConsentEvidence,
  validateStoredScopeVector,
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

});

describe("F-21 version counters (slice 2, landed 2026-11-17)", () => {
  it("pins the consent text, notice text and privacy policy versions", () => {
    expect(CONSENT_TEXT_VERSION).toBe("2026-11-17.consent-scopes");
    // Bumped to notice-v2 by slice 3 (the scope restatements); see consentNoticeTextLock.test.ts.
    expect(CONSENT_NOTICE_TEXT_VERSION).toBe("2026-11-17.notice-v2");
    expect(CONSENT_POLICY_VERSIONS.privacyPolicy).toBe("2026-11-17.consent-scopes");
    // Terms of Service text did not change in this slice.
    expect(CONSENT_POLICY_VERSIONS.termsOfService).toBe("2026-08-09.c54758ed");
  });

  it("the rejection messages are the approved copy (shown raw by older builds)", () => {
    const approved =
      "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.";
    expect(CONSENT_TEXT_OUTDATED_MESSAGE).toBe(approved);
    expect(CONSENT_SCOPES_INVALID_MESSAGE).toBe(approved);
    expect(CONSENT_TEXT_OUTDATED_REASON).toBe("consent_text_outdated");
    expect(CONSENT_SCOPES_INVALID_REASON).toBe("consent_scopes_invalid");
  });
});

describe("consent scope catalog (FR-65 / FR-103)", () => {
  it("five ids in display order; core required, the other four frozen", () => {
    expect([...CONSENT_SCOPE_IDS]).toEqual([
      "core",
      "analytics_internal",
      "ads_child_directed",
      "location_family_shared",
      "cross_family_visibility",
    ]);
    expect(CONSENT_SCOPE_CATALOG.map((entry) => entry.id)).toEqual([...CONSENT_SCOPE_IDS]);
    expect(CONSENT_SCOPE_CATALOG.map((entry) => entry.availability)).toEqual([
      "required",
      "frozen",
      "frozen",
      "frozen",
      "frozen",
    ]);
  });

  it("every scope has a positive integer practice version, and only catalog scopes do", () => {
    expect(Object.keys(CONSENT_SCOPE_PRACTICE_VERSIONS).sort()).toEqual(
      [...CONSENT_SCOPE_IDS].sort()
    );
    for (const id of CONSENT_SCOPE_IDS) {
      const version = CONSENT_SCOPE_PRACTICE_VERSIONS[id];
      expect(Number.isInteger(version)).toBe(true);
      expect(version).toBeGreaterThan(0);
    }
  });
});

describe("validateConsentScopeSelection", () => {
  it('accepts exactly ["core"] at launch', () => {
    expect(validateConsentScopeSelection(["core"])).toEqual({ ok: true, selection: ["core"] });
  });

  it.each([
    ["an empty array", [], "required_scope_missing"],
    ["undefined", undefined, "not_an_array"],
    ["a bare string", "core", "not_an_array"],
    ["a duplicate", ["core", "core"], "duplicate_scope"],
    ["an unknown id", ["core", "x"], "unknown_scope"],
    ["a non-string entry", ["core", 1], "unknown_scope"],
    ["a frozen scope without core", ["analytics_internal"], "required_scope_missing"],
    ["core plus a frozen scope", ["core", "ads_child_directed"], "frozen_scope_selected"],
  ])("rejects %s", (_label, raw, reason) => {
    expect(validateConsentScopeSelection(raw)).toEqual({ ok: false, reason });
  });
});

describe("buildScopeVector", () => {
  const launchVector = {
    core: { state: "granted", practiceVersion: 1 },
    analytics_internal: { state: "unavailable", practiceVersion: 1 },
    ads_child_directed: { state: "unavailable", practiceVersion: 1 },
    location_family_shared: { state: "unavailable", practiceVersion: 1 },
    cross_family_visibility: { state: "unavailable", practiceVersion: 1 },
  };

  it("the launch selection gives core granted@1 and the other four unavailable@1", () => {
    expect(buildScopeVector(["core"])).toEqual(launchVector);
  });

  it("always carries all five keys, in catalog order", () => {
    expect(Object.keys(buildScopeVector(["core"]))).toEqual([...CONSENT_SCOPE_IDS]);
    expect(Object.keys(buildScopeVector([]))).toEqual([...CONSENT_SCOPE_IDS]);
  });

  it("a frozen scope is unavailable even if a caller passes it", () => {
    expect(buildScopeVector(["core", "analytics_internal"])).toEqual(launchVector);
  });
});

describe("validateStoredScopeVector", () => {
  const launch = () =>
    JSON.parse(JSON.stringify(buildScopeVector(["core"]))) as Record<string, any>;

  it("accepts the launch vector", () => {
    const vector = launch();
    expect(validateStoredScopeVector(vector)).toEqual({ ok: true, vector });
  });

  it("rejects a vector that is not an object", () => {
    expect(validateStoredScopeVector(undefined)).toEqual({ ok: false, reason: "not_an_object" });
    expect(validateStoredScopeVector(null)).toEqual({ ok: false, reason: "not_an_object" });
    expect(validateStoredScopeVector(["core"])).toEqual({ ok: false, reason: "not_an_object" });
  });

  it("rejects core not granted", () => {
    const vector = launch();
    vector.core.state = "declined";
    expect(validateStoredScopeVector(vector)).toEqual({
      ok: false,
      reason: "required_scope_not_granted",
    });
  });

  it("rejects a missing core key and any other missing key", () => {
    const noCore = launch();
    delete noCore.core;
    expect(validateStoredScopeVector(noCore)).toEqual({ ok: false, reason: "missing_scope" });
    const noFrozen = launch();
    delete noFrozen.cross_family_visibility;
    expect(validateStoredScopeVector(noFrozen)).toEqual({ ok: false, reason: "missing_scope" });
  });

  it("rejects an unknown key", () => {
    const vector = launch();
    vector.gameplay = { state: "granted", practiceVersion: 1 };
    expect(validateStoredScopeVector(vector)).toEqual({ ok: false, reason: "unknown_scope" });
  });

  it("rejects a present entry that is not a plain {state, practiceVersion} object", () => {
    for (const bad of ["granted", 1, null, ["granted", 1]]) {
      const vector = launch();
      vector.core = bad;
      expect(validateStoredScopeVector(vector)).toEqual({
        ok: false,
        reason: "malformed_scope_entry",
      });
    }
    const extraField = launch();
    extraField.core.note = "x";
    expect(validateStoredScopeVector(extraField)).toEqual({
      ok: false,
      reason: "malformed_scope_entry",
    });
  });

  it("returns a fresh vector, not the stored object", () => {
    const vector = launch();
    const result = validateStoredScopeVector(vector);
    expect(result).toEqual({ ok: true, vector });
    if (!result.ok) throw new Error("expected ok");
    expect(result.vector).not.toBe(vector);
    expect(result.vector.core).not.toBe(vector.core);
  });

  it("rejects a state outside the closed set", () => {
    const vector = launch();
    vector.core.state = "yes";
    expect(validateStoredScopeVector(vector)).toEqual({ ok: false, reason: "invalid_state" });
  });

  it.each(["granted", "declined"])("rejects a frozen scope set to %s", (state) => {
    const vector = launch();
    vector.location_family_shared.state = state;
    expect(validateStoredScopeVector(vector)).toEqual({
      ok: false,
      reason: "frozen_scope_not_unavailable",
    });
  });

  it("rejects a practice-version drift on any scope", () => {
    for (const id of CONSENT_SCOPE_IDS) {
      const vector = launch();
      vector[id].practiceVersion = CONSENT_SCOPE_PRACTICE_VERSIONS[id] + 1;
      expect(validateStoredScopeVector(vector)).toEqual({
        ok: false,
        reason: "practice_version_mismatch",
      });
    }
    const missingVersion = launch();
    delete missingVersion.core.practiceVersion;
    expect(validateStoredScopeVector(missingVersion)).toEqual({
      ok: false,
      reason: "practice_version_mismatch",
    });
  });

  it("an optional scope may be granted or declined, never unavailable", () => {
    const catalog = CONSENT_SCOPE_CATALOG.map((entry) =>
      entry.id === "analytics_internal" ? { ...entry, availability: "optional" as const } : entry
    );
    for (const state of ["granted", "declined"]) {
      const vector = launch();
      vector.analytics_internal.state = state;
      expect(validateStoredScopeVector(vector, catalog).ok).toBe(true);
    }
    expect(validateStoredScopeVector(launch(), catalog)).toEqual({
      ok: false,
      reason: "optional_scope_unavailable",
    });
  });
});

describe("validateStoredConsentEvidence (F-21)", () => {
  const stored = () => ({
    scopeVector: JSON.parse(JSON.stringify(buildScopeVector(["core"]))),
    consentTextVersion: CONSENT_TEXT_VERSION,
    noticeTextVersion: CONSENT_NOTICE_TEXT_VERSION,
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
    guardianEmail: "never-copied@example.com",
  });

  it("returns exactly the four evidence fields from a well-formed request", () => {
    expect(validateStoredConsentEvidence(stored())).toEqual({
      consentScopes: buildScopeVector(["core"]),
      consentTextVersion: CONSENT_TEXT_VERSION,
      noticeTextVersion: CONSENT_NOTICE_TEXT_VERSION,
      policyVersions: { ...CONSENT_POLICY_VERSIONS },
    });
  });

  it("does not compare the text versions with today's constants", () => {
    const older = { ...stored(), consentTextVersion: "2026-01-01.x", noticeTextVersion: "n" };
    expect(validateStoredConsentEvidence(older)?.consentTextVersion).toBe("2026-01-01.x");
  });

  it.each([
    ["a missing document", () => undefined],
    ["no vector (a pre-F-21 request)", () => ({ ...stored(), scopeVector: undefined })],
    [
      "a frozen scope granted",
      () => {
        const s = stored();
        s.scopeVector.ads_child_directed.state = "granted";
        return s;
      },
    ],
    [
      "core missing",
      () => {
        const s = stored();
        delete s.scopeVector.core;
        return s;
      },
    ],
    [
      "a practice-version drift",
      () => {
        const s = stored();
        s.scopeVector.core.practiceVersion = 2;
        return s;
      },
    ],
    ["no consentTextVersion", () => ({ ...stored(), consentTextVersion: undefined })],
    ["an empty noticeTextVersion", () => ({ ...stored(), noticeTextVersion: "" })],
    ["no policyVersions", () => ({ ...stored(), policyVersions: undefined })],
    ["empty policyVersions", () => ({ ...stored(), policyVersions: {} })],
    ["a non-string policy version", () => ({ ...stored(), policyVersions: { privacyPolicy: 3 } })],
  ])("refuses %s", (_label, make) => {
    expect(validateStoredConsentEvidence(make() as never)).toBeNull();
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

describe("validateExpectedAgeOutYearMonth", () => {
  it("accepts absent, rejects out-of-range months/years and non-integers", () => {
    expect(validateExpectedAgeOutYearMonth(undefined, NOW_YEAR)).toEqual({
      ok: true,
      yearMonth: undefined,
    });
    expect(validateExpectedAgeOutYearMonth(null, NOW_YEAR)).toEqual({
      ok: true,
      yearMonth: undefined,
    });
    // Owner ruling 2026-08-27: full month + year, one YYYYMM integer.
    expect(validateExpectedAgeOutYearMonth((NOW_YEAR + 5) * 100 + 3, NOW_YEAR)).toEqual({
      ok: true,
      yearMonth: (NOW_YEAR + 5) * 100 + 3,
    });
    // Year window unchanged from the year-only rule.
    expect(validateExpectedAgeOutYearMonth((NOW_YEAR - 1) * 100 + 6, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYearMonth((NOW_YEAR + 14) * 100 + 6, NOW_YEAR).ok).toBe(false);
    // Month bounds.
    expect(validateExpectedAgeOutYearMonth(NOW_YEAR * 100, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYearMonth(NOW_YEAR * 100 + 13, NOW_YEAR).ok).toBe(false);
    // A bare year (the superseded shape) no longer validates — its "month" is 30.
    expect(validateExpectedAgeOutYearMonth(NOW_YEAR + 5, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYearMonth(203006.5, NOW_YEAR).ok).toBe(false);
    expect(validateExpectedAgeOutYearMonth("203006", NOW_YEAR).ok).toBe(false);
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
    expectedAgeOutYearMonth: undefined,
    consentScopes: ["core"] as unknown,
    consentTextVersion: CONSENT_TEXT_VERSION as unknown,
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
    expect(
      validateSetChildStatusInput({
        ...base,
        actorRole: "captain",
        expectedAgeOutYearMonth: (NOW_YEAR + 3) * 100 + 7,
      }).kind
    ).toBe("set");
  });

  // Owner ruling 2026-08-28 (manager_set → email_plus): the attestation is the ONLY
  // possible age-out source for a mid-membership child, so set-true REQUIRES it —
  // unlike the join-approve path, where the gate-derived marker exists.
  it("set-true without the turns-13 attestation is refused", () => {
    const decision = validateSetChildStatusInput(base); // base carries no attestation
    expect(decision.kind === "reject" && decision.code).toBe("invalid-argument");
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

  it("set-true carries a validated expectedAgeOutYearMonth through", () => {
    const decision = validateSetChildStatusInput({
      ...base,
      expectedAgeOutYearMonth: (NOW_YEAR + 3) * 100 + 9,
    });
    expect(decision).toEqual({
      kind: "set",
      expectedAgeOutYearMonth: (NOW_YEAR + 3) * 100 + 9,
      consentScopes: ["core"],
      consentTextVersion: CONSENT_TEXT_VERSION,
    });

    const invalid = validateSetChildStatusInput({
      ...base,
      expectedAgeOutYearMonth: (NOW_YEAR - 2) * 100 + 9,
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

  // F-21 (FR-65 / FR-103): the consent text version and the scope selection.
  const attested = { expectedAgeOutYearMonth: (NOW_YEAR + 3) * 100 + 9 };

  it("set-true with another (or no) consent text version is refused with details.reason", () => {
    for (const consentTextVersion of [undefined, "", "1.0.0-2026-08-10", 7]) {
      expect(
        validateSetChildStatusInput({ ...base, ...attested, consentTextVersion })
      ).toEqual({
        kind: "reject",
        code: "failed-precondition",
        message: CONSENT_TEXT_OUTDATED_MESSAGE,
        details: { reason: "consent_text_outdated" },
      });
    }
  });

  it.each([
    ["absent", undefined],
    ["empty", []],
    ["a frozen scope added", ["core", "analytics_internal"]],
    ["an unknown id", ["core", "x"]],
    ["a duplicate", ["core", "core"]],
  ])("set-true with a scope selection that is %s is refused with details.reason", (_l, consentScopes) => {
    expect(validateSetChildStatusInput({ ...base, ...attested, consentScopes })).toEqual({
      kind: "reject",
      code: "failed-precondition",
      message: CONSENT_SCOPES_INVALID_MESSAGE,
      details: { reason: "consent_scopes_invalid" },
    });
  });

  it("the text version is checked before the selection", () => {
    const decision = validateSetChildStatusInput({
      ...base,
      ...attested,
      consentScopes: undefined,
      consentTextVersion: undefined,
    });
    expect(decision.kind === "reject" && decision.details).toEqual({
      reason: "consent_text_outdated",
    });
  });

  it("a clear ignores the consent fields entirely", () => {
    expect(
      validateSetChildStatusInput({
        ...base,
        isChild: false,
        correctionReason: "child_turned_13",
        consentScopes: undefined,
        consentTextVersion: undefined,
      })
    ).toEqual({ kind: "clear", correctionReason: "child_turned_13" });
  });
});

describe("evaluateApprovalChildDeclaration (FR-1 / FR-25)", () => {
  const base = {
    payloadIsChild: undefined as unknown,
    consentAcknowledged: undefined as unknown,
    guardianAffirmed: undefined as unknown,
    correctionReason: undefined as unknown,
    expectedAgeOutYearMonth: undefined as unknown,
    consentScopes: ["core"] as unknown,
    consentTextVersion: CONSENT_TEXT_VERSION as unknown,
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
          expectedAgeOutYearMonth: (NOW_YEAR + 4) * 100 + 2,
          targetIsChildAccount,
        })
      ).toEqual({
        kind: "grant",
        expectedAgeOutYearMonth: (NOW_YEAR + 4) * 100 + 2,
        consentScopes: ["core"],
        consentTextVersion: CONSENT_TEXT_VERSION,
      });
    }
  });

  const childAck = { payloadIsChild: true, consentAcknowledged: true, guardianAffirmed: true };

  it("F-21: isChild true with another (or no) consent text version is refused with details.reason", () => {
    for (const consentTextVersion of [undefined, "1.0.0-2026-08-10"]) {
      expect(
        evaluateApprovalChildDeclaration({ ...base, ...childAck, consentTextVersion })
      ).toEqual({
        kind: "reject",
        code: "failed-precondition",
        message: CONSENT_TEXT_OUTDATED_MESSAGE,
        details: { reason: "consent_text_outdated" },
      });
    }
  });

  it("F-21: isChild true with an invalid scope selection is refused with details.reason", () => {
    for (const consentScopes of [undefined, [], ["core", "ads_child_directed"], "core"]) {
      expect(
        evaluateApprovalChildDeclaration({ ...base, ...childAck, consentScopes })
      ).toEqual({
        kind: "reject",
        code: "failed-precondition",
        message: CONSENT_SCOPES_INVALID_MESSAGE,
        details: { reason: "consent_scopes_invalid" },
      });
    }
  });

  it("F-21: adult approvals and the new-guardian clear need no consent fields", () => {
    const noConsent = { consentScopes: undefined, consentTextVersion: undefined };
    expect(evaluateApprovalChildDeclaration({ ...base, ...noConsent })).toEqual({ kind: "none" });
    expect(
      evaluateApprovalChildDeclaration({
        ...base,
        ...noConsent,
        payloadIsChild: false,
        targetIsChildAccount: true,
        consentAcknowledged: true,
        guardianAffirmed: true,
        correctionReason: "child_turned_13",
      })
    ).toEqual({ kind: "clear_new_guardian", correctionReason: "child_turned_13" });
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
  // Deliberately NOT the current constants: the builder must record what the request
  // stored, so a row's versions are the ones the captain and guardian actually saw.
  const evidence = {
    consentScopes: buildScopeVector(["core"]),
    consentTextVersion: "2026-01-01.older-text",
    noticeTextVersion: "2026-01-01.notice-older",
    policyVersions: { termsOfService: "t-old", privacyPolicy: "p-old" },
    consentRequestId: "req123",
  };
  const granted = buildConsentGrantedMetadata({
    familyId: "fam1",
    childUserId: "kid",
    actorRole: "creator",
    method: "email_plus",
    expectedAgeOutYearMonth: 203107,
    removedFriendEdgeCount: 2,
    assuranceLevel: 1,
    ageOutYearMonth: 203107,
    ...evidence,
  });

  it("GRANTED carries exactly the schema keys — the F-21 evidence, and no legacy consentScope", () => {
    expect(Object.keys(granted).sort()).toEqual(
      [
        "familyId",
        "childUserId",
        "actorRole",
        "consentScopes",
        "policyVersions",
        "consentTextVersion",
        "noticeTextVersion",
        "consentRequestId",
        "affirmationVersion",
        "guardianAffirmed",
        "method",
        "expectedAgeOutYearMonth",
        "removedFriendEdgeCount",
        "assuranceLevel",
        "ageOutYearMonth",
      ].sort()
    );
    expect(granted.guardianAffirmed).toBe(true);
    expect(granted).not.toHaveProperty("consentScope");
  });

  it("GRANTED records the evidence it was given, not the current constants", () => {
    expect(granted.consentScopes).toEqual(buildScopeVector(["core"]));
    expect(granted.consentTextVersion).toBe("2026-01-01.older-text");
    expect(granted.noticeTextVersion).toBe("2026-01-01.notice-older");
    expect(granted.policyVersions).toEqual({ termsOfService: "t-old", privacyPolicy: "p-old" });
    expect(granted.consentRequestId).toBe("req123");
  });

  it("GRANTED omits optional keys when absent", () => {
    const minimal = buildConsentGrantedMetadata({
      familyId: "fam1",
      childUserId: "kid",
      actorRole: "creator",
      method: "email_plus",
      ageOutYearMonth: 203107,
      ...evidence,
    });
    expect(minimal).not.toHaveProperty("expectedAgeOutYearMonth");
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
        // member_flag email_plus request lapsed unconfirmed (owner ruling 2026-08-28).
        "consent_not_obtained",
      ].sort()
    );
  });
});
