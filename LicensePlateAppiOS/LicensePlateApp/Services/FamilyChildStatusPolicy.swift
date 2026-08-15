//
//  FamilyChildStatusPolicy.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-1/2/5/25/29/30/31): pure client-side policy for the family
//  child-management surfaces. Everything here is a value type or a static function so
//  the consent rules, callable payload shapes, and rejection mapping are unit-testable
//  without Firebase.
//
//  The SERVER is the authority (`childAccountCore.ts` / `familyChildStatusFlows.ts`).
//  This file exists so the UI mirrors those rules and a manager never walks into a raw
//  server rejection: every state the server refuses is a state the UI blocks first.
//

import Foundation
import FirebaseFunctions

// MARK: - Correction reasons (FR-2/FR-5)

/// The ONLY reasons a manager may clear the flag. Raw values match
/// `CHILD_STATUS_CORRECTION_REASONS` in `childAccountCore.ts`; a mismatch would be
/// rejected server-side as `invalid-argument`.
enum ChildStatusCorrectionReason: String, CaseIterable, Identifiable, Sendable {
    case flagSetInError = "flag_set_in_error"
    case childTurned13 = "child_turned_13"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .flagSetInError: return "family.child.correction_reason.flag_set_in_error".localized
        case .childTurned13: return "family.child.correction_reason.child_turned_13".localized
        }
    }
}

// MARK: - Consent capture (FR-31)

/// Draft state of the consent block shown wherever a manager marks someone a child
/// (approval — FR-1, and post-hoc set — FR-2). Both acknowledgments are required before
/// the callable may be sent; the server independently re-checks them.
struct ChildConsentDraft: Equatable, Sendable {
    var consentAcknowledged: Bool = false
    var guardianAffirmed: Bool = false
    /// Optional, year-only parent attestation (FR-26). `nil` = not supplied.
    var expectedAgeOutYear: Int?

    /// FR-31: consent is captured only when BOTH boxes are checked.
    var isComplete: Bool {
        consentAcknowledged && guardianAffirmed
    }

    mutating func reset() {
        self = ChildConsentDraft()
    }
}

/// Sanity window for the optional age-out year, mirroring `validateExpectedAgeOutYear`
/// (`childAccountCore.ts`): a child is under 13 today, so they turn 13 within 13 years.
enum ExpectedAgeOutYearOptions {
    static let maxYearsAhead = 13

    static func options(currentYear: Int) -> [Int] {
        Array(currentYear...(currentYear + maxYearsAhead))
    }

    static func isValid(_ year: Int?, currentYear: Int) -> Bool {
        guard let year else { return true }
        return year >= currentYear && year <= currentYear + maxYearsAhead
    }
}

// MARK: - Approval declaration (FR-1 / FR-25)

/// What the client knows about a pending requester's existing child flag.
///
/// `unknown` is a real, expected state, not an error: FR-12 denies peer reads of a
/// child's `users/{uid}` doc to anyone outside the child's family, and a pending
/// requester is by definition not a member yet. An unreadable target is therefore
/// treated exactly like a known-child target — the manager must answer explicitly.
enum ChildApprovalTargetState: Equatable, Sendable {
    /// A fresh read confirmed the target is not flagged.
    case notChild
    /// A fresh read (or a server rejection) showed the target is already flagged.
    case alreadyChild
    /// The target's flag could not be resolved this session.
    case unknown

    /// FR-25: sticky targets (and unresolvable ones) demand an explicit yes/no. The
    /// server rejects a silent approval; the UI blocks it first so no raw error shows.
    var requiresExplicitDeclaration: Bool {
        self != .notChild
    }
}

/// Draft state of the correction block shown when a manager clears an EXISTING child flag
/// during approval (FR-25 new-guardian correction).
///
/// COPPA FR-66(b): this branch used to be attestation-free on both sides — the UI asked for
/// nothing and the server required nothing, so a bare "no, not a child" cleared a sticky
/// flag. That was the middle link of a laundering chain (found a family from a throwaway
/// account, arrive from the real flagged account, clear your own flag). The server now
/// demands an enumerated reason AND both acknowledgments, exactly like a capture does, so
/// the UI collects them first — a manager must never walk into a raw server rejection.
struct ChildCorrectionDraft: Equatable, Sendable {
    var reason: ChildStatusCorrectionReason?
    /// "This member is 13 or older, or was marked as a child by mistake."
    var statusAcknowledged: Bool = false
    /// Reuses the SAME guardian sentence as a consent capture (`AFFIRMATION_VERSION`).
    var guardianAffirmed: Bool = false

    var isComplete: Bool {
        reason != nil && statusAcknowledged && guardianAffirmed
    }

    mutating func reset() {
        self = ChildCorrectionDraft()
    }
}

/// Per-request draft of the approval-time child declaration.
struct ChildApprovalDraft: Equatable, Sendable {
    /// `nil` = the manager has not answered. For `.notChild` targets the UI seeds
    /// `false` (the toggle is simply off); for sticky/unknown targets it stays `nil`
    /// until the manager chooses.
    var isChild: Bool?
    var consent = ChildConsentDraft()
    var correction = ChildCorrectionDraft()

    static func initial(for state: ChildApprovalTargetState) -> ChildApprovalDraft {
        ChildApprovalDraft(isChild: state.requiresExplicitDeclaration ? nil : false)
    }
}

enum ChildApprovalPolicy {
    /// Whether Approve may be enabled. Mirrors `evaluateApprovalChildDeclaration`:
    /// - explicit declaration required for sticky/unknown targets;
    /// - `isChild == true` is a consent capture and needs both acknowledgments;
    /// - `isChild == false` on an ALREADY-FLAGGED target is the FR-66(b) correction and
    ///   needs a reason plus both acknowledgments.
    ///
    /// `.unknown` targets are deliberately NOT gated on the correction block. The flag could
    /// not be read (FR-12 denies peer reads of a non-family child's doc), so demanding a
    /// correction from every unreadable target would put that ceremony in front of ordinary
    /// adult approvals. If the target does turn out to be flagged, the server rejects and
    /// `FamilyPendingApprovalsViewModel` re-resolves the row to `.alreadyChild`, which then
    /// shows the block on the second pass.
    static func canApprove(state: ChildApprovalTargetState, draft: ChildApprovalDraft) -> Bool {
        guard let isChild = draft.isChild else {
            return !state.requiresExplicitDeclaration
        }
        if isChild {
            return draft.consent.isComplete
        }
        return showsCorrectionBlock(state: state, draft: draft) ? draft.correction.isComplete : true
    }

    /// Whether the consent block is shown (the manager said "yes, a child").
    static func showsConsentBlock(draft: ChildApprovalDraft) -> Bool {
        draft.isChild == true
    }

    /// Whether the FR-66(b) correction block is shown — clearing a flag we KNOW is set.
    static func showsCorrectionBlock(
        state: ChildApprovalTargetState,
        draft: ChildApprovalDraft
    ) -> Bool {
        state == .alreadyChild && draft.isChild == false
    }
}

/// Fixed slugs for `.familyChildStatusSet(source:)` (SRS §12). Never a uid, name, or age.
enum FamilyChildStatusAnalyticsSource: String, Sendable {
    case approval
    case familySettings = "family_settings"
}

// MARK: - Callable payloads

/// Pure builders for the four child-status callables. Kept separate from
/// `FamilyRepository` so the exact field names — which must match the server's
/// `data?.…` reads — are pinned by tests. `clientMetadata` is NEVER nested here: the
/// repository appends it as a sibling via `.addingClientMetadata()`
/// (client-metadata-cloud-calls rule).
enum FamilyChildStatusPayload {

    /// `setFamilyMemberChildStatus` — set branch (FR-2 set-true / FR-4).
    static func setChild(
        familyId: String,
        memberUserId: String,
        consent: ChildConsentDraft
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "familyId": familyId,
            "memberId": memberUserId,
            "isChild": true,
            "consentAcknowledged": consent.consentAcknowledged,
            "guardianAffirmed": consent.guardianAffirmed
        ]
        if let year = consent.expectedAgeOutYear {
            payload["expectedAgeOutYear"] = year
        }
        return payload
    }

    /// `setFamilyMemberChildStatus` — clear branch (FR-5 correction only).
    static func clearChild(
        familyId: String,
        memberUserId: String,
        correctionReason: ChildStatusCorrectionReason
    ) -> [String: Any] {
        [
            "familyId": familyId,
            "memberId": memberUserId,
            "isChild": false,
            "correctionReason": correctionReason.rawValue
        ]
    }

    /// `requestChildDataDeletion` (FR-30).
    static func requestChildDataDeletion(familyId: String, childUserId: String) -> [String: Any] {
        ["familyId": familyId, "childUserId": childUserId]
    }

    /// `getParentalConsentStatus` (FR-29).
    static func parentalConsentStatus(familyId: String, childUserId: String) -> [String: Any] {
        ["familyId": familyId, "childUserId": childUserId]
    }

    /// `approveFamilyJoinRequest_CaptainStep` (FR-1/FR-25). The child fields ride the
    /// existing approval payload; an unanswered draft omits `isChild` entirely, which is
    /// legal only for targets the server sees as non-child.
    static func respondToPendingRequest(
        familyId: String,
        requestId: String,
        approve: Bool,
        declaration: ChildApprovalDraft?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "familyId": familyId,
            "requestId": requestId,
            "response": approve ? "approve" : "decline"
        ]
        guard approve, let declaration, let isChild = declaration.isChild else {
            return payload
        }
        payload["isChild"] = isChild
        guard isChild else {
            // FR-66(b): a clear now carries the same evidence a capture does. Sent only when
            // the manager actually completed the correction block — for an unflagged target
            // the server treats `isChild: false` as a plain approval and reads none of this.
            guard declaration.correction.isComplete,
                  let reason = declaration.correction.reason else { return payload }
            payload["correctionReason"] = reason.rawValue
            payload["consentAcknowledged"] = declaration.correction.statusAcknowledged
            payload["guardianAffirmed"] = declaration.correction.guardianAffirmed
            return payload
        }
        payload["consentAcknowledged"] = declaration.consent.consentAcknowledged
        payload["guardianAffirmed"] = declaration.consent.guardianAffirmed
        if let year = declaration.consent.expectedAgeOutYear {
            payload["expectedAgeOutYear"] = year
        }
        return payload
    }
}

// MARK: - Consent-copy policy links

/// The two legal documents the consent copy cites (FR-31). A parent must be able to read
/// them in place, before affirming.
///
/// The references are markdown links inside the localized copy rather than separate
/// buttons, so the RENDERED WORDING IS UNCHANGED — only the markup is new, which keeps
/// this out of `CONSENT_TEXT_VERSION` territory. Markdown links in a SwiftUI `Text` are
/// real links to VoiceOver (link trait + links rotor), not styled text.
enum ChildConsentPolicyLink: String, Identifiable, CaseIterable, Sendable {
    case termsOfService = "terms"
    case privacyPolicy = "privacy"

    var id: String { rawValue }

    /// Intercepted by the consent block's `openURL` handler and never sent to the system,
    /// so this scheme deliberately does not overlap the app's real deep-link scheme.
    static let scheme = "rtr-legal"

    var url: URL? {
        URL(string: "\(Self.scheme)://\(rawValue)")
    }

    /// Resolves a tapped link. Returns nil for anything that is not one of ours, so the
    /// handler can fall back to the system.
    static func from(url: URL) -> ChildConsentPolicyLink? {
        guard url.scheme == scheme else { return nil }
        let key = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        return ChildConsentPolicyLink(rawValue: key)
    }
}

// MARK: - Repository seam

/// The three child-status callables, as a protocol so view models depend on behavior
/// rather than on `FamilyRepository` (and tests drive them without Firebase).
/// `FamilyRepository` is the only production conformer.
@MainActor
protocol FamilyChildStatusManaging: AnyObject {
    func setChildStatus(
        familyId: String,
        memberUserId: String,
        isChild: Bool,
        consentAcknowledged: Bool,
        guardianAffirmed: Bool,
        correctionReason: ChildStatusCorrectionReason?,
        expectedAgeOutYear: Int?
    ) async throws

    func requestChildDataDeletion(familyId: String, childUserId: String) async throws

    func getParentalConsentStatus(familyId: String, childUserId: String) async throws -> ParentalConsentStatus
}

// MARK: - Server rejection mapping

/// Recognizes the FR-25 "sticky target approved without an explicit declaration"
/// rejection so the UI can convert it into the explicit-choice state instead of showing
/// a raw server message. Belt-and-braces: the client already blocks this case whenever
/// it could read the target's flag; this covers the unreadable-target race.
///
/// Text matching follows the existing `FriendsFamilyInviteAnalytics` precedent — the
/// server sends no machine-readable `details.reason` on this path.
enum FamilyChildApprovalRejection {
    static func isMissingExplicitChildDeclaration(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              FunctionsErrorCode(rawValue: nsError.code) == .failedPrecondition else {
            return false
        }
        let message = (nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? "").lowercased()
        return message.contains("explicitly declare")
    }
}

// MARK: - Membership-loss recovery

/// Every membership-scoped callable — `removeFamilyMember`, `setFamilyMemberChildStatus`,
/// `requestChildDataDeletion`, `getParentalConsentStatus` — answers `not-found`
/// ("Member not found") when the target is no longer in the family.
///
/// That is not a failure the manager can act on: it means the roster on screen is stale
/// (the member was already removed, here or on another device). Treat it as a signal to
/// reconcile locally, never as a raw alert.
enum FamilyMembershipRecoveryPolicy {
    static func isAlreadyRemoved(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else { return false }
        return FunctionsErrorCode(rawValue: nsError.code) == .notFound
    }
}

// MARK: - Consent history (FR-29)

/// Lifecycle event types returned by `getParentalConsentStatus`. Raw values match
/// `CHILD_CONSENT_EVENT_TYPES` (`childAccountCore.ts`).
enum ParentalConsentEventType: String, Sendable {
    case declared = "AUDIT_CHILD_REGISTRATION_DECLARED"
    case granted = "AUDIT_PARENTAL_CONSENT_GRANTED"
    case corrected = "AUDIT_PARENTAL_CONSENT_CORRECTED"
    case revoked = "AUDIT_PARENTAL_CONSENT_REVOKED"

    var localizedTitle: String {
        switch self {
        case .declared: return "family.child.consent_event.declared".localized
        case .granted: return "family.child.consent_event.granted".localized
        case .corrected: return "family.child.consent_event.corrected".localized
        case .revoked: return "family.child.consent_event.revoked".localized
        }
    }
}

/// One curated consent row. The callable already strips everything uid-bearing or
/// PII-bearing; this mirror keeps only what the parent-facing surface renders.
struct ParentalConsentRecord: Identifiable, Equatable, Sendable {
    let id: String
    let eventType: ParentalConsentEventType?
    let rawEventType: String
    let createdAt: Date?
    let correctionReason: String?
    let guardianAffirmed: Bool?
    let expectedAgeOutYear: Int?

    var localizedTitle: String {
        eventType?.localizedTitle ?? "family.child.consent_event.unknown".localized
    }

    /// Only the enumerated correction reasons are surfaced; unknown server slugs are
    /// dropped rather than shown untranslated.
    var localizedCorrectionReason: String? {
        switch correctionReason {
        case ChildStatusCorrectionReason.flagSetInError.rawValue:
            return ChildStatusCorrectionReason.flagSetInError.localizedTitle
        case ChildStatusCorrectionReason.childTurned13.rawValue:
            return ChildStatusCorrectionReason.childTurned13.localizedTitle
        default:
            return nil
        }
    }
}

/// Parsed `getParentalConsentStatus` response.
struct ParentalConsentStatus: Equatable, Sendable {
    var records: [ParentalConsentRecord]

    /// Tolerant parser: an unexpected shape yields an empty history rather than an
    /// error, because consent history is a SHOULD (FR-29) layered on the MUST surface.
    static func parse(_ data: Any?) -> ParentalConsentStatus {
        guard let dict = data as? [String: Any],
              let rows = dict["records"] as? [[String: Any]] else {
            return ParentalConsentStatus(records: [])
        }
        let records = rows.enumerated().compactMap { index, row -> ParentalConsentRecord? in
            guard let rawEventType = row["eventType"] as? String, !rawEventType.isEmpty else {
                return nil
            }
            let millis = (row["createdAtMillis"] as? NSNumber)?.doubleValue
            return ParentalConsentRecord(
                id: "\(index)-\(rawEventType)-\(millis.map { String($0) } ?? "nil")",
                eventType: ParentalConsentEventType(rawValue: rawEventType),
                rawEventType: rawEventType,
                createdAt: millis.map { Date(timeIntervalSince1970: $0 / 1000) },
                correctionReason: row["reason"] as? String,
                guardianAffirmed: row["guardianAffirmed"] as? Bool,
                expectedAgeOutYear: (row["expectedAgeOutYear"] as? NSNumber)?.intValue
            )
        }
        return ParentalConsentStatus(records: records)
    }
}

// MARK: - Manage-control gating (FR-2/FR-20/FR-30)

/// Mirrors the server's target rules so a disabled control is never a surprise:
/// managers only, never yourself, never the creator.
enum FamilyChildManagePolicy {
    static func canManageChildStatus(
        isCaptainOrCreator: Bool,
        currentUserId: String?,
        memberUserId: String,
        familyCreatorId: String?,
        memberRole: FamilyMember.FamilyRole
    ) -> Bool {
        guard isCaptainOrCreator else { return false }
        guard let currentUserId, !currentUserId.isEmpty else { return false }
        guard memberUserId != currentUserId else { return false }
        guard memberUserId != familyCreatorId else { return false }
        return memberRole != .creator
    }
}
