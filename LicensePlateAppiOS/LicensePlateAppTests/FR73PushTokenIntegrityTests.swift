//
//  FR73PushTokenIntegrityTests.swift
//  LicensePlateAppTests
//
//  COPPA F-29 (FR-73 / v2.1 FR-53): push-token integrity, the bypass closure, and the
//  child-scoped push surfaces.
//
//  Pure and deterministic — policy types and injectable seams only. No Firebase, no
//  Messaging, no network, no timing. The three FR-73(a) bypass CALL SITES
//  (`RootView`, `FirebaseAuthService` × 2) all funnel through
//  `FirebaseMessagingService.refreshAndPersistTokenIfPossible`, whose guard is a direct
//  delegation to `PushTokenEligibilityPolicy` — so the policy matrix below is what
//  actually pins their behaviour.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - FR-73(a): who may hold a push token

@MainActor
struct PushTokenEligibilityPolicyTests {

    private func allows(startsMessaging: Bool, unconsentedChild: Bool) -> Bool {
        PushTokenEligibilityPolicy.allowsTokenRegistration(
            startsMessaging: startsMessaging,
            isUnconsentedChild: unconsentedChild
        )
    }

    /// The only combination that mints a token: FR-46's age gate open AND FR-28's consent
    /// gate satisfied.
    @Test func onlyAResolvedNonUnconsentedSessionRegisters() {
        #expect(allows(startsMessaging: true, unconsentedChild: false))
    }

    /// The gap FR-73 exists to close. A declared child is age-RESOLVED (as `.childDirected`),
    /// so `DeferredSDKStartupPolicy` starts messaging for them — correct for a consented
    /// child, and the entire exposure for an unconsented one. If this ever returns true,
    /// an unconsented child is minting a persistent identifier again.
    @Test func aResolvedButUnconsentedChildIsRefused() {
        #expect(!allows(startsMessaging: true, unconsentedChild: true))
    }

    /// FR-46 still governs on its own: an age-unresolved session registers nothing, whatever
    /// the consent answer happens to be. This is the age-unknown / rebirth case the three
    /// bypass call sites used to walk straight past.
    @Test func anUnresolvedSessionIsRefusedEitherWay() {
        #expect(!allows(startsMessaging: false, unconsentedChild: false))
        #expect(!allows(startsMessaging: false, unconsentedChild: true))
    }

    /// Both halves are required and neither implies the other — the same discipline
    /// `DeferredSDKStartupPolicy.isAgeResolutionComplete` documents for its own two halves.
    @Test func bothHalvesAreLoadBearing() {
        #expect(allows(startsMessaging: true, unconsentedChild: false))
        for (messaging, child) in [(true, true), (false, false), (false, true)] {
            #expect(!allows(startsMessaging: messaging, unconsentedChild: child))
        }
    }
}

// MARK: - FR-73(b)/(c): the child-scoped push surfaces

@MainActor
struct ChildPushRestrictionPolicyTests {

    private func restrictsPrompt(
        unconsented: Bool,
        under13Answer: Bool,
        provisioned: Bool
    ) -> Bool {
        ChildPushRestrictionPolicy.restrictsNotificationPermission(
            isUnconsentedChild: unconsented,
            isUnder13FlowAnswer: under13Answer,
            hasProvisionedIdentity: provisioned
        )
    }

    @Test func anUnconsentedChildIsNeverShownTheNotificationPrompt() {
        #expect(restrictsPrompt(unconsented: true, under13Answer: true, provisioned: true))
        #expect(restrictsPrompt(unconsented: true, under13Answer: false, provisioned: true))
    }

    /// FR-73(b)'s scope, and the half that is easy to get wrong in the protective direction:
    /// a CONSENTED child still receives the bounded family-trip categories (FR-38), so they
    /// keep the OS permission row. Denying it would take away a capability the parent's
    /// consent explicitly covers.
    @Test func aConsentedChildKeepsTheNotificationPrompt() {
        #expect(!restrictsPrompt(unconsented: false, under13Answer: true, provisioned: true))
    }

    /// The FR-33 no-gap property, carried over: an under-13 answer counts from the moment it
    /// is recorded, before any uid exists. Sound rather than merely cautious — with no
    /// provisioned identity there is no `activeFamilyId` and no consent record that could
    /// exist, so this window is necessarily an unconsented child.
    @Test func theAnsweredButUnprovisionedWindowHasNoGap() {
        #expect(restrictsPrompt(unconsented: false, under13Answer: true, provisioned: false))
    }

    /// An adult mid-onboarding (no uid yet, not an under-13 answer) must not be caught.
    @Test func anUnprovisionedAdultKeepsThePrompt() {
        #expect(!restrictsPrompt(unconsented: false, under13Answer: false, provisioned: false))
        #expect(!restrictsPrompt(unconsented: false, under13Answer: false, provisioned: true))
    }

    // MARK: FR-73(c) — marketing toggle

    private func hidesMarketing(childSession: Bool, under13Answer: Bool) -> Bool {
        ChildPushRestrictionPolicy.hidesMarketingPushToggle(
            isChildAccountSession: childSession,
            isUnder13FlowAnswer: under13Answer
        )
    }

    /// Deliberately WIDER than (b): consent buys the bounded family-trip categories, but
    /// nothing a parent consented to reaches promotional contact, and the amended
    /// §312.5(c)(7) internal-operations exception may not be used to prompt or encourage
    /// use of the service. So a CONSENTED child loses the toggle too.
    @Test func noChildIsOfferedTheMarketingToggle() {
        #expect(hidesMarketing(childSession: true, under13Answer: false))
        #expect(hidesMarketing(childSession: true, under13Answer: true))
    }

    /// Same no-gap window as (b): the answer counts before the account exists.
    @Test func theMarketingToggleHidesOnTheAnswerAlone() {
        #expect(hidesMarketing(childSession: false, under13Answer: true))
    }

    @Test func adultsKeepTheMarketingToggle() {
        #expect(!hidesMarketing(childSession: false, under13Answer: false))
    }

    /// The two rules are not the same rule. (c) catches a consented child that (b) does not —
    /// if these ever collapse into one another, one of the two requirements has been lost.
    @Test func theTwoSurfacesDivergeOnAConsentedChild() {
        let consentedChild = (childSession: true, unconsented: false, under13: true)
        #expect(!restrictsPrompt(
            unconsented: consentedChild.unconsented,
            under13Answer: consentedChild.under13,
            provisioned: true
        ))
        #expect(hidesMarketing(
            childSession: consentedChild.childSession,
            under13Answer: consentedChild.under13
        ))
    }
}

// MARK: - FR-73(a): the startup plan is visible before it is acted on

@MainActor
final class MessagingConfigureProbe {
    var startsMessagingWhenConfigured: Bool?
    var configureCount = 0
    weak var service: DeferredSDKStartupService?
}

@MainActor
struct DeferredStartupPlanVisibilityTests {

    private func makeService(_ probe: MessagingConfigureProbe) -> DeferredSDKStartupService {
        let deps = DeferredSDKStartupService.Dependencies(
            isAgeGateResolved: { true },
            hasPurchasesAPIKey: { false },
            currentAuthUserId: { nil },
            setMessagingAutoInitEnabled: { _ in },
            configureMessaging: {
                probe.configureCount += 1
                probe.startsMessagingWhenConfigured = probe.service?.currentPlan.startsMessaging
            },
            setAnalyticsCollectionEnabled: { _ in },
            configurePurchases: {},
            identifyPurchases: { _ in },
            startAds: { _ in }
        )
        let service = DeferredSDKStartupService(dependencies: deps)
        probe.service = service
        return service
    }

    /// REGRESSION (FR-73): `currentPlan` used to be committed at the END of `applyPlan`, so
    /// the token fetch that `configureMessaging()` kicks off could observe
    /// `startsMessaging: false` for the very plan that had just released it — and the new
    /// eligibility guard would then suppress a token the session was entitled to. Not a
    /// leak, but a real self-inflicted breakage. The plan is now published first.
    @Test func theReleasedPlanIsVisibleWhenMessagingConfigures() {
        let probe = MessagingConfigureProbe()
        let service = makeService(probe)
        service.installAtLaunch(isFirebaseConfigured: true)

        service.apply(posture: .confirmedNonChild)

        #expect(probe.configureCount == 1)
        #expect(probe.startsMessagingWhenConfigured == true)
    }

    /// A consented child is `.childDirected` and age-resolved, so messaging still starts for
    /// them (FR-53(c) / FR-38) — the eligibility guard, not the startup plan, is what
    /// separates them from an unconsented child.
    @Test func aChildDirectedSessionStillReleasesMessaging() {
        let probe = MessagingConfigureProbe()
        let service = makeService(probe)
        service.installAtLaunch(isFirebaseConfigured: true)

        service.apply(posture: .childDirected)

        #expect(probe.startsMessagingWhenConfigured == true)
        #expect(service.currentPlan.startsMessaging)
    }

    /// The delta behaviour my ordering change touched: re-applying an unchanged plan must
    /// still be free, and `configureMessaging` stays the one-time bootstrap it was.
    @Test func reapplyingTheSamePostureDoesNotReconfigure() {
        let probe = MessagingConfigureProbe()
        let service = makeService(probe)
        service.installAtLaunch(isFirebaseConfigured: true)

        service.apply(posture: .confirmedNonChild)
        service.apply(posture: .confirmedNonChild)
        service.apply(posture: .confirmedNonChild)

        #expect(probe.configureCount == 1)
    }

    /// Closing the gate re-holds it, and the plan reflects that immediately.
    @Test func losingThePostureReHoldsMessaging() {
        let probe = MessagingConfigureProbe()
        let service = makeService(probe)
        service.installAtLaunch(isFirebaseConfigured: true)

        service.apply(posture: .confirmedNonChild)
        #expect(service.currentPlan.startsMessaging)

        service.apply(posture: .unresolved)
        #expect(!service.currentPlan.startsMessaging)
    }
}
