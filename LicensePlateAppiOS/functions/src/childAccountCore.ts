/**
 * Child-signal core — COPPA remediation F-5a (FR-1…FR-6, FR-25…FR-28, FR-31, §11).
 *
 * Pure decision logic and consent-record builders for the per-child family-member signal.
 * No Firebase imports at all, so every rule here is unit-testable. The Firestore wiring
 * lives in `familyChildStatusFlows.ts` / `familyChildStatus.ts` / `childConsent.ts`.
 *
 * Vocabulary (§4 of the SRS):
 *  - `users/{uid}.isChildAccount == true` — the authoritative child flag. Missing ⇒ NOT a
 *    child (matches the missing-`isRegistered`-⇒-registered convention).
 *  - "Unconsented child" — flag true and no active family (provisional after
 *    `declareChildRegistration`, or post-revocation sticky). Restricted state: cloud
 *    gameplay collection stops (FR-28).
 *  - "Correction" clears the flag because the person is not / no longer under 13.
 *    "Revocation" ends consent for someone who is still a child — the flag stays true.
 */

// ---------------------------------------------------------------------------
// Consent-record constants (§11.1) — event types MUST match the retention
// exemption list in `retentionCore.ts` so these rows survive the audit-log
// retention job forever (G-7). `childAccountCore.test.ts` pins the match.
// ---------------------------------------------------------------------------

export const AUDIT_PARENTAL_CONSENT_GRANTED = "AUDIT_PARENTAL_CONSENT_GRANTED";
export const AUDIT_PARENTAL_CONSENT_CORRECTED = "AUDIT_PARENTAL_CONSENT_CORRECTED";
export const AUDIT_PARENTAL_CONSENT_REVOKED = "AUDIT_PARENTAL_CONSENT_REVOKED";
export const AUDIT_CHILD_REGISTRATION_DECLARED = "AUDIT_CHILD_REGISTRATION_DECLARED";

export const CHILD_CONSENT_EVENT_TYPES: readonly string[] = [
  AUDIT_CHILD_REGISTRATION_DECLARED,
  AUDIT_PARENTAL_CONSENT_GRANTED,
  AUDIT_PARENTAL_CONSENT_CORRECTED,
  AUDIT_PARENTAL_CONSENT_REVOKED,
];

/**
 * Versions stamped on every consent capture (FR-31). These are the durable
 * evidence of exactly which wording a parent consented to, so the DISCIPLINE
 * matters more than the format: ANY edit to the consent copy, the guardian
 * affirmation sentence, ToS §2, or Privacy Policy §12 MUST bump the matching
 * constant in the same commit. Policy versions pin the git commit that last
 * touched the legal text in HelpAboutView.swift (owner-maintained; no external
 * counsel pre-launch per owner decision 2026-08-10 — see SRS OQ-2).
 * A date+slug version ("YYYY-MM-DD.slug") is acceptable when the wording change
 * lands in the same change as the bump — the change itself is the pin.
 */
export const CONSENT_TEXT_VERSION = "2026-11-17.consent-scopes";
export const AFFIRMATION_VERSION = "1.0.0-2026-08-10";

/**
 * SHA-256 hex digest of `JSON.stringify([en, es, fr])` for the localized
 * `family.child.guardian_affirmation` string (the sentence AFFIRMATION_VERSION pins —
 * see the header comment in `FamilyChildConsentBlock.swift`). Recorded here, alongside
 * the version, as a machine-checkable lock: `affirmationTextLock.test.ts` recomputes
 * this hash from the live `en/es/fr.lproj/Localizable.strings` files on every run and
 * fails if it drifts. If you're updating this constant because the wording
 * intentionally changed, bump BOTH `AFFIRMATION_VERSION` and `CONSENT_TEXT_VERSION`
 * above in the SAME commit — do not update the hash alone.
 */
export const AFFIRMATION_TEXT_HASH =
  "1051f1534c0e6029d739bfef368462797e7108318abee57517d84307e8b70466";

export const CONSENT_POLICY_VERSIONS: Readonly<Record<string, string>> = {
  termsOfService: "2026-08-09.c54758ed",
  // 2026-11-17 (F-21 slice 2): §12 rewritten — the intro plus the per-scope subsections
  // 12.1–12.5 the consent cards link to, and the "Last updated" date.
  privacyPolicy: "2026-11-17.consent-scopes",
};

/**
 * SHA-256 hex digest of the app-shown consent text that CONSENT_TEXT_VERSION covers
 * (F-21 / FR-103): the values of `CONSENT_TEXT_KEYS` in `consentTextLock.test.ts`, in
 * that fixed order, for en, es and fr. The test recomputes it from the live
 * `Localizable.strings` files on every run, so changing any of those strings without
 * bumping CONSENT_TEXT_VERSION (and the fixture + Swift constant with it) fails the
 * suite. Update the hash only together with a version bump.
 */
export const CONSENT_TEXT_HASH =
  "d40407aaf657e820a72f16c39cfeef4e2d200db1847838e3f856169a409a40a7";

/**
 * Version of the server-only consent notice text (F-21 versionBump, counter 2): the
 * request email, the plus notice, the confirmation pages and the two rejection
 * messages below. Stamped on every consent request at creation and copied into the
 * GRANTED row. Never sent by or compared with the client, so a notice-text fix needs
 * no app release. Slice 3 moves that text into one module and adds a hash lock;
 * until then this constant is pinned by value only.
 */
export const CONSENT_NOTICE_TEXT_VERSION = "2026-11-17.notice-v1";

// ---------------------------------------------------------------------------
// Consent scope catalog (v3 FR-65 / v4 FR-103, F-21 slice 1)
//
// One closed list of consent scopes, in display order. Lattice precedent: the
// Swift `ConsentScopeCatalog` mirrors these constants, and the test-only fixture
// `consentScopeCatalog.v1.json` (byte-identical to the copy in LicensePlateAppTests/)
// pins both sides — `consentScopeParity.test.ts` here, `ConsentScopeCatalogParityTests`
// in Swift. Nothing loads the JSON at runtime.
//
// Both child-consent entry points validate a selection with `validateConsentScopeSelection`;
// the request stores `buildScopeVector`'s result; both FR-64 commits re-check it with
// `validateStoredConsentEvidence` before recording it.
// ---------------------------------------------------------------------------

export const CONSENT_SCOPE_IDS = [
  "core",
  "analytics_internal",
  "ads_child_directed",
  "location_family_shared",
  "cross_family_visibility",
] as const;

export type ConsentScopeId = (typeof CONSENT_SCOPE_IDS)[number];

/**
 * `required`: always part of a consent; `frozen`: not offered at launch, recorded as
 * `unavailable`; `optional`: exists in the type only — no scope uses it at launch.
 */
export type ConsentScopeAvailability = "required" | "optional" | "frozen";

export interface ConsentScopeCatalogEntry {
  id: ConsentScopeId;
  availability: ConsentScopeAvailability;
  /** In-app Privacy Policy anchor for this scope (`rtr-legal://<policyAnchor>`). */
  policyAnchor: string;
}

export const CONSENT_SCOPE_CATALOG: readonly ConsentScopeCatalogEntry[] = [
  { id: "core", availability: "required", policyAnchor: "privacy-children-core" },
  {
    id: "analytics_internal",
    availability: "frozen",
    policyAnchor: "privacy-children-analytics",
  },
  { id: "ads_child_directed", availability: "frozen", policyAnchor: "privacy-children-ads" },
  {
    id: "location_family_shared",
    availability: "frozen",
    policyAnchor: "privacy-children-location",
  },
  {
    id: "cross_family_visibility",
    availability: "frozen",
    policyAnchor: "privacy-children-cross-family",
  },
];

/** Per-scope practice version (FR-104): a positive integer, bumped only on a material change. */
export const CONSENT_SCOPE_PRACTICE_VERSIONS: Readonly<Record<ConsentScopeId, number>> = {
  core: 1,
  analytics_internal: 1,
  ads_child_directed: 1,
  location_family_shared: 1,
  cross_family_visibility: 1,
};

export type ConsentScopeState = "granted" | "declined" | "unavailable";

/** Always carries all five keys. */
export type ConsentScopeVector = Record<
  ConsentScopeId,
  { state: ConsentScopeState; practiceVersion: number }
>;

export type ConsentScopeSelectionRejectionReason =
  | "not_an_array"
  | "unknown_scope"
  | "duplicate_scope"
  | "required_scope_missing"
  | "frozen_scope_selected";

export type ConsentScopeSelectionResult =
  | { ok: true; selection: ConsentScopeId[] }
  | { ok: false; reason: ConsentScopeSelectionRejectionReason };

function isConsentScopeId(value: unknown): value is ConsentScopeId {
  return (
    typeof value === "string" && (CONSENT_SCOPE_IDS as readonly string[]).includes(value)
  );
}

/**
 * Validates a client-sent scope selection. Checks run in this order, and the first
 * failure is the reason: an array; of known ids; with no duplicates; every required
 * scope present; no frozen scope. At launch the only valid selection is ["core"].
 * The selection comes back in catalog order.
 */
export function validateConsentScopeSelection(raw: unknown): ConsentScopeSelectionResult {
  if (!Array.isArray(raw)) return { ok: false, reason: "not_an_array" };
  if (!raw.every(isConsentScopeId)) return { ok: false, reason: "unknown_scope" };
  const ids = raw as ConsentScopeId[];
  if (new Set(ids).size !== ids.length) return { ok: false, reason: "duplicate_scope" };
  for (const entry of CONSENT_SCOPE_CATALOG) {
    if (entry.availability === "required" && !ids.includes(entry.id)) {
      return { ok: false, reason: "required_scope_missing" };
    }
  }
  for (const entry of CONSENT_SCOPE_CATALOG) {
    if (entry.availability === "frozen" && ids.includes(entry.id)) {
      return { ok: false, reason: "frozen_scope_selected" };
    }
  }
  return {
    ok: true,
    selection: CONSENT_SCOPE_CATALOG.map((entry) => entry.id).filter((id) => ids.includes(id)),
  };
}

/**
 * Builds the full vector for a selection that passed `validateConsentScopeSelection`:
 * frozen scopes are `unavailable`, selected scopes `granted`, any other scope `declined`,
 * each at its current practice version. With the launch selection ["core"] this gives
 * core = granted@1 and the other four = unavailable@1.
 */
export function buildScopeVector(selection: readonly ConsentScopeId[]): ConsentScopeVector {
  const vector = {} as ConsentScopeVector;
  for (const entry of CONSENT_SCOPE_CATALOG) {
    const state: ConsentScopeState =
      entry.availability === "frozen"
        ? "unavailable"
        : selection.includes(entry.id)
          ? "granted"
          : "declined";
    vector[entry.id] = { state, practiceVersion: CONSENT_SCOPE_PRACTICE_VERSIONS[entry.id] };
  }
  return vector;
}

export type StoredScopeVectorRejectionReason =
  | "not_an_object"
  | "missing_scope"
  | "unknown_scope"
  | "malformed_scope_entry"
  | "invalid_state"
  | "required_scope_not_granted"
  | "frozen_scope_not_unavailable"
  | "optional_scope_unavailable"
  | "practice_version_mismatch";

export type StoredScopeVectorResult =
  | { ok: true; vector: ConsentScopeVector }
  | { ok: false; reason: StoredScopeVectorRejectionReason };

const CONSENT_SCOPE_STATES: readonly string[] = ["granted", "declined", "unavailable"];

/**
 * Re-checks a vector read back from storage before it is committed as evidence:
 * exactly the catalog's keys, each an object with no field besides `state` and
 * `practiceVersion`; every required scope `granted`; every frozen scope
 * `unavailable`; an optional scope `granted` or `declined`; and every practiceVersion
 * equal to the current one (a drift means the request predates a material change).
 * On success the vector returned is a fresh object rebuilt from the checked fields.
 */
export function validateStoredScopeVector(
  vector: unknown,
  catalog: readonly ConsentScopeCatalogEntry[] = CONSENT_SCOPE_CATALOG,
  practiceVersions: Readonly<Record<ConsentScopeId, number>> = CONSENT_SCOPE_PRACTICE_VERSIONS
): StoredScopeVectorResult {
  if (typeof vector !== "object" || vector === null || Array.isArray(vector)) {
    return { ok: false, reason: "not_an_object" };
  }
  const record = vector as Record<string, unknown>;
  const catalogIds: readonly string[] = catalog.map((entry) => entry.id);
  if (Object.keys(record).some((key) => !catalogIds.includes(key))) {
    return { ok: false, reason: "unknown_scope" };
  }
  const checked = {} as ConsentScopeVector;
  for (const entry of catalog) {
    const value = record[entry.id];
    if (value === undefined) {
      return { ok: false, reason: "missing_scope" };
    }
    if (
      typeof value !== "object" ||
      value === null ||
      Array.isArray(value) ||
      Object.keys(value).some((key) => key !== "state" && key !== "practiceVersion")
    ) {
      return { ok: false, reason: "malformed_scope_entry" };
    }
    const { state, practiceVersion } = value as Record<string, unknown>;
    if (typeof state !== "string" || !CONSENT_SCOPE_STATES.includes(state)) {
      return { ok: false, reason: "invalid_state" };
    }
    if (entry.availability === "required" && state !== "granted") {
      return { ok: false, reason: "required_scope_not_granted" };
    }
    if (entry.availability === "frozen" && state !== "unavailable") {
      return { ok: false, reason: "frozen_scope_not_unavailable" };
    }
    if (entry.availability === "optional" && state === "unavailable") {
      return { ok: false, reason: "optional_scope_unavailable" };
    }
    if (practiceVersion !== practiceVersions[entry.id]) {
      return { ok: false, reason: "practice_version_mismatch" };
    }
    checked[entry.id] = {
      state: state as ConsentScopeState,
      practiceVersion: practiceVersions[entry.id],
    };
  }
  return { ok: true, vector: checked };
}

/** FR-2: the only reasons a manager may CLEAR the flag (corrections, not withdrawals). */
export const CHILD_STATUS_CORRECTION_REASONS: readonly string[] = [
  "flag_set_in_error",
  "child_turned_13",
];

/**
 * FR-6 / §8.3: reasons a REVOKED record may carry. One per membership-exit path.
 * `member_left_family` covers the self-leave branch of `removeFamilyMember`, which the
 * SRS's enumeration missed but FR-6's "membership ends by any path" requires.
 */
export const CHILD_CONSENT_REVOCATION_REASONS: readonly string[] = [
  "parent_removed_child",
  "member_left_family",
  "family_inactivated",
  "creator_account_deleted",
  "member_account_deleted",
  "auth_user_deleted",
  "parent_requested_deletion",
  // Owner ruling 2026-08-28: a mid-membership child flag whose email_plus request
  // lapsed unconfirmed — refusal by silence removes the member (account survives).
  "consent_not_obtained",
];

export type ChildConsentRevocationReason =
  (typeof CHILD_CONSENT_REVOCATION_REASONS)[number];

/** Roles allowed to set/clear child status and request child data deletion (OQ-1). */
export const CHILD_STATUS_MANAGER_ROLES: readonly string[] = ["creator", "captain"];

/** expectedAgeOutYearMonth sanity window: a child is under 13 today (FR-26). */
const MAX_AGE_OUT_YEARS_AHEAD = 13;

// ---------------------------------------------------------------------------
// Flag / state predicates
// ---------------------------------------------------------------------------

/** Authoritative child check on a `users/{uid}` snapshot. Missing flag ⇒ not a child. */
export function isChildAccountUserData(
  data: Record<string, unknown> | undefined | null
): boolean {
  return data?.isChildAccount === true;
}

function hasActiveFamily(data: Record<string, unknown> | undefined | null): boolean {
  const familyId = data?.activeFamilyId;
  return typeof familyId === "string" && familyId.length > 0;
}

/**
 * FR-28: an unconsented child (provisional or post-revocation) has no gameplay or
 * profile-enriching cloud collection. `activeFamilyId` is the server-managed consent
 * proxy: it is set exactly when a manager admits the child and cleared on every exit.
 */
export function isUnconsentedChildUserData(
  data: Record<string, unknown> | undefined | null
): boolean {
  return isChildAccountUserData(data) && !hasActiveFamily(data);
}

/**
 * FR-15: a child who is already in a parent-managed family. A *new* family may not invite
 * them (their consenting manager would silently change); an UNCONSENTED child stays
 * invitable because family admission is exactly the path back to consented play.
 */
export function isChildWithActiveFamilyUserData(
  data: Record<string, unknown> | undefined | null
): boolean {
  return isChildAccountUserData(data) && hasActiveFamily(data);
}

// ---------------------------------------------------------------------------
// Rejection messages (FR-13/14/15/24/38)
// ---------------------------------------------------------------------------

/**
 * FR-24: child-target rejections reuse the EXACT wording of the existing privacy opt-out
 * rejection (`friends.ts` / `family.ts`), so a sender can never distinguish "this person is
 * a child" from "this person turned contact search off", and the sender-side analytics
 * mapping (`FriendsFamilyInviteAnalytics.swift` — `lower.contains("not searchable")`)
 * already classifies it without any new event.
 */
export const CHILD_TARGET_NOT_SEARCHABLE_MESSAGE =
  "User is not searchable by this method";

/**
 * FR-24 actor side. Same "not searchable" family of wording (so it lands on the same
 * client mapping and no analytics event exists that fires only for child sessions —
 * adults hitting a privacy opt-out emit the same one), with `details.reason` for the
 * client to key its non-punitive copy off, mirroring `unconsented_child`.
 */
export const CHILD_CALLER_NOT_SEARCHABLE_MESSAGE =
  "This account is not searchable and cannot start new connections";

export const CHILD_CALLER_REJECTION_REASON = "child_account";

/**
 * FR-38: family-only trips. Used only where the actor is either the child themselves or an
 * existing participant of a child-containing trip (who is therefore already in that
 * child's family), so the wording may be explicit without disclosing anything new.
 */
export const CHILD_FAMILY_ONLY_TRIP_MESSAGE =
  "Trips that include a child are limited to that child's family";

// ---------------------------------------------------------------------------
// Payload validation
// ---------------------------------------------------------------------------

export interface ChildStatusRejection {
  kind: "reject";
  code: "invalid-argument" | "failed-precondition" | "permission-denied" | "not-found";
  message: string;
  /** Passed through as the HttpsError's `details`; the client keys its copy off `reason`. */
  details?: { reason: string };
}

function reject(
  code: ChildStatusRejection["code"],
  message: string,
  details?: { reason: string }
): ChildStatusRejection {
  return details ? { kind: "reject", code, message, details } : { kind: "reject", code, message };
}

/** `details.reason` when the client sent a consent text version other than CONSENT_TEXT_VERSION. */
export const CONSENT_TEXT_OUTDATED_REASON = "consent_text_outdated";
/** `details.reason` when the client's scope selection fails `validateConsentScopeSelection`. */
export const CONSENT_SCOPES_INVALID_REASON = "consent_scopes_invalid";

/**
 * The HttpsError messages for the two reasons above (approved copy deck,
 * notice.reject.*; the same text on purpose). Builds without the reason mapping show
 * the raw message, so it must read as an instruction to the captain. Server text,
 * under CONSENT_NOTICE_TEXT_VERSION.
 */
export const CONSENT_TEXT_OUTDATED_MESSAGE =
  "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.";
export const CONSENT_SCOPES_INVALID_MESSAGE =
  "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.";

export type ConsentCaptureCheck =
  | { ok: true; consentScopes: ConsentScopeId[]; consentTextVersion: string }
  | { ok: false; rejection: ChildStatusRejection };

/**
 * F-21 (FR-65 / FR-103): the consent-text and scope gate shared by both child-consent
 * entry points. The text version is checked first: a build that shows other wording is
 * refused even when its selection happens to be valid, so no request is ever stamped
 * with a version the captain did not see.
 */
export function checkConsentCapture(input: {
  consentScopes?: unknown;
  consentTextVersion?: unknown;
}): ConsentCaptureCheck {
  if (input.consentTextVersion !== CONSENT_TEXT_VERSION) {
    return {
      ok: false,
      rejection: reject("failed-precondition", CONSENT_TEXT_OUTDATED_MESSAGE, {
        reason: CONSENT_TEXT_OUTDATED_REASON,
      }),
    };
  }
  const selection = validateConsentScopeSelection(input.consentScopes);
  if (!selection.ok) {
    return {
      ok: false,
      rejection: reject("failed-precondition", CONSENT_SCOPES_INVALID_MESSAGE, {
        reason: CONSENT_SCOPES_INVALID_REASON,
      }),
    };
  }
  return { ok: true, consentScopes: selection.selection, consentTextVersion: CONSENT_TEXT_VERSION };
}

export type ExpectedAgeOutYearResult =
  | { ok: true; yearMonth: number | undefined }
  | { ok: false; message: string };

/**
 * Optional, parent-supplied, MONTH + YEAR as one comparable integer `YYYYMM` (owner
 * ruling 2026-08-27: "year they turn 13 should now have the full month and year").
 * Supersedes the year-only form outright (pre-release delete rule; AGEOUT's naming note
 * forbids month-granular data hiding in a "...Year" field). Distinct from the
 * device-derived `ageOutYearMonth` by name AND provenance: this one is guardian-typed
 * attestation, that one is gate-derived protection state — never conflate them.
 */
export function validateExpectedAgeOutYearMonth(
  value: unknown,
  nowYear: number
): ExpectedAgeOutYearResult {
  if (value === undefined || value === null) {
    return { ok: true, yearMonth: undefined };
  }
  const month = typeof value === "number" ? value % 100 : 0;
  const year = typeof value === "number" ? Math.floor(value / 100) : 0;
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    month < 1 ||
    month > 12 ||
    year < nowYear ||
    year > nowYear + MAX_AGE_OUT_YEARS_AHEAD
  ) {
    return {
      ok: false,
      message: `expectedAgeOutYearMonth must be YYYYMM with a year between ${nowYear} and ${
        nowYear + MAX_AGE_OUT_YEARS_AHEAD
      }`,
    };
  }
  return { ok: true, yearMonth: value };
}

export type SetChildStatusDecision =
  | ChildStatusRejection
  // Required, not optional (owner ruling 2026-08-28): the attestation is the only
  // possible age-out source for a mid-membership child — the validator enforces it.
  | {
      kind: "set";
      expectedAgeOutYearMonth: number;
      consentScopes: ConsentScopeId[];
      consentTextVersion: string;
    }
  | { kind: "clear"; correctionReason: string };

/**
 * FR-2 gate for `setFamilyMemberChildStatus`: manager-only, no self-targets, no creator
 * targets; set-true is a consent capture and requires both acknowledgments (FR-31);
 * clear requires an enumerated correction reason (withdrawal is never expressed here).
 */
export function validateSetChildStatusInput(input: {
  actorRole: string | undefined;
  actorUserId: string;
  targetUserId: string;
  targetRole: string | undefined;
  isChild: unknown;
  correctionReason: unknown;
  consentAcknowledged: unknown;
  guardianAffirmed: unknown;
  expectedAgeOutYearMonth: unknown;
  /** F-21: required on isChild:true, ignored otherwise. */
  consentScopes?: unknown;
  consentTextVersion?: unknown;
  nowYear: number;
}): SetChildStatusDecision {
  if (!input.actorRole || !CHILD_STATUS_MANAGER_ROLES.includes(input.actorRole)) {
    return reject("permission-denied", "Only Captains can manage child status");
  }
  if (input.actorUserId === input.targetUserId) {
    return reject("failed-precondition", "You cannot change your own child status");
  }
  if (input.targetRole === "creator") {
    return reject(
      "failed-precondition",
      "The family creator cannot be marked as a child"
    );
  }
  if (typeof input.isChild !== "boolean") {
    return reject("invalid-argument", "isChild must be true or false");
  }

  if (input.isChild) {
    if (input.consentAcknowledged !== true || input.guardianAffirmed !== true) {
      return reject(
        "failed-precondition",
        "Marking a member as a child requires consentAcknowledged and guardianAffirmed"
      );
    }
    const capture = checkConsentCapture(input);
    if (!capture.ok) {
      return capture.rejection;
    }
    const yearMonth = validateExpectedAgeOutYearMonth(
      input.expectedAgeOutYearMonth,
      input.nowYear
    );
    if (!yearMonth.ok) {
      return reject("invalid-argument", yearMonth.message);
    }
    // Owner ruling 2026-08-28 (manager_set → email_plus): a mid-membership child never
    // passed the age gate, so the guardian's turns-13 attestation is the ONLY possible
    // age-out source — without it the consent record could never satisfy FR-110(b) and
    // the AGEOUT machinery could never release them. Required here; the join-approve
    // path keeps it optional (there the gate-derived marker exists).
    if (yearMonth.yearMonth === undefined) {
      return reject(
        "invalid-argument",
        "Marking an existing member as a child requires the month and year they turn 13"
      );
    }
    return {
      kind: "set",
      expectedAgeOutYearMonth: yearMonth.yearMonth,
      consentScopes: capture.consentScopes,
      consentTextVersion: capture.consentTextVersion,
    };
  }

  if (
    typeof input.correctionReason !== "string" ||
    !CHILD_STATUS_CORRECTION_REASONS.includes(input.correctionReason)
  ) {
    return reject(
      "invalid-argument",
      `Clearing child status requires correctionReason in [${CHILD_STATUS_CORRECTION_REASONS.join(
        ", "
      )}]`
    );
  }
  return { kind: "clear", correctionReason: input.correctionReason };
}

export type ApprovalChildDecision =
  | ChildStatusRejection
  | { kind: "none" }
  | {
      kind: "grant";
      expectedAgeOutYearMonth: number | undefined;
      consentScopes: ConsentScopeId[];
      consentTextVersion: string;
    }
  | { kind: "clear_new_guardian"; correctionReason: string };

/**
 * FR-1 / FR-25 gate for `approveFamilyJoinRequest_CaptainStep`:
 *  - sticky targets (flag already true) demand an EXPLICIT `isChild` — absent ⇒ rejected,
 *    so a flag is never silently laundered through re-admission;
 *  - `isChild: true` is a consent capture ⇒ both acknowledgments required (FR-31);
 *  - `isChild: false` on a sticky target is the new-guardian correction.
 *
 * FR-66(b): that last branch used to be ATTESTATION-FREE — a bare `isChild: false` cleared a
 * sticky flag with no reason and no acknowledgment, which is strictly weaker than the
 * in-family clear (`validateSetChildStatusInput`) that has always demanded an enumerated
 * `correctionReason`. It was the middle link of the self-made-captain laundering chain: mint
 * a throwaway adult account, found a family, arrive from the real flagged account, approve
 * yourself as "not a child". It now requires an enumerated reason AND both acknowledgments,
 * so a clear carries at least as much evidence as a grant does. The caller pairs this with
 * `assertGuardianClearSeasoning` (`familyJoinRequestIntegrity.ts`), which additionally
 * refuses brand-new single-adult families — evidence alone cannot fix a fabricated guardian.
 */
export function evaluateApprovalChildDeclaration(input: {
  payloadIsChild: unknown;
  consentAcknowledged: unknown;
  guardianAffirmed: unknown;
  correctionReason: unknown;
  expectedAgeOutYearMonth: unknown;
  /** F-21: required on isChild:true, ignored otherwise. */
  consentScopes?: unknown;
  consentTextVersion?: unknown;
  targetIsChildAccount: boolean;
  nowYear: number;
}): ApprovalChildDecision {
  const { payloadIsChild } = input;

  if (payloadIsChild === undefined || payloadIsChild === null) {
    if (input.targetIsChildAccount) {
      return reject(
        "failed-precondition",
        "This member is marked as a child; approval must explicitly declare isChild"
      );
    }
    return { kind: "none" };
  }

  if (typeof payloadIsChild !== "boolean") {
    return reject("invalid-argument", "isChild must be true or false");
  }

  if (payloadIsChild) {
    if (input.consentAcknowledged !== true || input.guardianAffirmed !== true) {
      return reject(
        "failed-precondition",
        "Approving a child requires consentAcknowledged and guardianAffirmed"
      );
    }
    const capture = checkConsentCapture(input);
    if (!capture.ok) {
      return capture.rejection;
    }
    const yearMonth = validateExpectedAgeOutYearMonth(
      input.expectedAgeOutYearMonth,
      input.nowYear
    );
    if (!yearMonth.ok) {
      return reject("invalid-argument", yearMonth.message);
    }
    return {
      kind: "grant",
      expectedAgeOutYearMonth: yearMonth.yearMonth,
      consentScopes: capture.consentScopes,
      consentTextVersion: capture.consentTextVersion,
    };
  }

  if (!input.targetIsChildAccount) {
    return { kind: "none" };
  }

  // FR-66(b): the new-guardian clear is a consent-affecting decision, so it carries the same
  // evidence a capture does. Acknowledgments first, mirroring the `isChild: true` branch
  // above, so the two paths reject in the same order for the same shape of missing input.
  if (input.consentAcknowledged !== true || input.guardianAffirmed !== true) {
    return reject(
      "failed-precondition",
      "Clearing a child flag on approval requires consentAcknowledged and guardianAffirmed"
    );
  }
  if (
    typeof input.correctionReason !== "string" ||
    !CHILD_STATUS_CORRECTION_REASONS.includes(input.correctionReason)
  ) {
    return reject(
      "invalid-argument",
      `Clearing child status requires correctionReason in [${CHILD_STATUS_CORRECTION_REASONS.join(
        ", "
      )}]`
    );
  }
  return { kind: "clear_new_guardian", correctionReason: input.correctionReason };
}

// ---------------------------------------------------------------------------
// linkedPlatforms minimization (FR-35b, part of the FR-4 batch)
// ---------------------------------------------------------------------------

const PUBLIC_SAFE_LINKED_PLATFORM_KEYS = ["platform", "platformUserId", "linkedAt"];

export interface SanitizedLinkedPlatforms {
  changed: boolean;
  sanitized: Array<Record<string, unknown>>;
}

/**
 * Strips contact subfields (email / phoneNumber / displayName / anything else) from a
 * child's `linkedPlatforms` entries, keeping only the identity keys the peer-readable
 * rules sanitizer allows. Returns `changed: false` when there is nothing to rewrite,
 * so the FR-4 batch stays idempotent and minimal.
 */
export function sanitizedChildLinkedPlatforms(value: unknown): SanitizedLinkedPlatforms | null {
  if (!Array.isArray(value)) {
    return null;
  }
  let changed = false;
  const sanitized: Array<Record<string, unknown>> = [];
  for (const entry of value) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      changed = true; // malformed entry dropped
      continue;
    }
    const record = entry as Record<string, unknown>;
    const kept: Record<string, unknown> = {};
    for (const key of PUBLIC_SAFE_LINKED_PLATFORM_KEYS) {
      if (key in record) {
        kept[key] = record[key];
      }
    }
    if (Object.keys(record).some((key) => !PUBLIC_SAFE_LINKED_PLATFORM_KEYS.includes(key))) {
      changed = true;
    }
    sanitized.push(kept);
  }
  return { changed, sanitized };
}

// ---------------------------------------------------------------------------
// Consent-record metadata (§11.1) — uid-only, NO PII EVER
// ---------------------------------------------------------------------------

/**
 * Keys that must never appear in consent metadata. Consent rows are retained forever
 * (G-7) and survive account deletion; with FR-35 landed, a uid-only row genuinely
 * de-identifies once `users/{uid}` is gone. A name / email / birthdate here would make
 * the record permanent PII (§16).
 */
export const FORBIDDEN_CONSENT_METADATA_KEYS: readonly string[] = [
  "name",
  "firstName",
  "lastName",
  "displayName",
  "userName",
  "userNameLower",
  "familyName",
  "email",
  "emailLower",
  "toEmail",
  "fromEmail",
  "contactEmail",
  "phone",
  "phoneNumber",
  "phoneE164",
  "birthdate",
  "birthDate",
  "dateOfBirth",
  "age",
];

/**
 * Returns every PII violation in a metadata object: a forbidden key, or any string
 * value that looks like an email address. Empty array ⇒ safe to persist.
 */
export function consentMetadataPiiViolations(
  metadata: Record<string, unknown>
): string[] {
  const violations: string[] = [];
  for (const [key, value] of Object.entries(metadata)) {
    if (FORBIDDEN_CONSENT_METADATA_KEYS.includes(key)) {
      violations.push(`forbidden key: ${key}`);
    }
    if (typeof value === "string" && value.includes("@")) {
      violations.push(`email-like value under key: ${key}`);
    }
  }
  return violations;
}

function pruneUndefined(record: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(record)) {
    if (value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}

export interface ConsentGrantedMetadataInput {
  familyId: string;
  childUserId: string;
  actorRole: string;
  method: string;
  expectedAgeOutYearMonth?: number;
  removedFriendEdgeCount?: number;
  /** FR-59.2/FR-108: the assurance level of the method that produced this capture. */
  assuranceLevel?: number;
  /** AGEOUT FR-110(b): the FR-64 transactions refuse to commit without it. */
  ageOutYearMonth: number;
  /**
   * F-21 (FR-65 / FR-103) evidence, all copied from the consent request the FR-64
   * transaction re-read (`validateStoredConsentEvidence`), never from current constants.
   */
  consentScopes: ConsentScopeVector;
  consentTextVersion: string;
  noticeTextVersion: string;
  policyVersions: Readonly<Record<string, string>>;
  consentRequestId: string;
}

export interface StoredConsentEvidence {
  consentScopes: ConsentScopeVector;
  consentTextVersion: string;
  noticeTextVersion: string;
  policyVersions: Record<string, string>;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

/**
 * F-21: re-checks the evidence a consent request stored at creation before an FR-64
 * transaction records it. The vector must pass `validateStoredScopeVector` (so a frozen
 * scope granted, a missing core or a practice-version drift all fail), both text
 * versions must be non-empty strings and policyVersions a non-empty map of strings.
 * The text versions are NOT compared with today's constants: the record states what the
 * captain was shown when the request was made. Pure; `null` means refuse.
 */
export function validateStoredConsentEvidence(
  requestData: Record<string, unknown> | undefined | null
): StoredConsentEvidence | null {
  if (!requestData) return null;
  const vector = validateStoredScopeVector(requestData.scopeVector);
  if (!vector.ok) return null;
  const { consentTextVersion, noticeTextVersion, policyVersions } = requestData;
  if (!isNonEmptyString(consentTextVersion) || !isNonEmptyString(noticeTextVersion)) {
    return null;
  }
  if (
    typeof policyVersions !== "object" ||
    policyVersions === null ||
    Array.isArray(policyVersions)
  ) {
    return null;
  }
  const policyEntries = Object.entries(policyVersions as Record<string, unknown>);
  if (policyEntries.length === 0 || !policyEntries.every(([, value]) => isNonEmptyString(value))) {
    return null;
  }
  return {
    consentScopes: vector.vector,
    consentTextVersion,
    noticeTextVersion,
    policyVersions: Object.fromEntries(policyEntries) as Record<string, string>,
  };
}

/** GRANTED — a verifiable-parental-consent capture (FR-1 / FR-2 set-true / FR-25). */
export function buildConsentGrantedMetadata(
  input: ConsentGrantedMetadataInput
): Record<string, unknown> {
  return pruneUndefined({
    familyId: input.familyId,
    childUserId: input.childUserId,
    actorRole: input.actorRole,
    consentScopes: input.consentScopes,
    policyVersions: { ...input.policyVersions },
    consentTextVersion: input.consentTextVersion,
    noticeTextVersion: input.noticeTextVersion,
    consentRequestId: input.consentRequestId,
    affirmationVersion: AFFIRMATION_VERSION,
    guardianAffirmed: true,
    method: input.method,
    expectedAgeOutYearMonth: input.expectedAgeOutYearMonth,
    removedFriendEdgeCount: input.removedFriendEdgeCount,
    assuranceLevel: input.assuranceLevel,
    ageOutYearMonth: input.ageOutYearMonth,
  });
}

export interface ConsentCorrectedMetadataInput {
  familyId: string;
  childUserId: string;
  actorRole: string;
  method: string;
  reason: string;
}

/** CORRECTED — the person is not / no longer under 13; protections lift (FR-5 / FR-25). */
export function buildConsentCorrectedMetadata(
  input: ConsentCorrectedMetadataInput
): Record<string, unknown> {
  return {
    familyId: input.familyId,
    childUserId: input.childUserId,
    actorRole: input.actorRole,
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
    method: input.method,
    reason: input.reason,
  };
}

export interface ConsentRevokedMetadataInput {
  familyId: string;
  childUserId: string;
  actorRole: string;
  method: string;
  reason: ChildConsentRevocationReason;
}

/** REVOKED — consent ended while still a child; flag stays true, collection stops (FR-6). */
export function buildConsentRevokedMetadata(
  input: ConsentRevokedMetadataInput
): Record<string, unknown> {
  return {
    familyId: input.familyId,
    childUserId: input.childUserId,
    actorRole: input.actorRole,
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
    method: input.method,
    reason: input.reason,
  };
}

/** DECLARED — self-declaration at the neutral age screen (FR-27); protective only. */
export function buildChildRegistrationDeclaredMetadata(input: {
  childUserId: string;
  /** AGEOUT FR-110(c): the F-14b marker rides the declaration row when the client has it. */
  ageOutYearMonth?: number;
}): Record<string, unknown> {
  const metadata: Record<string, unknown> = {
    childUserId: input.childUserId,
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
    method: "self_declared",
  };
  if (typeof input.ageOutYearMonth === "number") {
    metadata.ageOutYearMonth = input.ageOutYearMonth;
  }
  return metadata;
}
