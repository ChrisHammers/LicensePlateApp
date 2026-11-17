//
//  ConsentScopeCardPolicyTests.swift
//  LicensePlateAppTests
//
//  FR-103: the scope-card model, pinned as a model snapshot (not an image). Each card
//  names localization KEYS only; nothing here resolves a string.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ConsentScopeCardPolicyTests {

    private let frozen: [ConsentScopeId] = [
        .analyticsInternal, .adsChildDirected, .locationFamilyShared, .crossFamilyVisibility
    ]

    private let launchScopes: [String: ConsentScopeGrantState] = [
        "core": .granted,
        "analytics_internal": .unavailable,
        "ads_child_directed": .unavailable,
        "location_family_shared": .unavailable,
        "cross_family_visibility": .unavailable,
    ]

    // MARK: Approval

    @Test func approvalJoinShowsFiveCardsCoreLockedFourFrozen() throws {
        let cards = ConsentScopeCardPolicy.cards(mode: .approval(kind: .join))
        #expect(cards.map(\.scope) == ConsentScopeId.allCases)

        let core = try #require(cards.first)
        #expect(core.state == .required)
        #expect(core.showsLock)
        #expect(!core.showsDisabledSwitch)
        #expect(core.stateKey == "family.consent_scope.state.required")
        #expect(core.accessibilityValueKey == "family.consent_scope.a11y.value.required")
        #expect(core.accessibilityHintKey == "family.consent_scope.a11y.hint.core")
        #expect(core.requiredReasonKey == "family.consent_scope.core.required_reason.join")
        #expect(core.notificationsKey == "family.consent_scope.core.notifications")
        #expect(core.frozenReasonKey == nil)
        #expect(core.anchor == .core)

        for card in cards.dropFirst() {
            #expect(card.state == .unavailable, "\(card.id)")
            #expect(!card.showsLock, "\(card.id)")
            #expect(card.showsDisabledSwitch, "\(card.id)")
            #expect(card.stateKey == "family.consent_scope.state.unavailable", "\(card.id)")
            #expect(card.accessibilityValueKey == "family.consent_scope.a11y.value.unavailable")
            #expect(card.accessibilityHintKey == "family.consent_scope.a11y.hint.unavailable")
            #expect(card.frozenReasonKey == "family.consent_scope.frozen_reason", "\(card.id)")
            #expect(card.requiredReasonKey == nil, "\(card.id)")
            #expect(card.notificationsKey == nil, "\(card.id)")
            #expect(card.anchor == card.scope.policyAnchor, "\(card.id)")
        }
        #expect(cards.dropFirst().map(\.scope) == frozen)
    }

    @Test func approvalMemberFlagUsesTheMemberFlagReason() throws {
        let cards = ConsentScopeCardPolicy.cards(mode: .approval(kind: .memberFlag))
        let core = try #require(cards.first)
        #expect(core.scope == .core)
        #expect(core.requiredReasonKey == "family.consent_scope.core.required_reason.member_flag")
        // Only the reason line differs between the two approval paths.
        let join = ConsentScopeCardPolicy.cards(mode: .approval(kind: .join))
        #expect(Array(cards.dropFirst()) == Array(join.dropFirst()))
    }

    /// The FR-103 scope-matrix snapshot: every content key per card, at join approval.
    @Test func scopeMatrixSnapshot() {
        let cards = ConsentScopeCardPolicy.cards(mode: .approval(kind: .join))
        let snapshot = cards.map { [$0.id, $0.nameKey, $0.meaningKey, $0.collectedKey, $0.whoSeesKey] }
        #expect(snapshot == [
            ["core",
             "family.consent_scope.core.name",
             "family.consent_scope.core.meaning",
             "family.consent_scope.core.collected",
             "family.consent_scope.core.who_sees"],
            ["analytics_internal",
             "family.consent_scope.analytics_internal.name",
             "family.consent_scope.analytics_internal.meaning",
             "family.consent_scope.analytics_internal.collected",
             "family.consent_scope.who_sees_nobody"],
            ["ads_child_directed",
             "family.consent_scope.ads_child_directed.name",
             "family.consent_scope.ads_child_directed.meaning",
             "family.consent_scope.ads_child_directed.collected",
             "family.consent_scope.who_sees_nobody"],
            ["location_family_shared",
             "family.consent_scope.location_family_shared.name",
             "family.consent_scope.location_family_shared.meaning",
             "family.consent_scope.location_family_shared.collected",
             "family.consent_scope.who_sees_nobody"],
            ["cross_family_visibility",
             "family.consent_scope.cross_family_visibility.name",
             "family.consent_scope.cross_family_visibility.meaning",
             "family.consent_scope.cross_family_visibility.collected",
             "family.consent_scope.cross_family_visibility.who_sees"],
        ])
    }

    // MARK: Manage

    @Test func manageLiveShowsCoreAgreedAndFourUnavailable() throws {
        let cards = ConsentScopeCardPolicy.cards(
            mode: .manage(status: .live, currentScopes: launchScopes)
        )
        #expect(cards.map(\.scope) == ConsentScopeId.allCases)

        let core = try #require(cards.first)
        #expect(core.state == .agreed)
        #expect(core.stateKey == "family.consent_scope.state.agreed")
        #expect(core.accessibilityValueKey == "family.consent_scope.a11y.value.agreed")
        #expect(!core.showsLock)
        #expect(!core.showsDisabledSwitch)
        // The kind-specific reason belongs to approval only.
        #expect(core.requiredReasonKey == nil)

        for card in cards.dropFirst() {
            #expect(card.state == .unavailable, "\(card.id)")
            #expect(card.showsDisabledSwitch, "\(card.id)")
            #expect(card.frozenReasonKey == "family.consent_scope.frozen_reason", "\(card.id)")
        }
        #expect(ConsentScopeCardPolicy.statusLineKey(for: .live) == "family.consent_scope.manage_footer")
    }

    @Test(arguments: [
        (ConsentScopeStatus.pending, "family.consent_scope.manage_pending"),
        (ConsentScopeStatus.ended, "family.consent_scope.manage_ended"),
        (ConsentScopeStatus.noRecord, "family.consent_scope.manage_none"),
    ])
    func manageNonLiveShowsNoCardsAndItsStatusLine(status: ConsentScopeStatus, key: String) {
        // Even a stale vector is never shown outside the live state.
        #expect(ConsentScopeCardPolicy.cards(mode: .manage(status: status, currentScopes: launchScopes)).isEmpty)
        #expect(ConsentScopeCardPolicy.statusLineKey(for: status) == key)
    }

    @Test func manageStatusRawValuesMatchTheServer() {
        #expect(ConsentScopeStatus(rawValue: "live") == .live)
        #expect(ConsentScopeStatus(rawValue: "pending") == .pending)
        #expect(ConsentScopeStatus(rawValue: "ended") == .ended)
        #expect(ConsentScopeStatus(rawValue: "none") == .noRecord)
    }

    @Test func manageDropsUnknownIds() {
        var scopes = launchScopes
        scopes["gameplay"] = .granted
        scopes["analytics_limited"] = .granted
        let cards = ConsentScopeCardPolicy.cards(mode: .manage(status: .live, currentScopes: scopes))
        #expect(cards.map(\.scope) == ConsentScopeId.allCases)

        let onlyUnknown = ConsentScopeCardPolicy.cards(
            mode: .manage(status: .live, currentScopes: ["gameplay": .granted])
        )
        #expect(onlyUnknown.isEmpty)
    }

    /// Pins today's policy: no scope is optional at launch, so a declined entry and a
    /// catalog scope missing from the server's map both give no card. A later optional
    /// scope has to change this test on purpose.
    @Test func manageGivesNoCardForADeclinedOrMissingScope() {
        var declined = launchScopes
        declined["analytics_internal"] = .declined
        let declinedCards = ConsentScopeCardPolicy.cards(
            mode: .manage(status: .live, currentScopes: declined)
        )
        #expect(!declinedCards.map(\.scope).contains(.analyticsInternal))
        #expect(declinedCards.count == ConsentScopeId.allCases.count - 1)

        var missing = launchScopes
        missing.removeValue(forKey: "ads_child_directed")
        let missingCards = ConsentScopeCardPolicy.cards(
            mode: .manage(status: .live, currentScopes: missing)
        )
        #expect(!missingCards.map(\.scope).contains(.adsChildDirected))
        #expect(missingCards.count == ConsentScopeId.allCases.count - 1)
    }

    // MARK: Anchors

    @Test func everyPolicyAnchorRoundTripsThroughItsURL() throws {
        #expect(ConsentScopePolicyAnchor.scheme == ChildConsentPolicyLink.scheme)
        for anchor in ConsentScopePolicyAnchor.allCases {
            let url = try #require(anchor.url)
            #expect(url.absoluteString == "rtr-legal://\(anchor.rawValue)")
            #expect(ConsentScopePolicyAnchor.from(url: url) == anchor)
        }
        // The terms/privacy links are not scope anchors, and vice versa.
        for link in ChildConsentPolicyLink.allCases {
            let url = try #require(link.url)
            #expect(ConsentScopePolicyAnchor.from(url: url) == nil)
        }
        #expect(ConsentScopePolicyAnchor.from(url: try #require(URL(string: "https://privacy-children-core"))) == nil)
    }
}
