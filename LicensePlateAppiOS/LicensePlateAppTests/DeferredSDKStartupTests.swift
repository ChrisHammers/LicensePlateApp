//
//  DeferredSDKStartupTests.swift
//  LicensePlateAppTests
//
//  COPPA F-9 (FR-46): the SDK-startup deferral policy and its delta application.
//  Pure and deterministic — injectable seams only, no Firebase, no RevenueCat, no timing.
//

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

    @Test func resolvedAdultStartsAllThree() {
        let plan = plan(ageResolved: true, posture: .confirmedNonChild)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
        #expect(plan.startsPurchases)
    }

    /// FR-32/FR-34 postures: a resolved child still gets family-trip push and
    /// internal-ops analytics, and is never handed to RevenueCat.
    @Test func resolvedChildStartsMessagingAndAnalyticsButNeverPurchases() {
        let plan = plan(ageResolved: true, posture: .childDirected)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
        #expect(plan.startsPurchases == false)
    }

    /// A ratcheted-anonymous session is ad-ineligible (FR-39) but is not a child
    /// account, so FR-34 does not suppress its purchases. The gate must not
    /// over-restrict once the epoch has an answer.
    @Test func ratchetedAnonymousWithAnAnswerMayStartPurchases() {
        let plan = plan(ageResolved: true, posture: .ratchetedAnonymous)
        #expect(plan.startsPurchases)
        #expect(plan.startsMessaging)
        #expect(plan.startsAnalyticsCollection)
    }

    /// Offline-only mode (no Firebase app): the two Firebase-side SDKs have nothing to
    /// start; RevenueCat does not depend on Firebase.
    @Test func withoutFirebaseOnlyPurchasesCanStart() {
        let plan = plan(ageResolved: true, posture: .confirmedNonChild, firebase: false)
        #expect(plan.startsMessaging == false)
        #expect(plan.startsAnalyticsCollection == false)
        #expect(plan.startsPurchases)
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
                identifyPurchases: { [weak self] in self?.events.append("rcIdentify(\($0 ?? "nil"))") }
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
        ])

        // Re-running the routine with unchanged inputs must emit nothing.
        world.events.removeAll()
        service.apply(posture: .confirmedNonChild)
        service.apply(posture: .confirmedNonChild)
        #expect(world.events.isEmpty)
    }

    /// A child session resolves too — it just never reaches RevenueCat.
    @Test func resolvedChildReleasesWithoutTouchingPurchases() {
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

    /// A parent correction back to adult re-identifies, and still never re-configures.
    @Test func childToAdultCorrectionReIdentifies() {
        let world = World()
        let service = world.makeService()
        service.installAtLaunch(isFirebaseConfigured: true)
        world.ageResolved = true
        world.authUserId = "u1"
        service.apply(posture: .childDirected)
        world.events.removeAll()

        service.apply(posture: .confirmedNonChild)

        #expect(world.events == ["rcConfigure", "rcIdentify(u1)"])
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
            storeCachedIsChildAccount: { _, _ in },
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

    /// The age answer is itself a resolution event, so it re-runs the one routine.
    @Test func ageResolutionIsATriggerOnTheSameRoutine() {
        let log = Log()
        let deps = ChildSessionPostureCoordinator.Dependencies(
            currentAuthIdentity: { ("u1", false) },
            freshIsChildAccount: { _ in false },
            isFreshChildFlagExplicit: { _ in true },
            cachedIsChildAccount: { _ in nil },
            storeCachedIsChildAccount: { _, _ in },
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
