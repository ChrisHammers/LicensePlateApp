//
//  DeferredSDKStartupTests.swift
//  LicensePlateAppTests
//
//  COPPA F-9 (FR-46) + F-15 (FR-56/FR-57): the SDK-startup deferral policy and its delta
//  application, ads SDK included.
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

    /// FR-32/FR-34/FR-56 postures: a resolved child still gets family-trip push and
    /// internal-ops analytics, and is never handed to RevenueCat or to the ad network.
    @Test func resolvedChildStartsMessagingAndAnalyticsOnly() {
        let plan = plan(ageResolved: true, posture: .childDirected)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
        #expect(plan.startsPurchases == false)
        #expect(plan.startsAds == false)
    }

    /// FR-57 (overturns the old ratcheted-anonymous purchase carve-out): a device that
    /// has hosted a child hands its anonymous uid to NEITHER commerce SDK nor ad SDK,
    /// answered epoch or not. Push and internal-ops analytics still release.
    @Test func ratchetedAnonymousWithAnAnswerStartsNeitherPurchasesNorAds() {
        let plan = plan(ageResolved: true, posture: .ratchetedAnonymous)
        #expect(plan.startsPurchases == false)
        #expect(plan.startsAds == false)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
    }

    /// The whole matrix in one place: four postures × four startups, at the only age
    /// state that can release anything. `.unresolved` is held by the gate above; it is
    /// listed here so the row exists and can never silently start something.
    @Test func planMatrixOverEveryPosture() {
        // posture → (messaging, analytics, purchases, ads)
        let expected: [(ChildSessionPosture, Bool, Bool, Bool, Bool)] = [
            (.unresolved,        false, false, false, false),
            (.childDirected,     true,  true,  false, false),
            (.ratchetedAnonymous, true, true,  false, false),
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
        var events: [String] = []

        func makeService() -> DeferredSDKStartupService {
            let deps = DeferredSDKStartupService.Dependencies(
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

    /// A child session resolves too — it just never reaches RevenueCat or the ads SDK.
    @Test func resolvedChildReleasesWithoutTouchingPurchasesOrAds() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.events.removeAll()

        world.ageResolved = true
        world.authUserId = "child1"
        service.apply(posture: .childDirected)

        #expect(world.events == ["fcmAutoInit(true)", "fcmConfigure", "analytics(true)"])
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

    /// A server-side flip to child mid-session drops the RevenueCat identity (FR-34) and
    /// leaves the internal-ops analytics + push postures running (FR-32).
    @Test func adultToChildDropsThePurchaseIdentityOnly() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .confirmedNonChild)
        world.events.removeAll()

        service.apply(posture: .childDirected)

        #expect(world.events == ["rcIdentify(nil)"])
    }

    /// A parent correction back to adult re-identifies and starts the ads SDK for the
    /// first time, and still never re-configures what is already configured.
    @Test func childToAdultCorrectionReIdentifiesAndStartsAds() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .childDirected)
        world.events.removeAll()

        service.apply(posture: .confirmedNonChild)

        #expect(world.events == ["rcConfigure", "rcIdentify(u1)", "adsStart(confirmedNonChild)"])
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
