//
//  ConsentScopeCatalog.swift
//  LicensePlateApp
//
//  COPPA v3 FR-65 / v4 FR-103 (F-21 slice 1): the per-scope consent catalog, client side.
//
//  The SERVER is the authority (`CONSENT_SCOPE_*` in `childAccountCore.ts`). This file
//  mirrors that catalog as compile-time constants — lattice precedent: no runtime JSON
//  load. The test-only fixture `LicensePlateAppTests/ConsentScopeCatalog.v1.json` is
//  byte-identical to `functions/src/consentScopeCatalog.v1.json`, and
//  `ConsentScopeCatalogParityTests` pins these constants to it, so drift on either side
//  fails a suite.
//
//  `ConsentScopeCardPolicy` is the pure model of which scope cards an approval or manage
//  surface shows and which localization KEYS each card uses. It resolves no strings:
//  the keys are plain constants, and `ConsentScopeCardList` (slice 2) renders them.
//

import Foundation

// MARK: - Scope ids

/// How a scope may appear in a consent. `optional` exists in the type only; no scope uses
/// it at launch. Raw values match `ConsentScopeAvailability` in `childAccountCore.ts`.
nonisolated enum ConsentScopeAvailability: String, Sendable {
    case required
    case optional
    case frozen
}

/// The closed list of consent scopes, in display order. Raw values match
/// `CONSENT_SCOPE_IDS` in `childAccountCore.ts`.
nonisolated enum ConsentScopeId: String, CaseIterable, Identifiable, Sendable {
    case core
    case analyticsInternal = "analytics_internal"
    case adsChildDirected = "ads_child_directed"
    case locationFamilyShared = "location_family_shared"
    case crossFamilyVisibility = "cross_family_visibility"

    var id: String { rawValue }

    var availability: ConsentScopeAvailability {
        switch self {
        case .core: return .required
        case .analyticsInternal, .adsChildDirected, .locationFamilyShared, .crossFamilyVisibility:
            return .frozen
        }
    }

    var policyAnchor: ConsentScopePolicyAnchor {
        switch self {
        case .core: return .core
        case .analyticsInternal: return .analytics
        case .adsChildDirected: return .ads
        case .locationFamilyShared: return .location
        case .crossFamilyVisibility: return .crossFamily
        }
    }

    // Copy-deck keys. Plain constants; the views resolve them.

    var nameKey: String {
        switch self {
        case .core: return "family.consent_scope.core.name"
        case .analyticsInternal: return "family.consent_scope.analytics_internal.name"
        case .adsChildDirected: return "family.consent_scope.ads_child_directed.name"
        case .locationFamilyShared: return "family.consent_scope.location_family_shared.name"
        case .crossFamilyVisibility: return "family.consent_scope.cross_family_visibility.name"
        }
    }

    var meaningKey: String {
        switch self {
        case .core: return "family.consent_scope.core.meaning"
        case .analyticsInternal: return "family.consent_scope.analytics_internal.meaning"
        case .adsChildDirected: return "family.consent_scope.ads_child_directed.meaning"
        case .locationFamilyShared: return "family.consent_scope.location_family_shared.meaning"
        case .crossFamilyVisibility: return "family.consent_scope.cross_family_visibility.meaning"
        }
    }

    var collectedKey: String {
        switch self {
        case .core: return "family.consent_scope.core.collected"
        case .analyticsInternal: return "family.consent_scope.analytics_internal.collected"
        case .adsChildDirected: return "family.consent_scope.ads_child_directed.collected"
        case .locationFamilyShared: return "family.consent_scope.location_family_shared.collected"
        case .crossFamilyVisibility: return "family.consent_scope.cross_family_visibility.collected"
        }
    }

    /// The analytics, ads and location cards share one "nobody" line.
    var whoSeesKey: String {
        switch self {
        case .core: return "family.consent_scope.core.who_sees"
        case .analyticsInternal, .adsChildDirected, .locationFamilyShared:
            return "family.consent_scope.who_sees_nobody"
        case .crossFamilyVisibility: return "family.consent_scope.cross_family_visibility.who_sees"
        }
    }
}

// MARK: - Catalog

nonisolated enum ConsentScopeCatalog {
    /// Equals `CONSENT_TEXT_VERSION` in `childAccountCore.ts` (pinned through the fixture
    /// by both parity suites). Bumped only together with that constant and the fixture.
    static let consentTextVersion = "2026-11-17.consent-scopes"

    /// The only valid selection at launch: core is required, every other scope is frozen.
    static let launchSelection: [ConsentScopeId] = [.core]
}

// MARK: - Policy anchors (FR-103(c))

/// The in-app Privacy Policy anchors for the five scopes, as `rtr-legal://<anchor>` URLs.
/// A separate type from `ChildConsentPolicyLink`, so that type's `allCases` keeps meaning
/// exactly the terms + privacy pair.
nonisolated enum ConsentScopePolicyAnchor: String, CaseIterable, Sendable {
    case core = "privacy-children-core"
    case analytics = "privacy-children-analytics"
    case ads = "privacy-children-ads"
    case location = "privacy-children-location"
    case crossFamily = "privacy-children-cross-family"

    /// The same scheme as `ChildConsentPolicyLink.scheme` (pinned by
    /// ConsentScopeCardPolicyTests). Restated here because that type is main-actor
    /// isolated and this one is not.
    static let scheme = "rtr-legal"

    var url: URL? {
        URL(string: "\(Self.scheme)://\(rawValue)")
    }

    /// Returns nil for anything that is not one of these anchors.
    static func from(url: URL) -> ConsentScopePolicyAnchor? {
        guard url.scheme == scheme else { return nil }
        let key = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        return ConsentScopePolicyAnchor(rawValue: key)
    }
}

// MARK: - Card policy

/// Server `scopeStatus` for a child (getParentalConsentStatus). Raw values match the server.
nonisolated enum ConsentScopeStatus: String, Sendable {
    case live
    case pending
    case ended
    case noRecord = "none"
}

/// One scope's recorded state in the server vector. Raw values match `ConsentScopeState`
/// in `childAccountCore.ts`.
nonisolated enum ConsentScopeGrantState: String, Sendable {
    case granted
    case declined
    case unavailable
}

/// What a card shows as its state row.
nonisolated enum ConsentScopeCardState: Sendable {
    /// Core at approval: lock, no switch.
    case required
    /// A granted scope on the manage screen.
    case agreed
    /// A frozen scope: clock and a disabled, off switch.
    case unavailable

    var textKey: String {
        switch self {
        case .required: return "family.consent_scope.state.required"
        case .agreed: return "family.consent_scope.state.agreed"
        case .unavailable: return "family.consent_scope.state.unavailable"
        }
    }

    var accessibilityValueKey: String {
        switch self {
        case .required: return "family.consent_scope.a11y.value.required"
        case .agreed: return "family.consent_scope.a11y.value.agreed"
        case .unavailable: return "family.consent_scope.a11y.value.unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .required: return "lock.fill"
        case .agreed: return "checkmark.seal"
        case .unavailable: return "clock"
        }
    }
}

nonisolated struct ConsentScopeCardModel: Identifiable, Equatable, Sendable {
    let scope: ConsentScopeId
    let state: ConsentScopeCardState
    let nameKey: String
    let meaningKey: String
    let collectedKey: String
    let whoSeesKey: String
    /// Core only.
    let notificationsKey: String?
    /// Core at approval only; the line differs between the join and Mark-as-a-child paths.
    let requiredReasonKey: String?
    /// Frozen cards only.
    let frozenReasonKey: String?
    let accessibilityHintKey: String?
    let anchor: ConsentScopePolicyAnchor

    var id: String { scope.rawValue }
    var stateKey: String { state.textKey }
    var accessibilityValueKey: String { state.accessibilityValueKey }
    var showsLock: Bool { state == .required }
    var showsDisabledSwitch: Bool { state == .unavailable }
}

nonisolated enum ConsentScopeCardPolicy {

    enum ApprovalKind: Sendable {
        /// A captain approving a join request.
        case join
        /// A manager marking an existing member as a child.
        case memberFlag
    }

    enum Mode: Sendable {
        case approval(kind: ApprovalKind)
        /// `currentScopes` is keyed by raw scope id, as the server returns it.
        case manage(status: ConsentScopeStatus, currentScopes: [String: ConsentScopeGrantState])
    }

    // Keys shared by every card or by the surrounding section.
    static let sectionTitleKey = "family.consent_scope.section_title"
    static let sectionIntroKey = "family.consent_scope.section_intro"
    static let fullPolicyLinksKey = "family.consent_scope.full_policy_links"
    static let policyLinkKey = "family.consent_scope.policy_link"
    static let accessibilityPolicyActionKey = "family.consent_scope.a11y.action.policy"
    static let manageTitleKey = "family.consent_scope.manage_title"
    static let manageFooterKey = "family.consent_scope.manage_footer"
    /// Shown when the status callable fails; not a server status.
    static let manageUnavailableKey = "family.consent_scope.manage_unavailable"

    /// Approval: every catalog scope, in order. Manage: only when `live`, one card per
    /// catalog scope present in `currentScopes` (unknown ids are dropped); any other
    /// status gives no cards and a status line (`statusLineKey`).
    static func cards(mode: Mode) -> [ConsentScopeCardModel] {
        switch mode {
        case .approval(let kind):
            return ConsentScopeId.allCases.map { scope in
                card(
                    scope,
                    state: scope.availability == .required ? .required : .unavailable,
                    requiredReasonKey: scope.availability == .required ? requiredReasonKey(kind) : nil
                )
            }
        case .manage(let status, let currentScopes):
            guard status == .live else { return [] }
            return ConsentScopeId.allCases.compactMap { scope in
                switch currentScopes[scope.rawValue] {
                case .granted: return card(scope, state: .agreed, requiredReasonKey: nil)
                case .unavailable: return card(scope, state: .unavailable, requiredReasonKey: nil)
                // No scope is optional at launch, so no copy exists for a declined one.
                case .declined, nil: return nil
                }
            }
        }
    }

    /// The manage screen's line for a status: the footer when live, otherwise the line
    /// that replaces the cards.
    static func statusLineKey(for status: ConsentScopeStatus) -> String {
        switch status {
        case .live: return manageFooterKey
        case .pending: return "family.consent_scope.manage_pending"
        case .ended: return "family.consent_scope.manage_ended"
        case .noRecord: return "family.consent_scope.manage_none"
        }
    }

    static func requiredReasonKey(_ kind: ApprovalKind) -> String {
        switch kind {
        case .join: return "family.consent_scope.core.required_reason.join"
        case .memberFlag: return "family.consent_scope.core.required_reason.member_flag"
        }
    }

    private static func card(
        _ scope: ConsentScopeId,
        state: ConsentScopeCardState,
        requiredReasonKey: String?
    ) -> ConsentScopeCardModel {
        let hintKey: String?
        switch scope.availability {
        case .required: hintKey = "family.consent_scope.a11y.hint.core"
        case .frozen: hintKey = "family.consent_scope.a11y.hint.unavailable"
        case .optional: hintKey = nil
        }
        return ConsentScopeCardModel(
            scope: scope,
            state: state,
            nameKey: scope.nameKey,
            meaningKey: scope.meaningKey,
            collectedKey: scope.collectedKey,
            whoSeesKey: scope.whoSeesKey,
            notificationsKey: scope == .core ? "family.consent_scope.core.notifications" : nil,
            requiredReasonKey: requiredReasonKey,
            frozenReasonKey: scope.availability == .frozen ? "family.consent_scope.frozen_reason" : nil,
            accessibilityHintKey: hintKey,
            anchor: scope.policyAnchor
        )
    }
}
