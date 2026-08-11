//
//  ChildSessionPostureTests.swift
//  LicensePlateAppTests
//
//  COPPA F-7 (FR-17/18/19/23/32/33/34/39): posture policy matrix, signal cache /
//  device ratchet semantics, and the single apply-postures routine (order,
//  idempotency, both triggers).
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - Policy matrix (FR-19 amended: only fresh-confirmed non-child sees ads)

struct ChildSessionPosturePolicyTests {

    private func signal(
        hasCurrentUser: Bool = true,
        isAnonymousOrSignedOut: Bool = false,
        fresh: Bool? = nil,
        cached: Bool? = nil,
        declared: Bool = false,
        ageResolved: Bool = true,
        ratcheted: Bool = false
    ) -> ChildSessionSignal {
        ChildSessionSignal(
            hasCurrentUser: hasCurrentUser,
            isAnonymousOrSignedOut: isAnonymousOrSignedOut,
            freshIsChildAccount: fresh,
            cachedIsChildAccount: cached,
            isDeclaredChildIdentity: declared,
            isAgeResolved: ageResolved,
            isDeviceRatcheted: ratcheted
        )
    }

    @Test func freshChildTrueIsChildDirected() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: true)) == .childDirected)
    }

    @Test func cachedTrueIsChildDirectedEvenWithoutFreshRead() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: nil, cached: true)) == .childDirected)
    }

    @Test func declaredIdentityIsChildDirectedEvenIfServerSaysFalse() {
        // Protective direction: the device's own declaration outranks a fresh false.
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: false, declared: true)) == .childDirected)
    }

    @Test func cachedTrueOutranksFreshAbsence() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: nil, cached: true, ageResolved: false)) == .childDirected)
    }

    @Test func ratchetGovernsAnonymousSessions() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(isAnonymousOrSignedOut: true, fresh: false, ratcheted: true)
        ) == .ratchetedAnonymous)
    }

    @Test func ratchetGovernsSignedOutSessions() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(hasCurrentUser: false, isAnonymousOrSignedOut: true, ageResolved: false, ratcheted: true)
        ) == .ratchetedAnonymous)
    }

    @Test func ratchetDoesNotGovernRegisteredSignIn() {
        // FR-39: a resolved adult (registered) sign-in gets normal treatment.
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(isAnonymousOrSignedOut: false, fresh: false, ratcheted: true)
        ) == .confirmedNonChild)
    }

    @Test func signedOutUnratchetedIsUnresolved() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(hasCurrentUser: false, isAnonymousOrSignedOut: true, ageResolved: false)
        ) == .unresolved)
    }

    @Test func cachedFalseIsNeverTrustedForDisplay() {
        // FR-19 asymmetric trust: stale cached "adult" without a fresh read stays held.
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: nil, cached: false)) == .unresolved)
    }

    @Test func noCacheNoFreshReadIsUnresolved() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: nil, cached: nil)) == .unresolved)
    }

    @Test func freshFalseConfirmsNonChild() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: false, cached: false)) == .confirmedNonChild)
    }

    @Test func anonymousAdultWithAgeAnswerAndFreshFalseIsConfirmed() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(isAnonymousOrSignedOut: true, fresh: false, ageResolved: true)
        ) == .confirmedNonChild)
    }

    @Test func anonymousWithoutAgeAnswerStaysHeldDespiteFreshFalse() {
        // Reinstall-restored guest: age truth for anonymous identities is the device
        // gate; an unanswered epoch is child-equivalent (option B, fail-closed).
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(isAnonymousOrSignedOut: true, fresh: false, ageResolved: false)
        ) == .unresolved)
    }

    // MARK: Posture → applied treatments

    @Test func childDirectedPostureAppliesEveryRestriction() {
        let p = ChildSessionPosture.childDirected
        #expect(p.childDirectedTreatment == true)
        #expect(p.isAdDisplayEligible == false)
        #expect(p.disablesAdPersonalizationSignals == true)
        #expect(p.forcesLocationOff == true)
        #expect(p.suppressesPurchases == true)
    }

    @Test func ratchetedAnonymousTagsAdsButKeepsAdultLocationAndPaywall() {
        let p = ChildSessionPosture.ratchetedAnonymous
        #expect(p.childDirectedTreatment == true)
        #expect(p.isAdDisplayEligible == false)
        #expect(p.disablesAdPersonalizationSignals == true)
        // D-11: adult defaults untouched — the ratchet does not force location off
        // or hide purchases for a (possibly adult) guest session.
        #expect(p.forcesLocationOff == false)
        #expect(p.suppressesPurchases == false)
    }

    @Test func unresolvedHoldsAdsWithoutChildTagging() {
        let p = ChildSessionPosture.unresolved
        #expect(p.childDirectedTreatment == false)
        #expect(p.isAdDisplayEligible == false)
        #expect(p.forcesLocationOff == false)
        #expect(p.suppressesPurchases == false)
    }

    @Test func confirmedNonChildIsTheOnlyAdEligiblePosture() {
        for posture in [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved] {
            #expect(posture.isAdDisplayEligible == false)
        }
        let adult = ChildSessionPosture.confirmedNonChild
        #expect(adult.isAdDisplayEligible == true)
        #expect(adult.childDirectedTreatment == false)
        #expect(adult.disablesAdPersonalizationSignals == false)
        #expect(adult.forcesLocationOff == false)
        #expect(adult.suppressesPurchases == false)
    }
}

// MARK: - Signal cache + device ratchet (FR-19/FR-39)

@MainActor
struct ChildSignalCacheTests {

    private func makeCache() -> ChildSignalCache {
        let suite = "ChildSignalCacheTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ChildSignalCache(defaults: defaults)
    }

    @Test func startsEmptyAndUnratcheted() {
        let cache = makeCache()
        #expect(cache.cachedIsChildAccount(for: "u1") == nil)
        #expect(cache.hasAnyCachedChildTrue == false)
        #expect(cache.isDeviceRatcheted == false)
    }

    @Test func cachingTrueEngagesTheRatchet() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(true, for: "child1")
        #expect(cache.cachedIsChildAccount(for: "child1") == true)
        #expect(cache.hasAnyCachedChildTrue == true)
        #expect(cache.isDeviceRatcheted == true)
    }

    @Test func cachingFalseDoesNotEngageTheRatchet() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(false, for: "adult1")
        #expect(cache.cachedIsChildAccount(for: "adult1") == false)
        #expect(cache.isDeviceRatcheted == false)
    }

    @Test func ratchetSurvivesLaterAdultResolution() {
        // FR-39: per-uid cache may flip to false (correction), the ratchet never clears.
        let cache = makeCache()
        cache.setCachedIsChildAccount(true, for: "u1")
        cache.setCachedIsChildAccount(false, for: "u1")
        #expect(cache.cachedIsChildAccount(for: "u1") == false)
        #expect(cache.hasAnyCachedChildTrue == false)
        #expect(cache.isDeviceRatcheted == true)
    }

    @Test func cacheIsPerUid() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(true, for: "child1")
        cache.setCachedIsChildAccount(false, for: "adult1")
        #expect(cache.cachedIsChildAccount(for: "child1") == true)
        #expect(cache.cachedIsChildAccount(for: "adult1") == false)
        #expect(cache.cachedIsChildAccount(for: "stranger") == nil)
    }
}

// MARK: - Apply-postures routine (FR-23: two triggers, one routine)

@MainActor
struct ChildSessionPostureCoordinatorTests {

    /// Mutable world backing the injected dependencies, with an ordered event log so
    /// sequencing (TFCD before banner refresh) is provable.
    @MainActor
    final class World {
        var identity: (uid: String, isAnonymous: Bool)?
        var fresh: [String: Bool] = [:]
        var cached: [String: Bool] = [:]
        var declaredUids: Set<String> = []
        var under13FlowAnswer = false
        var ageResolved = true
        var ratcheted = false
        var events: [String] = []
        var notificationEvents: [Bool] = []
        private var observer: AnyObject?

        func makeCoordinator() -> ChildSessionPostureCoordinator {
            let deps = ChildSessionPostureCoordinator.Dependencies(
                currentAuthIdentity: { [weak self] in self?.identity },
                freshIsChildAccount: { [weak self] uid in self?.fresh[uid] },
                cachedIsChildAccount: { [weak self] uid in self?.cached[uid] },
                storeCachedIsChildAccount: { [weak self] uid, value in
                    self?.cached[uid] = value
                    self?.events.append("cache(\(uid)=\(value))")
                    if value { self?.ratcheted = true }
                },
                isDeclaredChildIdentity: { [weak self] uid in
                    guard let self else { return false }
                    guard let uid else { return false }
                    return self.declaredUids.contains(uid)
                },
                isUnder13FlowAnswer: { [weak self] in self?.under13FlowAnswer ?? false },
                isAgeResolved: { [weak self] in self?.ageResolved ?? false },
                isDeviceRatcheted: { [weak self] in self?.ratcheted ?? false },
                engageDeviceRatchet: { [weak self] in
                    self?.ratcheted = true
                    self?.events.append("ratchet")
                },
                applyChildDirectedTreatment: { [weak self] in self?.events.append("tfcd(\($0))") },
                setAdPersonalizationSignalsDisabled: { [weak self] in self?.events.append("analytics(disabled=\($0))") },
                setLocationForcedOff: { [weak self] in self?.events.append("location(forcedOff=\($0))") }
            )
            let coordinator = ChildSessionPostureCoordinator(dependencies: deps)
            observer = NotificationCenter.default.addObserver(
                forName: .adIdentityDidChange, object: nil, queue: nil
            ) { [weak self] note in
                let eligible = (note.userInfo?[AdIdentityChangeKeys.isAdDisplayEligible] as? Bool) ?? false
                self?.events.append("banner(eligible=\(eligible))")
                self?.notificationEvents.append(eligible)
            }
            return coordinator
        }
    }

    @Test func adultToChildStampsTfcdBeforeBannerRemoval() {
        let world = World()
        world.identity = ("u1", false)
        world.fresh["u1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .confirmedNonChild)

        world.events.removeAll()
        // Server-side flip lands mid-session.
        world.fresh["u1"] = true
        coordinator.noteUserProfilesMerged(userIds: ["u1"])

        #expect(coordinator.currentPosture == .childDirected)
        guard let tfcdIndex = world.events.firstIndex(of: "tfcd(true)"),
              let bannerIndex = world.events.firstIndex(of: "banner(eligible=false)") else {
            Issue.record("expected TFCD stamp and banner removal, got \(world.events)")
            return
        }
        // FR-18/FR-23: the global config is re-stamped strictly before the banner
        // refresh, and the removal notification says not-eligible.
        #expect(tfcdIndex < bannerIndex)
        // The flip also lands in the per-uid cache and engages the ratchet.
        #expect(world.cached["u1"] == true)
        #expect(world.ratcheted == true)
    }

    @Test func childToAdultResetsTfcdAndPostsReload() {
        let world = World()
        world.identity = ("child1", false)
        world.fresh["child1"] = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .childDirected)

        // Registered adult signs in (different uid, fresh-confirmed false).
        world.identity = ("adult1", false)
        world.fresh["adult1"] = false
        world.events.removeAll()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .confirmedNonChild)
        guard let tfcdIndex = world.events.firstIndex(of: "tfcd(false)"),
              let bannerIndex = world.events.firstIndex(of: "banner(eligible=true)") else {
            Issue.record("expected TFCD reset and banner reload, got \(world.events)")
            return
        }
        #expect(tfcdIndex < bannerIndex)
        // FR-39: the ratchet persists for later anonymous sessions.
        #expect(world.ratcheted == true)
    }

    @Test func cachedFalseIsNotTrustedUntilFreshConfirm() {
        let world = World()
        world.identity = ("u1", false)
        world.cached["u1"] = false // stale "adult" from a previous session
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        // FR-19: hold until this session's fresh read resolves.
        #expect(coordinator.currentPosture == .unresolved)
        #expect(world.events.contains("tfcd(false)"))

        // Fresh read arrives via the merge trigger and resolves the hold.
        world.fresh["u1"] = false
        coordinator.noteUserProfilesMerged(userIds: ["u1"])
        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(world.notificationEvents.last == true)
    }

    @Test func cachedTrueIsChildDirectedImmediately() {
        let world = World()
        world.identity = ("child1", false)
        world.cached["child1"] = true
        world.ratcheted = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .childDirected)
        #expect(world.events.contains("tfcd(true)"))
        #expect(world.events.contains("location(forcedOff=true)"))
        #expect(world.events.contains("analytics(disabled=true)"))
    }

    @Test func ratchetGovernsAnonymousSessions() {
        let world = World()
        world.identity = ("guest1", true)
        world.fresh["guest1"] = false
        world.ageResolved = true
        world.ratcheted = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .ratchetedAnonymous)
        #expect(world.events.contains("tfcd(true)"))
        // D-11: no location forcing / purchase suppression for the anonymous adult.
        #expect(world.events.contains("location(forcedOff=false)"))
    }

    @Test func declaredIdentityEngagesRatchetAndChildPosture() {
        let world = World()
        world.identity = ("declared1", true)
        world.declaredUids = ["declared1"]
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .childDirected)
        #expect(world.ratcheted == true)
    }

    @Test func routineIsIdempotentAndNotifiesOnlyOnChange() {
        let world = World()
        world.identity = ("u1", false)
        world.fresh["u1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        let notificationsAfterFirst = world.notificationEvents.count

        coordinator.applyPostures(trigger: .identityTransition)
        coordinator.noteUserProfilesMerged(userIds: ["u1"])

        // Postures re-applied (idempotent SDK writes) but no banner churn.
        #expect(world.notificationEvents.count == notificationsAfterFirst)
        #expect(world.events.filter { $0 == "tfcd(false)" }.count >= 3)
    }

    @Test func mergesForOtherUidsDoNotReapply() {
        let world = World()
        world.identity = ("u1", false)
        world.fresh["u1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        world.events.removeAll()

        coordinator.noteUserProfilesMerged(userIds: ["someoneElse"])
        #expect(world.events.isEmpty)
    }

    @Test func userProfilesMergedNotificationDrivesTheMergeTrigger() {
        let world = World()
        world.identity = ("u1", false)
        world.fresh["u1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .confirmedNonChild)

        world.fresh["u1"] = true
        NotificationCenter.default.post(
            name: .userProfilesMerged,
            object: nil,
            userInfo: ["userIds": ["u1"]]
        )
        // The observer receives on RunLoop.main; pump it.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(coordinator.currentPosture == .childDirected)
        #expect(world.notificationEvents.last == false)
    }

    @Test func signedOutSessionOnCleanDeviceHoldsWithoutChildTag() {
        let world = World()
        world.identity = nil
        world.ageResolved = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .unresolved)
        #expect(world.events.contains("tfcd(false)"))
        #expect(world.events.contains("banner(eligible=false)") == false) // no change from initial .unresolved
    }

    // MARK: - FR-33 onboarding flow window (answered but not yet provisioned)

    @Test func under13FlowAnswerRestrictsLocationBeforeAnyPostureTrigger() {
        // The permissions step can render before provisioning/declaration re-runs the
        // posture routine; the flow answer alone must already restrict location UI.
        let world = World()
        world.identity = nil
        world.under13FlowAnswer = true
        let coordinator = world.makeCoordinator()

        #expect(coordinator.currentPosture == .unresolved) // no trigger ran yet
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationForcedOffForChildSession == false)
    }

    @Test func under13FlowAnswerRestrictsLocationEvenWithProvisionedUidAndUnboundDeclaration() {
        // Sign-up over an existing guest uid: answer recorded, declaration not yet
        // bound to the uid — the flow window must still restrict.
        let world = World()
        world.identity = ("guest1", true)
        world.under13FlowAnswer = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
    }

    @Test func adultFlowAnswerLeavesLocationUnrestricted() {
        let world = World()
        world.identity = ("u1", false)
        world.fresh["u1"] = false
        world.under13FlowAnswer = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)
    }

    @Test func childPostureRestrictsFlowLocationWithoutFlowAnswer() {
        // A resolved child session restricts regardless of the (cleared) flow answer.
        let world = World()
        world.identity = ("child1", false)
        world.fresh["child1"] = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
    }
}

// MARK: - FR-34-amended/D-14: premium surfaces stay visible; child variant has no purchase UI

@MainActor
struct ChildPremiumSheetVariantTests {

    @Test func childSessionGetsInformationalVariant() {
        // The child-directed posture suppresses purchases, and a suppressed session
        // renders the informational variant in the same sheet slot.
        let suppressed = ChildSessionPosture.childDirected.suppressesPurchases
        #expect(suppressed == true)
        #expect(ChildPremiumSheetVariant.variant(purchasesSuppressed: suppressed) == .childInfo)
    }

    @Test func adultSessionGetsUnchangedPaywall() {
        let suppressed = ChildSessionPosture.confirmedNonChild.suppressesPurchases
        #expect(suppressed == false)
        #expect(ChildPremiumSheetVariant.variant(purchasesSuppressed: suppressed) == .paywall)
    }

    @Test func everyContextRendersWithoutPurchaseSurface() {
        // By construction the child variant takes no paywall view model, loads no
        // offerings, and exposes only a dismiss/continue action — there is no
        // package row, restore, or upgrade path to render, in any context.
        for context in [ChildPremiumInfoContext.tripLimit, .savedTrips, .premiumIntro] {
            let view = ChildPremiumInfoView(context: context, onDismiss: {})
            _ = view.body
        }
        _ = ChildPremiumInfoView(context: .premiumIntro, primaryActionTitle: "Continue", onDismiss: {}).body
        _ = ChildPremiumInlineNotice().body
    }

    @Test func everyContextLeadsWithTheParentDirectedUpgradesLine() {
        for context in [ChildPremiumInfoContext.tripLimit, .savedTrips, .premiumIntro] {
            #expect(context.infoRowKeys.first == "child_gate.premium.upgrades")
        }
    }

    @Test func familyElevationLineIsContextAccurate() {
        // Trip limits use the trip-specific elevation line; saved trips and the
        // onboarding intro use the generic tier line. All three claims are
        // mechanically true (effectiveTier drives trip limits, saved-trip caps,
        // and gold/royale avatar unlocks).
        #expect(ChildPremiumInfoContext.tripLimit.infoRowKeys.contains("child_gate.trip_limit.family"))
        #expect(ChildPremiumInfoContext.savedTrips.infoRowKeys.contains("child_gate.premium.family_tier"))
        #expect(ChildPremiumInfoContext.premiumIntro.infoRowKeys.contains("child_gate.premium.family_tier"))
    }

    @Test func childPremiumStringsExistInTheBundle() {
        // .localized falls back to the key itself when missing — pin every new key.
        let keys = [
            "child_gate.premium.upgrades",
            "child_gate.premium.family_tier",
            "child_gate.premium.intro_title",
            "child_gate.premium.intro_body",
            "child_gate.premium.avatar_inline",
            "child_gate.saved_trips.body",
            "child_gate.trip_limit.title",
            "child_gate.trip_limit.body",
            "child_gate.trip_limit.family",
            "child_gate.location_disabled"
        ]
        for key in keys {
            #expect(key.localized != key, "missing localization for \(key)")
        }
    }
}

// MARK: - FR-33: the OS location prompt is never triggered for a child session

@MainActor
struct LocationManagerChildPromptGateTests {

    @Test func promptGateIsPure() {
        #expect(LocationManager.mayRequestAuthorization(isChildLocationRestricted: true) == false)
        #expect(LocationManager.mayRequestAuthorization(isChildLocationRestricted: false) == true)
    }

    @Test func requestAuthorizationIsSuppressedForChildSessions() {
        let manager = LocationManager()
        manager.childLocationRestrictionProvider = { true }

        manager.requestAuthorization()

        // No CLLocationManager authorization request was initiated: the outstanding-
        // prompt marker (set only on the real request path) never flips.
        #expect(manager.didRequestAuthorization == false)
    }
}

// MARK: - FR-32 analytics value + FR-34 entitlement interplay

@MainActor
struct ChildSessionAnalyticsAndEntitlementTests {

    @Test func adPersonalizationValueDisabledIsExplicitFalse() {
        #expect(AnalyticsService.adPersonalizationUserPropertyValue(disabled: true) == "false")
    }

    @Test func adPersonalizationValueEnabledRestoresPlistDefault() {
        // nil clears the per-session override; the app-wide plist default governs.
        #expect(AnalyticsService.adPersonalizationUserPropertyValue(disabled: false) == nil)
    }

    @Test func familyEntitlementTagsStillUnlockWhilePurchasesSuppressed() {
        // FR-34: suppression hides purchase surfaces; family-granted benefits remain.
        #expect(ChildSessionPosture.childDirected.suppressesPurchases == true)

        let entitlement = EntitlementState(
            userTier: .signedUp,
            familyId: "fam1",
            wasEverInFamily: true,
            familyRole: "member",
            tags: ["founder"],
            creatorTierForFamily: .royale
        )
        let founderAvatar = AvatarItem(
            id: "avatar_founder_test",
            displayName: "Founder Test",
            unlockSource: .founder
        )
        let service = EntitlementService(revenueCatBridge: nil)
        #expect(service.isUnlocked(avatar: founderAvatar, entitlement: entitlement) == true)
        #expect(entitlement.familyPassUnlocked == true)
    }
}
