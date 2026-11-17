//
//  DeferredSDKStartupTests.swift
//  LicensePlateAppTests
//
//  COPPA F-9 (FR-46) + F-15 (FR-56/FR-57): the SDK-startup deferral policy and its delta
//  application, ads SDK included. COPPA F-28 (FR-72(a)): child analytics collection is
//  consent-scoped. COPPA F-29 (FR-73): an ineligible session mints no push token.
//  Pure and deterministic — injectable seams only, no Firebase, no RevenueCat, no timing.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - The gate itself (pure policy)

@MainActor
struct DeferredSDKStartupPolicyTests {

    private func plan(
        ageResolved: Bool,
        posture: ChildSessionPosture,
        firebase: Bool = true,
        apiKey: Bool = true
    ) -> DeferredSDKStartupPlan {
        DeferredSDKStartupPolicy.plan(
            isAgeGateResolved: ageResolved,
            posture: posture,
            isFirebaseConfigured: firebase,
            hasPurchasesAPIKey: apiKey
        )
    }

    /// The FR-46 acceptance case: on a fresh install nothing has been answered and
    /// nothing has resolved, so there is no FCM, RevenueCat or Analytics start at all.
    @Test func freshInstallStartsNothing() {
        #expect(plan(ageResolved: false, posture: .unresolved) == .allDeferred)
    }

    /// Both halves of the gate are load-bearing, and neither implies the other.
    @Test func eitherHalfMissingHoldsEverything() {
        // Age answered, but this session's `users/{uid}` read has not landed yet.
        #expect(plan(ageResolved: true, posture: .unresolved) == .allDeferred)
        // Posture known from the FR-39 device ratchet, but this epoch never answered
        // (sign-out cleared it) — still age-unresolved, so still held.
        #expect(plan(ageResolved: false, posture: .ratchetedAnonymous) == .allDeferred)
        #expect(plan(ageResolved: false, posture: .childDirected) == .allDeferred)
        #expect(plan(ageResolved: false, posture: .confirmedNonChild) == .allDeferred)
    }

    @Test func resolvedAdultStartsAllFour() {
        let plan = plan(ageResolved: true, posture: .confirmedNonChild)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
        #expect(plan.startsPurchases)
        #expect(plan.startsAds)
    }

    /// FR-32/FR-34/FR-56 postures: a resolved child still gets the family-trip push plan,
    /// and is never handed to RevenueCat or to the ad network. FR-72(a): with no
    /// `analytics_internal` scope (F-21 not built), analytics collection stays OFF.
    @Test func resolvedChildStartsMessagingOnly() {
        let plan = plan(ageResolved: true, posture: .childDirected)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection == false)
        #expect(plan.startsPurchases == false)
        #expect(plan.startsAds == false)
    }

    /// FR-57 (overturns the old ratcheted-anonymous purchase carve-out): a device that
    /// has hosted a child hands its anonymous uid to NEITHER commerce SDK nor ad SDK,
    /// answered epoch or not. Push still releases; FR-72(a) / OD-14b keep analytics
    /// collection off — the resolution guard alone did NOT, once the epoch was answered.
    @Test func ratchetedAnonymousWithAnAnswerStartsNeitherPurchasesNorAdsNorAnalytics() {
        let plan = plan(ageResolved: true, posture: .ratchetedAnonymous)
        #expect(plan.startsPurchases == false)
        #expect(plan.startsAds == false)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection == false)
    }

    /// The whole matrix in one place: four postures × four startups, at the only age
    /// state that can release anything. `.unresolved` is held by the gate above; it is
    /// listed here so the row exists and can never silently start something.
    @Test func planMatrixOverEveryPosture() {
        // posture → (messaging, analytics, purchases, ads)
        let expected: [(ChildSessionPosture, Bool, Bool, Bool, Bool)] = [
            (.unresolved,        false, false, false, false),
            (.childDirected,     true,  false, false, false),
            (.ratchetedAnonymous, true, false, false, false),
            (.confirmedNonChild, true,  true,  true,  true),
        ]
        for (posture, messaging, analytics, purchases, ads) in expected {
            let plan = plan(ageResolved: true, posture: posture)
            #expect(plan.startsMessaging == messaging, "messaging for \(posture.rawValue)")
            #expect(plan.startsAnalyticsCollection == analytics, "analytics for \(posture.rawValue)")
            #expect(plan.startsPurchases == purchases, "purchases for \(posture.rawValue)")
            #expect(plan.startsAds == ads, "ads for \(posture.rawValue)")
        }
    }

    /// FR-56: ad STARTUP and ad DISPLAY are released by the same predicate, so the SDK
    /// can never be running for a session that may not show ads.
    @Test func adStartupTracksAdDisplayEligibility() {
        for posture in [ChildSessionPosture.unresolved, .childDirected, .ratchetedAnonymous, .confirmedNonChild] {
            #expect(plan(ageResolved: true, posture: posture).startsAds == posture.isAdDisplayEligible)
        }
    }

    /// Offline-only mode (no Firebase app): the two Firebase-side SDKs have nothing to
    /// start; neither RevenueCat nor Google Mobile Ads depends on Firebase.
    @Test func withoutFirebaseOnlyPurchasesAndAdsCanStart() {
        let plan = plan(ageResolved: true, posture: .confirmedNonChild, firebase: false)
        #expect(plan.startsMessaging == false)
        #expect(plan.startsAnalyticsCollection == false)
        #expect(plan.startsPurchases)
        #expect(plan.startsAds)
    }

    @Test func withoutAnApiKeyPurchasesNeverStart() {
        #expect(plan(ageResolved: true, posture: .confirmedNonChild, apiKey: false).startsPurchases == false)
    }

    // MARK: FR-72(a) — analytics collection is consent-scoped

    /// Every posture × consented/unconsented × F-21 scope × cooldown × Firebase configured ×
    /// age answered. Collection starts for exactly two shapes of cell: a confirmed adult, and a
    /// CONSENTED `.childDirected` session whose scope seam is true. The scope alone can never
    /// open it for an unconsented child, and no child posture opens while the seam is false.
    @Test func analyticsCollectionMatrixOverEveryPostureConsentScopeHoldAndFirebase() {
        let postures: [ChildSessionPosture] = [.unresolved, .childDirected, .ratchetedAnonymous, .confirmedNonChild]
        for posture in postures {
            for unconsented in [false, true] {
                for scope in [false, true] {
                    for held in [false, true] {
                        for firebase in [false, true] {
                            for ageResolved in [false, true] {
                                let plan = DeferredSDKStartupPolicy.plan(
                                    isAgeGateResolved: ageResolved,
                                    isUnder13RetryCooldownHeld: held,
                                    posture: posture,
                                    isFirebaseConfigured: firebase,
                                    hasPurchasesAPIKey: true,
                                    isUnconsentedChild: unconsented,
                                    isConsentedChildAnalyticsScopeGranted: scope
                                )
                                let open = firebase && ageResolved && !held && (
                                    posture == .confirmedNonChild
                                        || (posture == .childDirected && !unconsented && scope)
                                )
                                #expect(
                                    plan.startsAnalyticsCollection == open,
                                    "\(posture.rawValue) unconsented=\(unconsented) scope=\(scope) held=\(held) firebase=\(firebase) answered=\(ageResolved)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// The baseline ruling: until F-21 passes the scope, NO child session collects —
    /// consented, unconsented, provisional or held alike.
    @Test func withTheSeamAtItsDefaultNoChildPostureEverCollects() {
        for unconsented in [false, true] {
            for posture in [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved] {
                let plan = DeferredSDKStartupPolicy.plan(
                    isAgeGateResolved: true,
                    hasAccountProvenance: true,
                    posture: posture,
                    isFirebaseConfigured: true,
                    hasPurchasesAPIKey: true,
                    isUnconsentedChild: unconsented
                )
                #expect(plan.startsAnalyticsCollection == false, "\(posture.rawValue) unconsented=\(unconsented)")
            }
        }
    }

    /// The scope opens a consented child only; it cannot open an unconsented child, and
    /// it has no say over any non-child posture.
    @Test func theScopeAloneCannotOpenAnUnconsentedChild() {
        func analytics(_ posture: ChildSessionPosture, unconsented: Bool) -> Bool {
            DeferredSDKStartupPolicy.plan(
                isAgeGateResolved: true,
                posture: posture,
                isFirebaseConfigured: true,
                hasPurchasesAPIKey: true,
                isUnconsentedChild: unconsented,
                isConsentedChildAnalyticsScopeGranted: true
            ).startsAnalyticsCollection
        }
        #expect(analytics(.childDirected, unconsented: false))
        #expect(analytics(.childDirected, unconsented: true) == false)
        #expect(analytics(.ratchetedAnonymous, unconsented: false) == false)
        #expect(analytics(.unresolved, unconsented: false) == false)
    }

    /// FR-72(a) moves analytics only: messaging, purchases and ads are the same plan with
    /// or without the consent inputs (the FR-73 consent half is applied by the service).
    @Test func consentInputsChangeNothingButAnalytics() {
        for posture in [ChildSessionPosture.unresolved, .childDirected, .ratchetedAnonymous, .confirmedNonChild] {
            let base = plan(ageResolved: true, posture: posture)
            for unconsented in [false, true] {
                for scope in [false, true] {
                    let p = DeferredSDKStartupPolicy.plan(
                        isAgeGateResolved: true,
                        posture: posture,
                        isFirebaseConfigured: true,
                        hasPurchasesAPIKey: true,
                        isUnconsentedChild: unconsented,
                        isConsentedChildAnalyticsScopeGranted: scope
                    )
                    #expect(p.startsMessaging == base.startsMessaging)
                    #expect(p.startsPurchases == base.startsPurchases)
                    #expect(p.startsAds == base.startsAds)
                }
            }
        }
    }

    @Test func resolutionPredicateRequiresBothHalves() {
        #expect(DeferredSDKStartupPolicy.isAgeResolutionComplete(
            isAgeGateResolved: true, posture: .confirmedNonChild))
        #expect(!DeferredSDKStartupPolicy.isAgeResolutionComplete(
            isAgeGateResolved: true, posture: .unresolved))
        #expect(!DeferredSDKStartupPolicy.isAgeResolutionComplete(
            isAgeGateResolved: false, posture: .childDirected))
    }
}

// MARK: - Delta application across the three FR-46 lifecycle cases

@MainActor
struct DeferredSDKStartupServiceTests {

    /// Mutable world behind the injected seams, with an ordered event log so "started
    /// exactly once, in this order" is provable.
    @MainActor
    final class World {
        var ageResolved = false
        var hasAPIKey = true
        var authUserId: String?
        var unconsentedChild = false
        /// FR-73's positive consent evidence. `true` by default so a `.childDirected` world
        /// models a configured, consented child; `false` models the pre-`configure` window.
        var consentedChild = true
        var analyticsScopeGranted = false
        var events: [String] = []

        func makeService() -> DeferredSDKStartupService {
            var deps = DeferredSDKStartupService.Dependencies(
                isAgeGateResolved: { [weak self] in self?.ageResolved ?? false },
                hasPurchasesAPIKey: { [weak self] in self?.hasAPIKey ?? false },
                currentAuthUserId: { [weak self] in self?.authUserId },
                setMessagingAutoInitEnabled: { [weak self] in self?.events.append("fcmAutoInit(\($0))") },
                configureMessaging: { [weak self] in self?.events.append("fcmConfigure") },
                setAnalyticsCollectionEnabled: { [weak self] in self?.events.append("analytics(\($0))") },
                configurePurchases: { [weak self] in self?.events.append("rcConfigure") },
                identifyPurchases: { [weak self] in self?.events.append("rcIdentify(\($0 ?? "nil"))") },
                startAds: { [weak self] in self?.events.append("adsStart(\($0.rawValue))") }
            )
            deps.isUnconsentedChild = { [weak self] in self?.unconsentedChild ?? false }
            deps.isConsentedChild = { [weak self] in self?.consentedChild ?? false }
            deps.isConsentedChildAnalyticsScopeGranted = { [weak self] in self?.analyticsScopeGranted ?? false }
            return DeferredSDKStartupService(dependencies: deps)
        }
    }

    // MARK: Cold start

    /// Launch applies the holds rather than assuming them: both Firebase switches
    /// persist across launches, so a previously resolved install must be re-held.
    @Test func launchInstallsExplicitHolds() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        #expect(world.events == ["fcmAutoInit(false)", "analytics(false)"])
        #expect(service.currentPlan == .allDeferred)
    }

    @Test func coldStartHoldsWhileUnresolvedHoweverManyTriggersFire() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()

        service.apply(posture: .unresolved)
        service.apply(posture: .unresolved)
        world.ageResolved = true          // answered, but the child signal is still out
        service.apply(posture: .unresolved)

        #expect(world.events.isEmpty)
        #expect(service.currentPlan == .allDeferred)
    }

    @Test func releasesOnceOnResolutionAndIsIdempotent() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()

        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)

        #expect(world.events == [
            "fcmAutoInit(true)", "fcmConfigure", "analytics(true)", "rcConfigure", "rcIdentify(u1)",
            "adsStart(confirmedNonChild)",
        ])

        // Re-running the routine with unchanged inputs must emit nothing.
        world.events.removeAll()
        service.apply(posture: .confirmedNonChild)
        service.apply(posture: .confirmedNonChild)
        #expect(world.events.isEmpty)
    }

    /// A consented child session resolves too — it never reaches RevenueCat or the ads SDK,
    /// and (FR-72(a), no F-21 scope yet) never turns analytics collection on.
    @Test func resolvedChildReleasesWithoutTouchingPurchasesOrAds() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()

        world.ageResolved = true
        world.authUserId = "child1"
        service.apply(posture: .childDirected)

        #expect(world.events == ["fcmAutoInit(true)", "fcmConfigure"])
    }

    // MARK: FR-72(a) — the F-21 seam

    /// The seam ships unwired: the production dependency set answers `false`, so every
    /// child session runs with collection off until F-21 wires the scope. A ship-state pin,
    /// not a behaviour test — F-21 is expected to change it.
    @Test func theLiveScopeSeamIsUnwiredAndFalse() {
        #expect(DeferredSDKStartupService.Dependencies.live().isConsentedChildAnalyticsScopeGranted() == false)
    }

    /// Through the service: the seam turns collection on for a consented child only, and
    /// losing the scope (or consent) turns it back off.
    @Test func theScopeSeamOpensAndClosesCollectionForAConsentedChildOnly() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "child1"
        service.apply(posture: .childDirected)
        world.events.removeAll()

        world.analyticsScopeGranted = true
        service.apply(posture: .childDirected)
        #expect(world.events == ["analytics(true)"])

        world.events.removeAll()
        world.unconsentedChild = true          // revocation: scope alone cannot hold it open
        service.apply(posture: .childDirected)
        #expect(world.events == ["fcmAutoInit(false)", "analytics(false)"])
    }

    @Test func theScopeSeamNeverOpensAnUnconsentedChild() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()
        world.ageResolved = true
        world.authUserId = "child1"
        world.unconsentedChild = true
        world.analyticsScopeGranted = true

        service.apply(posture: .childDirected)

        #expect(world.events.contains("analytics(true)") == false)
        #expect(service.currentPlan.startsAnalyticsCollection == false)
    }

    // MARK: FR-73 — an ineligible session mints no push token

    /// The confirmed finding, as a test: an unconsented child is age-resolved, so the plan
    /// releases messaging — but FCM auto-init and `configure` (APNs registration + the first
    /// `Messaging.token()`) must not run, because minting is the act of creating the
    /// persistent identifier.
    @Test func anUnconsentedChildNeitherAutoInitsNorConfiguresMessaging() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()
        world.ageResolved = true
        world.authUserId = "child1"
        world.unconsentedChild = true

        service.apply(posture: .childDirected)
        service.apply(posture: .childDirected)

        #expect(world.events.isEmpty)
        // The FR-46 half of the plan is unchanged — PushTokenEligibilityPolicy still reads it.
        #expect(service.currentPlan.startsMessaging)
    }

    /// Consent arriving re-runs the routine under the SAME posture and plan; messaging then
    /// starts exactly once. Revocation turns auto-init back off without re-configuring.
    @Test func consentStartsMessagingOnceAndRevocationStopsAutoInit() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "child1"
        world.unconsentedChild = true
        service.apply(posture: .childDirected)
        world.events.removeAll()

        world.unconsentedChild = false         // `.userProfilesMerged` → `.profileMerge`
        service.apply(posture: .childDirected)
        service.apply(posture: .childDirected)
        #expect(world.events == ["fcmAutoInit(true)", "fcmConfigure"])

        world.events.removeAll()
        world.unconsentedChild = true
        service.apply(posture: .childDirected)
        #expect(world.events == ["fcmAutoInit(false)"])

        world.events.removeAll()
        world.unconsentedChild = false
        service.apply(posture: .childDirected)
        #expect(world.events == ["fcmAutoInit(true)"])
    }

    /// Eligible sessions are unchanged: an adult and a consented child configure messaging
    /// exactly as before the pre-mint gate.
    @Test func eligibleSessionsStillStartMessaging() {
        for posture in [ChildSessionPosture.confirmedNonChild, .childDirected] {
            let world = World()
            let service = world.makeService()
            service.installAtLaunch(isFirebaseConfigured: true)
            world.events.removeAll()
            world.ageResolved = true
            world.hasAPIKey = false
            service.apply(posture: posture)
            #expect(Array(world.events.prefix(2)) == ["fcmAutoInit(true)", "fcmConfigure"], "\(posture.rawValue)")
        }
    }

    /// The pre-`configure` window: `ChildRestrictedModeService` is not wired yet, so a
    /// Keychain-restored, server-flagged child reads neither unconsented NOR consented. The
    /// absence of "unconsented" must not be read as consent — nothing is minted until the
    /// post-bootstrap re-run supplies positive evidence, and then it configures exactly once.
    @Test func aChildPostureWithoutPositiveConsentEvidenceMintsNothing() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()
        world.ageResolved = true
        world.authUserId = "child1"
        world.unconsentedChild = false
        world.consentedChild = false

        service.apply(posture: .childDirected)
        #expect(world.events.isEmpty)
        #expect(service.isMessagingEnabled == false)

        world.consentedChild = true            // `configure` + the `.identityTransition` re-run
        service.apply(posture: .childDirected)
        #expect(world.events == ["fcmAutoInit(true)", "fcmConfigure"])
        #expect(service.isMessagingEnabled)
    }

    /// The consent-evidence term is child-only: an adult never consults it.
    @Test func anAdultNeedsNoConsentEvidence() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()
        world.ageResolved = true
        world.hasAPIKey = false
        world.consentedChild = false

        service.apply(posture: .confirmedNonChild)

        #expect(Array(world.events.prefix(2)) == ["fcmAutoInit(true)", "fcmConfigure"])
    }

    // MARK: Guest → registered link

    /// Linking preserves nothing but the gate state: the uid changes, so RevenueCat is
    /// re-identified exactly once and no SDK is re-started.
    @Test func guestToRegisteredLinkReIdentifiesPurchasesOnly() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "guest1"
        service.apply(posture: .confirmedNonChild)
        world.events.removeAll()

        world.authUserId = "registered1"
        service.apply(posture: .confirmedNonChild)

        #expect(world.events == ["rcIdentify(registered1)"])
    }

    // MARK: Sign-out → anonymous rebirth

    /// Sign-out clears the epoch answer (F-6), so the gate CLOSES again — it is not a
    /// one-way latch. The rebirth session must not inherit the previous account's start.
    @Test func signOutRebirthClosesTheGateAndDropsThePurchaseIdentity() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)
        world.events.removeAll()

        world.ageResolved = false     // AgeGateStore.clearAnswer() at sign-out
        world.authUserId = nil
        service.apply(posture: .unresolved)

        #expect(world.events == ["fcmAutoInit(false)", "analytics(false)", "rcIdentify(nil)"])
        #expect(service.currentPlan == .allDeferred)
    }

    /// ...and answering again in the new epoch re-opens it, without re-configuring the
    /// SDKs that can only be configured once.
    @Test func rebirthReopensWithoutReconfiguring() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)
        world.ageResolved = false
        world.authUserId = nil
        service.apply(posture: .unresolved)
        world.events.removeAll()

        world.ageResolved = true
        world.authUserId = "guest2"
        service.apply(posture: .confirmedNonChild)

        // No second `fcmConfigure` / `rcConfigure` — those are one-time bootstraps.
        #expect(world.events == ["fcmAutoInit(true)", "analytics(true)", "rcIdentify(guest2)"])
    }

    // MARK: Mid-session flag flip (FR-23 seam)

    /// A server-side flip to child mid-session drops the RevenueCat identity (FR-34),
    /// leaves push running (FR-32), and stops analytics collection (FR-72(a), no scope).
    @Test func adultToChildDropsThePurchaseIdentityAndStopsAnalytics() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)
        world.events.removeAll()

        service.apply(posture: .childDirected)

        #expect(world.events == ["analytics(false)", "rcIdentify(nil)"])
    }

    /// A parent correction back to adult starts analytics collection, re-identifies and
    /// starts the ads SDK for the first time, and never re-configures what is configured.
    @Test func childToAdultCorrectionReIdentifiesAndStartsAds() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .childDirected)
        world.events.removeAll()

        service.apply(posture: .confirmedNonChild)

        #expect(world.events == ["analytics(true)", "rcConfigure", "rcIdentify(u1)", "adsStart(confirmedNonChild)"])
    }

    // MARK: Ads (FR-56)

    /// The FR-56 defect, as a test: no posture short of a confirmed adult may start the
    /// ads SDK, however many triggers fire — this is the clean-install path that used to
    /// run `MobileAds.start()` untagged from `didFinishLaunching`.
    @Test func adsNeverStartForANonAdultPosture() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"

        service.apply(posture: .unresolved)
        service.apply(posture: .childDirected)
        service.apply(posture: .ratchetedAnonymous)

        #expect(world.events.contains { $0.hasPrefix("adsStart") } == false)
        #expect(service.currentPlan.startsAds == false)
    }

    /// `MobileAds.start()` is one-way: the SDK cannot be un-started, so the release
    /// happens exactly once and a later child correction does not re-fire it.
    @Test func adsStartOnceAndNeverRestart() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)
        world.events.removeAll()

        service.apply(posture: .childDirected)
        service.apply(posture: .confirmedNonChild)
        service.apply(posture: .confirmedNonChild)

        #expect(world.events.contains { $0.hasPrefix("adsStart") } == false)
    }

    /// The start carries the posture that released it, so `AdMobService`'s pre-start
    /// stamp is derived from the same value the posture routine applied (FR-17).
    @Test func adsStartCarriesTheReleasingPosture() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        service.apply(posture: .confirmedNonChild)

        #expect(world.events.contains("adsStart(confirmedNonChild)"))
        #expect(AdMobService.preStartChildDirected(posture: .confirmedNonChild) == false)
    }
}

// MARK: - Ordering against the FR-32 posture (one routine, correct sequence)

@MainActor
struct DeferredSDKStartupPostureOrderingTests {

    @MainActor
    final class Log {
        var events: [String] = []
    }

    /// FR-32 before FR-46: Analytics COLLECTION is only ever released after the child
    /// session's ad-personalization posture has been applied, so no event can be
    /// collected under an un-applied posture.
    @Test func personalizationPostureIsAppliedBeforeTheStartupRelease() {
        let log = Log()
        let deps = ChildSessionPostureCoordinator.Dependencies(
            currentAuthIdentity: { ("child1", false) },
            freshIsChildAccount: { _ in true },
            isFreshChildFlagExplicit: { _ in true },
            cachedIsChildAccount: { _ in nil },
            storeCachedIsChildAccount: { _, _, _ in },
            isDeclaredChildIdentity: { _ in false },
            isUnder13FlowAnswer: { false },
            isAgeResolved: { true },
            isDeviceRatcheted: { false },
            engageDeviceRatchet: {},
            clearChildIdentityLineage: { _ in },
            hasAnyCachedChildTrue: { false },
            hasDeclaredChildHistory: { false },
            hasConfirmedChildDeclaration: { _ in false },
            hasOutstandingChildDeclaration: { false },
            liftDeviceChildMarkers: {},
            applyChildDirectedTreatment: { _ in },
            setAdPersonalizationSignalsDisabled: { [weak log] in
                log?.events.append("personalization(disabled=\($0))")
            },
            setLocationForcedOff: { _ in },
            releaseDeferredSDKStartups: { [weak log] in
                log?.events.append("release(\($0.rawValue))")
            }
        )
        let coordinator = ChildSessionPostureCoordinator(dependencies: deps)
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(log.events == ["personalization(disabled=true)", "release(childDirected)"])
    }

    /// FR-56 ordering, both sides: the TFCD stamp is applied BEFORE the ads SDK is
    /// released, and the banner refresh notification fires AFTER it — so a reloading
    /// banner can neither out-run the tag nor build a request into an unstarted SDK.
    @Test func adsAreTaggedThenStartedThenBannersRefresh() {
        let log = Log()
        let observer = NotificationCenter.default.addObserver(
            forName: .adIdentityDidChange,
            object: nil,
            queue: nil
        ) { [weak log] _ in
            // Posted synchronously on the main actor (queue: nil), like the live
            // `AdBannerView` observer.
            MainActor.assumeIsolated {
                log?.events.append("bannerRefresh")
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let deps = ChildSessionPostureCoordinator.Dependencies(
            currentAuthIdentity: { ("u1", false) },
            freshIsChildAccount: { _ in false },
            isFreshChildFlagExplicit: { _ in true },
            cachedIsChildAccount: { _ in nil },
            storeCachedIsChildAccount: { _, _, _ in },
            isDeclaredChildIdentity: { _ in false },
            isUnder13FlowAnswer: { false },
            isAgeResolved: { true },
            isDeviceRatcheted: { false },
            engageDeviceRatchet: {},
            clearChildIdentityLineage: { _ in },
            hasAnyCachedChildTrue: { false },
            hasDeclaredChildHistory: { false },
            hasConfirmedChildDeclaration: { _ in false },
            hasOutstandingChildDeclaration: { false },
            liftDeviceChildMarkers: {},
            applyChildDirectedTreatment: { [weak log] in log?.events.append("tfcd(\($0))") },
            setAdPersonalizationSignalsDisabled: { _ in },
            setLocationForcedOff: { _ in },
            releaseDeferredSDKStartups: { [weak log] in
                log?.events.append("release(\($0.rawValue))")
            }
        )
        let coordinator = ChildSessionPostureCoordinator(dependencies: deps)
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(log.events == ["tfcd(false)", "release(confirmedNonChild)", "bannerRefresh"])
    }

    /// The age answer is itself a resolution event, so it re-runs the one routine.
    @Test func ageResolutionIsATriggerOnTheSameRoutine() {
        let log = Log()
        let deps = ChildSessionPostureCoordinator.Dependencies(
            currentAuthIdentity: { ("u1", false) },
            freshIsChildAccount: { _ in false },
            isFreshChildFlagExplicit: { _ in true },
            cachedIsChildAccount: { _ in nil },
            storeCachedIsChildAccount: { _, _, _ in },
            isDeclaredChildIdentity: { _ in false },
            isUnder13FlowAnswer: { false },
            isAgeResolved: { true },
            isDeviceRatcheted: { false },
            engageDeviceRatchet: {},
            clearChildIdentityLineage: { _ in },
            hasAnyCachedChildTrue: { false },
            hasDeclaredChildHistory: { false },
            hasConfirmedChildDeclaration: { _ in false },
            hasOutstandingChildDeclaration: { false },
            liftDeviceChildMarkers: {},
            applyChildDirectedTreatment: { _ in },
            setAdPersonalizationSignalsDisabled: { _ in },
            setLocationForcedOff: { _ in },
            releaseDeferredSDKStartups: { [weak log] in
                log?.events.append("release(\($0.rawValue))")
            }
        )
        let coordinator = ChildSessionPostureCoordinator(dependencies: deps)
        coordinator.applyPostures(trigger: .ageResolution)

        #expect(log.events == ["release(confirmedNonChild)"])
    }
}
