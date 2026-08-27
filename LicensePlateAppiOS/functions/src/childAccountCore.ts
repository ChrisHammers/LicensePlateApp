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
 * What parental consent covers (§11.1). Location and ads are deliberately absent:
 * all location flags are forced off for child sessions (FR-33) and child sessions see
 * no ads at MVP (FR-19/D-6). Widening this list requires legal review (OQ-2).
 */
export const CHILD_CONSENT_SCOPE: readonly string[] = [
  "gameplay",
  "search_excluded",
  "analytics_limited",
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
export const CONSENT_TEXT_VERSION = "1.0.0-2026-08-10";
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
  // 2026-08-11: data-collection paragraph rewritten — real names are no longer
  // collected anywhere in the app (F-6 rework, owner decision).
  privacyPolicy: "2026-08-11.no-real-names",
};

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
}

function reject(
  code: ChildStatusRejection["code"],
  message: string
): ChildStatusRejection {
  return { kind: "reject", code, message };
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
  | { kind: "set"; expectedAgeOutYearMonth: number | undefined }
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
    const yearMonth = validateExpectedAgeOutYearMonth(
      input.expectedAgeOutYearMonth,
      input.nowYear
    );
    if (!yearMonth.ok) {
      return reject("invalid-argument", yearMonth.message);
    }
    return { kind: "set", expectedAgeOutYearMonth: yearMonth.yearMonth };
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
  | { kind: "grant"; expectedAgeOutYearMonth: number | undefined }
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
    const yearMonth = validateExpectedAgeOutYearMonth(
      input.expectedAgeOutYearMonth,
      input.nowYear
    );
    if (!yearMonth.ok) {
      return reject("invalid-argument", yearMonth.message);
    }
    return { kind: "grant", expectedAgeOutYearMonth: yearMonth.yearMonth };
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
  /**
   * AGEOUT FR-110(b): required on email_plus captures (the FR-64 transaction refuses to
   * commit without it). Optional here only so the legacy `family_admission` writer keeps
   * compiling until it is deleted with the F-17 cutover.
   */
  ageOutYearMonth?: number;
}

/** GRANTED — a verifiable-parental-consent capture (FR-1 / FR-2 set-true / FR-25). */
export function buildConsentGrantedMetadata(
  input: ConsentGrantedMetadataInput
): Record<string, unknown> {
  return pruneUndefined({
    familyId: input.familyId,
    childUserId: input.childUserId,
    actorRole: input.actorRole,
    consentScope: [...CHILD_CONSENT_SCOPE],
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
    consentTextVersion: CONSENT_TEXT_VERSION,
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
