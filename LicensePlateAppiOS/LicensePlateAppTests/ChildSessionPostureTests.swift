//
//  ChildSessionPostureTests.swift
//  LicensePlateAppTests
//
//  COPPA F-7 (FR-17/18/19/23/32/33/34/39): posture policy matrix, signal cache /
//  device ratchet semantics, and the single apply-postures routine (order,
//  idempotency, both triggers).
//

import Foundation
import Combine
import CoreLocation
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
        // FR-75: the durable child signal is also the only one that rewrites stored flags.
        #expect(p.rewritesStoredLocationFlagsOff == true)
        #expect(p.suppressesPurchases == true)
    }

    @Test func ratchetedAnonymousTagsAdsAndSuppressesPurchasesAndLocation() {
        let p = ChildSessionPosture.ratchetedAnonymous
        #expect(p.childDirectedTreatment == true)
        #expect(p.isAdDisplayEligible == false)
        #expect(p.disablesAdPersonalizationSignals == true)
        // FR-75(c) overturns D-11's location half for the ratchet: a device that has
        // hosted a child does not hand its anonymous session a GPS trail either.
        #expect(p.forcesLocationOff == true)
        // ...but the hold is structural. D-11's real content — "adult defaults stay
        // untouched" — survives: nothing rewrites the stored flags for a guest.
        #expect(p.rewritesStoredLocationFlagsOff == false)
        // FR-57 overturns D-11's purchase half: a device that has hosted a child does
        // not hand its anonymous session to a commerce SDK or a purchase surface.
        #expect(p.suppressesPurchases == true)
    }

    @Test func unresolvedHoldsAdsPurchasesAndLocationWithoutChildTagging() {
        let p = ChildSessionPosture.unresolved
        #expect(p.childDirectedTreatment == false)
        #expect(p.isAdDisplayEligible == false)
        // FR-75(c): no proof of adulthood, no location — the last fail-open asymmetry.
        #expect(p.forcesLocationOff == true)
        // An unresolved session is transient (an offline adult is unresolved all
        // session); its stored preferences must survive it intact.
        #expect(p.rewritesStoredLocationFlagsOff == false)
        // FR-57: no proof of adulthood, no purchase surface.
        #expect(p.suppressesPurchases == true)
    }

    /// FR-75(c) as one statement, over all four postures: `confirmedNonChild` is the only
    /// posture that keeps location, exactly as it is the only one that permits ads and
    /// purchases — and `childDirected` is the only one that touches stored preferences.
    @Test func onlyConfirmedNonChildKeepsLocationAndOnlyChildDirectedRewritesStoredFlags() {
        let all: [ChildSessionPosture] = [.childDirected, .ratchetedAnonymous, .unresolved, .confirmedNonChild]
        for posture in all {
            #expect(
                posture.forcesLocationOff == (posture != .confirmedNonChild),
                "\(posture.rawValue) location hold drifted"
            )
            #expect(
                posture.rewritesStoredLocationFlagsOff == (posture == .childDirected),
                "\(posture.rawValue) stored-flag rewrite drifted"
            )
            // A posture that rewrites the stored flags must also hold structurally;
            // the persisted half can never be the wider of the two.
            if posture.rewritesStoredLocationFlagsOff {
                #expect(posture.forcesLocationOff)
            }
        }
    }

    /// FR-57 as one statement: `confirmedNonChild` is the only posture that permits
    /// purchases, exactly as it is the only one that permits ads.
    @Test func onlyConfirmedNonChildPermitsPurchases() {
        for posture in [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved] {
            #expect(posture.suppressesPurchases == true, "\(posture.rawValue) must suppress purchases")
        }
        #expect(ChildSessionPosture.confirmedNonChild.suppressesPurchases == false)
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

// MARK: - Location trust (FR-75 amendment, owner decision OD-8)

/// The OD-8 truth table. `.unresolved` is the only posture with a way out, and it needs
/// positive local evidence for the current uid AND zero child evidence on the device.
struct ChildLocationTrustPolicyTests {

    /// The seven cache/history states the ruling enumerates, over `.unresolved`.
    private enum Cell: String, CaseIterable {
        case cachedExplicitFalse
        case cachedNonExplicitFalse
        case cacheAbsent
        case cachedTrue
        case ratcheted
        case declaredHistory
        case under13Answer

        /// Only the first earns the trusted-adult branch.
        var trusted: Bool { self == .cachedExplicitFalse }

        /// Which cells are child-EVIDENCED (drive the child copy of the notice).
        var childEvidenced: Bool {
            switch self {
            case .cachedExplicitFalse, .cachedNonExplicitFalse, .cacheAbsent: return false
            case .cachedTrue, .ratcheted, .declaredHistory, .under13Answer: return true
            }
        }

        var inputs: ChildLocationTrustPolicy.Inputs {
            switch self {
            case .cachedExplicitFalse:
                return .init(posture: .unresolved, cachedIsChildAccount: false, isCachedValueServerExplicit: true)
            case .cachedNonExplicitFalse:
                // The document resolved `false` only because the key was ABSENT — §4's
                // effective value, not a server statement. Absence of evidence.
                return .init(posture: .unresolved, cachedIsChildAccount: false, isCachedValueServerExplicit: false)
            case .cacheAbsent:
                // Reinstall / post-sign-out rebirth: nothing local to trust.
                return .init(posture: .unresolved, cachedIsChildAccount: nil, isCachedValueServerExplicit: false)
            case .cachedTrue:
                return .init(
                    posture: .unresolved,
                    cachedIsChildAccount: true,
                    isCachedValueServerExplicit: true,
                    hasAnyCachedChildTrue: true
                )
            case .ratcheted:
                return .init(
                    posture: .unresolved,
                    cachedIsChildAccount: false,
                    isCachedValueServerExplicit: true,
                    isDeviceRatcheted: true
                )
            case .declaredHistory:
                return .init(
                    posture: .unresolved,
                    cachedIsChildAccount: false,
                    isCachedValueServerExplicit: true,
                    hasDeclaredChildHistory: true
                )
            case .under13Answer:
                return .init(
                    posture: .unresolved,
                    cachedIsChildAccount: false,
                    isCachedValueServerExplicit: true,
                    isUnder13FlowAnswer: true
                )
            }
        }
    }

    @Test func unresolvedMatrixTrustsOnlyTheServerExplicitAdultCacheOnACleanDevice() {
        for cell in Cell.allCases {
            let inputs = cell.inputs
            #expect(
                ChildLocationTrustPolicy.trustsCachedAdultForLocation(inputs) == cell.trusted,
                "trust drifted: \(cell.rawValue)"
            )
            #expect(
                ChildLocationTrustPolicy.isLocationRestricted(inputs) == !cell.trusted,
                "restriction drifted: \(cell.rawValue)"
            )
            #expect(
                ChildLocationTrustPolicy.isRestrictionChildEvidenced(inputs) == cell.childEvidenced,
                "evidence drifted: \(cell.rawValue)"
            )
        }
    }

    /// An undelivered declaration is a promise about a specific account; it outranks a
    /// cached adult value exactly as it blocks the F-8 device lift.
    @Test func outstandingDeclarationVetoesTheTrustedCache() {
        let inputs = ChildLocationTrustPolicy.Inputs(
            posture: .unresolved,
            cachedIsChildAccount: false,
            isCachedValueServerExplicit: true,
            hasOutstandingChildDeclaration: true
        )
        #expect(ChildLocationTrustPolicy.trustsCachedAdultForLocation(inputs) == false)
        #expect(ChildLocationTrustPolicy.isLocationRestricted(inputs))
        #expect(ChildLocationTrustPolicy.isRestrictionChildEvidenced(inputs))
    }

    /// The branch is scoped to `.unresolved`. A resolved child, and a ratcheted guest,
    /// are decided by their own evidence and no cache can talk them out of it.
    @Test func noOtherPostureCanEarnTheTrustedBranch() {
        for posture in [ChildSessionPosture.childDirected, .ratchetedAnonymous, .confirmedNonChild] {
            let inputs = ChildLocationTrustPolicy.Inputs(
                posture: posture,
                cachedIsChildAccount: false,
                isCachedValueServerExplicit: true
            )
            #expect(
                ChildLocationTrustPolicy.trustsCachedAdultForLocation(inputs) == false,
                "\(posture.rawValue) must not reach the trusted branch"
            )
            // ...and the answer still tracks the posture: only the confirmed adult is free.
            #expect(ChildLocationTrustPolicy.forcesLocationOff(inputs) == (posture != .confirmedNonChild))
        }
    }

    /// FR-33's flow window is unchanged: an under-13 answer restricts even a session the
    /// posture would otherwise leave alone.
    @Test func under13FlowAnswerStillRestrictsAConfirmedAdultSession() {
        let inputs = ChildLocationTrustPolicy.Inputs(posture: .confirmedNonChild, isUnder13FlowAnswer: true)
        #expect(ChildLocationTrustPolicy.forcesLocationOff(inputs) == false)
        #expect(ChildLocationTrustPolicy.isLocationRestricted(inputs))
        #expect(ChildLocationTrustPolicy.isRestrictionChildEvidenced(inputs))
    }

    /// Every combination of the four device-history markers vetoes the trust, so a new
    /// marker cannot be added and silently ignored.
    @Test func anySingleChildMarkerAnywhereOnTheDeviceVetoesTrust() {
        for ratchet in [true, false] {
            for cachedTrue in [true, false] {
                for declared in [true, false] {
                    for outstanding in [true, false] {
                        let inputs = ChildLocationTrustPolicy.Inputs(
                            posture: .unresolved,
                            cachedIsChildAccount: false,
                            isCachedValueServerExplicit: true,
                            isDeviceRatcheted: ratchet,
                            hasDeclaredChildHistory: declared,
                            hasOutstandingChildDeclaration: outstanding,
                            hasAnyCachedChildTrue: cachedTrue
                        )
                        let clean = !ratchet && !cachedTrue && !declared && !outstanding
                        #expect(
                            ChildLocationTrustPolicy.trustsCachedAdultForLocation(inputs) == clean,
                            "ratchet=\(ratchet) cachedTrue=\(cachedTrue) declared=\(declared) pending=\(outstanding)"
                        )
                    }
                }
            }
        }
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

    // MARK: FR-75 amendment (OD-8): the persisted provenance bit

    @Test func provenanceDefaultsToNotServerExplicit() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(false, for: "adult1")
        #expect(cache.cachedIsChildAccount(for: "adult1") == false)
        // An unstated provenance is never trusted — same reading as "key absent".
        #expect(cache.isCachedValueServerExplicit(for: "adult1") == false)
        #expect(cache.isCachedValueServerExplicit(for: "stranger") == false)
    }

    @Test func provenanceIsRecordedPerUidAndSurvivesOtherWrites() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(false, for: "adult1", isServerExplicit: true)
        cache.setCachedIsChildAccount(false, for: "adult2", isServerExplicit: false)
        #expect(cache.isCachedValueServerExplicit(for: "adult1") == true)
        #expect(cache.isCachedValueServerExplicit(for: "adult2") == false)
    }

    @Test func aLaterUnqualifiedWriteDemotesAPreviouslyExplicitEntry() {
        // Provenance always restates itself, so no stale claim can outlive its value.
        let cache = makeCache()
        cache.setCachedIsChildAccount(false, for: "adult1", isServerExplicit: true)
        cache.setCachedIsChildAccount(false, for: "adult1")
        #expect(cache.isCachedValueServerExplicit(for: "adult1") == false)
    }

    @Test func clearingAUidDropsItsProvenanceToo() {
        let cache = makeCache()
        cache.setCachedIsChildAccount(false, for: "adult1", isServerExplicit: true)
        cache.clearCachedIsChildAccount(for: "adult1")
        #expect(cache.cachedIsChildAccount(for: "adult1") == nil)
        #expect(cache.isCachedValueServerExplicit(for: "adult1") == false)
    }

    @Test func provenancePersistsAcrossInstancesOverTheSameDefaults() {
        // The cache is UserDefaults-backed; a cold start is a new instance over the same
        // store, which is exactly the OD-8 case (offline relaunch).
        let suite = "ChildSignalCacheTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        ChildSignalCache(defaults: defaults).setCachedIsChildAccount(false, for: "adult1", isServerExplicit: true)

        let relaunched = ChildSignalCache(defaults: defaults)
        #expect(relaunched.cachedIsChildAccount(for: "adult1") == false)
        #expect(relaunched.isCachedValueServerExplicit(for: "adult1") == true)
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
        /// Uids whose FRESH resolution came from a document that literally carried
        /// `isChildAccount`. Empty by default; `isFreshChildFlagExplicit` treats any
        /// resolved value as explicit unless the uid is listed in `freshFlagAbsent`.
        var freshFlagAbsent: Set<String> = []
        var cached: [String: Bool] = [:]
        /// FR-75 amendment (OD-8): provenance of the CACHED value, per uid.
        var cachedServerExplicitUids: Set<String> = []
        var declaredUids: Set<String> = []
        var pendingDeclarationUids: Set<String> = []
        var under13FlowAnswer = false
        var ageResolved = true
        var ratcheted = false
        var events: [String] = []
        var notificationEvents: [Bool] = []
        var objectWillChangeCount = 0
        private var observer: AnyObject?
        private var postureSubscription: AnyCancellable?

        func makeCoordinator() -> ChildSessionPostureCoordinator {
            let deps = ChildSessionPostureCoordinator.Dependencies(
                currentAuthIdentity: { [weak self] in self?.identity },
                freshIsChildAccount: { [weak self] uid in self?.fresh[uid] },
                // Any resolved value in this harness stands for an explicit server key
                // unless the uid is listed in `freshFlagAbsent`; the absent-key case is
                // also covered in ChildDeviceCorrectionTests.
                isFreshChildFlagExplicit: { [weak self] uid in
                    guard let self else { return false }
                    return self.fresh[uid] != nil && !self.freshFlagAbsent.contains(uid)
                },
                cachedIsChildAccount: { [weak self] uid in self?.cached[uid] },
                storeCachedIsChildAccount: { [weak self] uid, value, isServerExplicit in
                    self?.cached[uid] = value
                    if isServerExplicit {
                        self?.cachedServerExplicitUids.insert(uid)
                    } else {
                        self?.cachedServerExplicitUids.remove(uid)
                    }
                    self?.events.append("cache(\(uid)=\(value),explicit=\(isServerExplicit))")
                    if value { self?.ratcheted = true }
                },
                isDeclaredChildIdentity: { [weak self] uid in
                    guard let self else { return false }
                    guard let uid else { return false }
                    return self.declaredUids.contains(uid) || self.pendingDeclarationUids.contains(uid)
                },
                isUnder13FlowAnswer: { [weak self] in self?.under13FlowAnswer ?? false },
                isAgeResolved: { [weak self] in self?.ageResolved ?? false },
                isDeviceRatcheted: { [weak self] in self?.ratcheted ?? false },
                engageDeviceRatchet: { [weak self] in
                    self?.ratcheted = true
                    self?.events.append("ratchet")
                },
                clearChildIdentityLineage: { [weak self] uid in
                    self?.declaredUids.remove(uid)
                    self?.cached.removeValue(forKey: uid)
                    self?.cachedServerExplicitUids.remove(uid)
                    self?.events.append("clearLineage(\(uid))")
                },
                hasAnyCachedChildTrue: { [weak self] in self?.cached.values.contains(true) ?? false },
                hasDeclaredChildHistory: { [weak self] in !(self?.declaredUids.isEmpty ?? true) },
                hasConfirmedChildDeclaration: { [weak self] uid in
                    self?.declaredUids.contains(uid) ?? false
                },
                hasOutstandingChildDeclaration: { [weak self] in
                    !(self?.pendingDeclarationUids.isEmpty ?? true)
                },
                liftDeviceChildMarkers: { [weak self] in
                    self?.ratcheted = false
                    self?.under13FlowAnswer = false
                    self?.events.append("liftDeviceMarkers")
                },
                applyChildDirectedTreatment: { [weak self] in self?.events.append("tfcd(\($0))") },
                setAdPersonalizationSignalsDisabled: { [weak self] in self?.events.append("analytics(disabled=\($0))") },
                setLocationForcedOff: { [weak self] in self?.events.append("location(forcedOff=\($0))") },
                releaseDeferredSDKStartups: { [weak self] in self?.events.append("sdkRelease(\($0.rawValue))") },
                isCachedChildFlagServerExplicit: { [weak self] uid in
                    self?.cachedServerExplicitUids.contains(uid) ?? false
                }
            )
            let coordinator = ChildSessionPostureCoordinator(dependencies: deps)
            postureSubscription = coordinator.objectWillChange.sink { [weak self] _ in
                self?.objectWillChangeCount += 1
            }
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
        // FR-75: the STORED flags are not rewritten (D-11 — a possibly-adult guest's
        // saved preferences survive), but the capability is held structurally.
        #expect(world.events.contains("location(forcedOff=false)"))
        #expect(coordinator.isLocationForcedOffForChildSession == true)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
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
        // Post-FR-75(c) the unresolved posture holds location on its own too, so the
        // flow answer is now belt-and-braces for this window rather than its only cover.
        #expect(coordinator.isLocationForcedOffForChildSession == true)
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

    // MARK: - FR-75(b): the synchronous launch pass

    /// The launch pass derives a posture from device-local signals alone — no auth
    /// identity restored yet, no fresh server read possible — and the location hold lands
    /// immediately. This is the exact cell FR-75(c) closes: pre-F-31 a ratcheted
    /// anonymous session at cold start kept full GPS.
    @Test func launchTriggerHoldsLocationFromDeviceRatchetWithNoIdentity() {
        let world = World()
        world.identity = nil              // Firebase has not restored an identity yet
        world.ratcheted = true            // device-local: ChildSignalCache ratchet
        let coordinator = world.makeCoordinator()

        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.currentPosture == .ratchetedAnonymous)
        #expect(coordinator.isLocationForcedOffForChildSession == true)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(world.events.contains("tfcd(true)"))
        // Structural hold only — a possibly-adult guest's stored flags are not rewritten.
        #expect(world.events.contains("location(forcedOff=false)"))
    }

    /// The other launch shape: a cached child signal for the identity Firebase restored
    /// during `configure`, with no fresh read yet.
    @Test func launchTriggerAppliesChildHoldFromCachedSignal() {
        let world = World()
        world.identity = ("child1", false)
        world.cached["child1"] = true
        let coordinator = world.makeCoordinator()

        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.currentPosture == .childDirected)
        #expect(coordinator.isLocationForcedOffForChildSession == true)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(world.events.contains("tfcd(true)"))
        #expect(world.events.contains("location(forcedOff=true)"))
    }

    /// FR-46/FR-58 are unchanged by F-31: the launch pass never releases the deferred SDK
    /// startups `installAtLaunch` just held — a cached signal is not this session's
    /// resolution. The identity transition that follows releases them exactly as before.
    @Test func launchTriggerDoesNotReleaseDeferredSDKStartups() {
        let world = World()
        world.identity = ("u1", false)
        world.cached["u1"] = true
        let coordinator = world.makeCoordinator()

        coordinator.applyPostures(trigger: .launch)
        #expect(coordinator.currentPosture == .childDirected)
        #expect(world.events.contains { $0.hasPrefix("sdkRelease") } == false)

        world.events.removeAll()
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(world.events.contains("sdkRelease(childDirected)"))
    }

    /// Every other trigger still releases, so the skip is scoped to `.launch` alone.
    @Test func everyNonLaunchTriggerReleasesDeferredSDKStartups() {
        for trigger in [ChildSessionPostureCoordinator.Trigger.identityTransition, .profileMerge, .ageResolution] {
            #expect(trigger.releasesDeferredSDKStartups, "\(trigger.rawValue) must still release")
        }
        #expect(ChildSessionPostureCoordinator.Trigger.launch.releasesDeferredSDKStartups == false)
    }

    /// The launch pass is protective only: a device with no child lineage is not
    /// downgraded by it, and a genuine adult still resolves normally on the next trigger.
    @Test func launchTriggerOnCleanDeviceHoldsUnresolvedAndResolvesNormallyAfterwards() {
        let world = World()
        world.identity = ("adult1", false)
        let coordinator = world.makeCoordinator()

        coordinator.applyPostures(trigger: .launch)
        // No fresh read can exist at launch, so FR-19 keeps the session held...
        #expect(coordinator.currentPosture == .unresolved)
        // ...and FR-75(c) means the hold covers location. Crucially it does NOT rewrite
        // the adult's stored flags: only `.childDirected` does that.
        #expect(world.events.contains("location(forcedOff=false)"))
        #expect(coordinator.isLocationForcedOffForChildSession == true)

        world.fresh["adult1"] = false
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(coordinator.isLocationForcedOffForChildSession == false)
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

// MARK: - Shared location-settings fixtures

/// Factory-default privacy flags and an all-on participant pref row — the state a fresh
/// install is in, and the one the pre-F-31 resolver read straight through as `true`.
@MainActor
enum LocationTestSupport {

    static func factoryDefaultPrivacyDefaults() -> UserDefaults {
        let name = "test.FR75.privacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        LocationSettingsBootstrap.registerFactoryDefaults(using: defaults)
        return defaults
    }

    static func allOnPrefsStore(sessionId: UUID, userId: String) -> TripParticipantPrefsStore {
        let name = "test.FR75.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = TripParticipantPrefsStore(defaults: defaults)
        store.apply(
            sessionId: sessionId,
            userId: userId,
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: false,
                saveLocationWhenMarkingPlates: true,
                showMyLocationOnLargeMap: true,
                trackMyLocationDuringTrip: true,
                source: .userEdit
            )
        )
        return store
    }
}

// MARK: - FR-75 amendment (OD-8) at the coordinator seam

/// The offline-adult case the amendment exists for, and the blast radius around it.
@MainActor
struct ChildLocationTrustCoordinatorTests {

    /// An established adult whose device cached a SERVER-EXPLICIT `false` last session
    /// and who now launches offline. `ChildFlagIngestPolicy` rejects the cached Firestore
    /// snapshot, so the session is `.unresolved` all the way through — but location works.
    private func establishedAdultOffline() -> ChildSessionPostureCoordinatorTests.World {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false
        world.cachedServerExplicitUids = ["adult1"]
        return world
    }

    @Test func establishedAdultOfflineKeepsLocation() {
        let world = establishedAdultOffline()
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isLocationForcedOffForChildSession == false)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)
    }

    /// STRICT SCOPE (OD-8): the trusted cache buys LOCATION and nothing else. Every other
    /// posture consequence of `.unresolved` is byte-for-byte what it was before the
    /// amendment — no ads, no purchases, no TFCD stamp, no analytics suppression, no
    /// stored-flag rewrite, and the same deferred-SDK plan.
    @Test func theTrustedCacheChangesLocationAndNothingElse() {
        let world = establishedAdultOffline()
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isAdDisplayEligible == false)
        #expect(coordinator.arePurchasesSuppressed == true)
        // TFCD stays untagged (an unresolved session is display-held, not child-tagged),
        // analytics keeps its normal signals, and no stored location flag is rewritten.
        #expect(world.events.contains("tfcd(false)"))
        #expect(world.events.contains("analytics(disabled=false)"))
        #expect(world.events.contains("location(forcedOff=false)"))
        #expect(world.events.contains("sdkRelease(unresolved)"))
        // ...and the only thing that moved is the location answer.
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)
    }

    /// The same run against an untrusted cache produces an IDENTICAL non-location plan —
    /// proof that the branch is not reachable from any of those code paths.
    @Test func theNonLocationPlanIsIdenticalWithAndWithoutTheTrustedCache() {
        let trusted = establishedAdultOffline()
        let untrusted = ChildSessionPostureCoordinatorTests.World()
        untrusted.identity = ("adult1", false)
        untrusted.cached["adult1"] = false // same value, provenance unknown

        let a = trusted.makeCoordinator()
        let b = untrusted.makeCoordinator()
        a.applyPostures(trigger: .identityTransition)
        b.applyPostures(trigger: .identityTransition)

        #expect(a.currentPosture == b.currentPosture)
        #expect(a.currentPosture == .unresolved)
        // Banner events come from a process-wide notification, so a concurrently running
        // test could land one in either log; everything else is this routine's own work.
        let plan: ([String]) -> [String] = { $0.filter { !$0.hasPrefix("banner(") } }
        #expect(plan(trusted.events) == plan(untrusted.events))
        #expect(a.isAdDisplayEligible == b.isAdDisplayEligible)
        #expect(a.arePurchasesSuppressed == b.arePurchasesSuppressed)
        // The one divergence, by design.
        #expect(a.isLocationRestrictedForCurrentFlow == false)
        #expect(b.isLocationRestrictedForCurrentFlow == true)
    }

    /// The accepted residual: reinstall wipes the cache, so the first offline launch has
    /// no local evidence either way and stays held — with the NEUTRAL copy, because
    /// nothing here says "child".
    @Test func reinstallOfflineStaysRestrictedAndIsNotChildEvidenced() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false) // keychain-restored uid, empty cache
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == false)
    }

    /// A cached `false` whose document never carried the key is the ABSENCE of evidence
    /// (§4's effective value), not a server statement. It stays held.
    @Test func nonServerExplicitCacheEarnsNothing() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == false)
    }

    /// A registered sign-in is exempt from the FR-39 ratchet for POSTURE purposes, so it
    /// can be `.unresolved` on a ratcheted device. The device history still vetoes the
    /// trusted branch, and the copy stays child-specific.
    @Test func ratchetedDeviceVetoesTrustAndKeepsTheChildCopy() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false
        world.cachedServerExplicitUids = ["adult1"]
        world.ratcheted = true
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == true)
    }

    /// Another child on the device (cached true for a different uid) vetoes it too.
    @Test func anotherChildOnTheDeviceVetoesTrust() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false
        world.cached["sibling"] = true
        world.cachedServerExplicitUids = ["adult1", "sibling"]
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == true)
    }

    /// An undelivered declaration for some other uid is child history too.
    @Test func anOutstandingDeclarationVetoesTrust() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false
        world.cachedServerExplicitUids = ["adult1"]
        world.pendingDeclarationUids = ["kid-uid"]
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == true)
    }

    // MARK: Provenance capture at the ingest site

    /// The coordinator is the ONE writer of the per-uid cache, and it now records the
    /// provenance the `ChildFlagIngestPolicy`-gated resolution already knew.
    @Test func freshResolutionsCacheTheirProvenance() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.fresh["adult1"] = false
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(world.cached["adult1"] == false)
        #expect(world.cachedServerExplicitUids.contains("adult1"))
    }

    /// A fresh resolution from a document with NO `isChildAccount` key caches the §4
    /// effective `false` but records it as non-explicit, so the next offline launch
    /// stays held rather than trusting the absence of a key.
    @Test func anAbsentKeyIsCachedAsNotServerExplicit() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.fresh["adult1"] = false
        world.freshFlagAbsent = ["adult1"]
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(world.cached["adult1"] == false)
        #expect(world.cachedServerExplicitUids.contains("adult1") == false)

        // Next launch, offline: nothing to trust.
        world.fresh.removeAll()
        let relaunched = world.makeCoordinator()
        relaunched.applyPostures(trigger: .launch)
        #expect(relaunched.currentPosture == .unresolved)
        #expect(relaunched.isLocationRestrictedForCurrentFlow == true)
    }

    // MARK: Reactivity (F-31 plumbing must carry the new inputs)

    /// A fresh read that contradicts the trusted cache re-publishes and re-restricts.
    @Test func aFreshChildReadContradictingTheCacheReimposesTheRestriction() {
        let world = establishedAdultOffline()
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)

        let publishesBefore = world.objectWillChangeCount
        // Device comes online; the server says this uid IS a child.
        world.fresh["adult1"] = true
        coordinator.noteUserProfilesMerged(userIds: ["adult1"])

        #expect(coordinator.currentPosture == .childDirected)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(coordinator.isLocationRestrictionChildEvidenced == true)
        #expect(world.objectWillChangeCount > publishesBefore)
    }

    /// The projection now depends on more than `currentPosture`, so a run that flips it
    /// while the posture stays `.unresolved` must STILL notify subscribers. (Sign-out to
    /// a signal-less identity: trusted before, nothing to trust after.)
    @Test func aProjectionFlipWithoutAPostureChangeStillRepublishes() {
        let world = establishedAdultOffline()
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)
        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)

        let publishesBefore = world.objectWillChangeCount
        world.identity = nil
        world.ageResolved = false
        coordinator.applyPostures(trigger: .identityTransition)

        // Same posture, opposite location answer — and the change was published.
        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(world.objectWillChangeCount > publishesBefore)
    }

    /// End to end through the real resolver: the flip reaches `EffectiveSettingsResolver`
    /// and an already-running trip stops capturing, with no other input.
    @Test func theResolverSignalRefiresWhenTheTrustedBranchFlips() {
        let world = establishedAdultOffline()
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)

        let sessionId = UUID()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: LocationTestSupport.factoryDefaultPrivacyDefaults(),
            prefsStore: LocationTestSupport.allOnPrefsStore(sessionId: sessionId, userId: "adult1"),
            childRestriction: ChildLocationRestrictionSignal(
                isRestricted: { coordinator.isLocationRestrictedForCurrentFlow },
                changes: coordinator.objectWillChange.eraseToAnyPublisher()
            )
        )
        // Trusted: location resolves ON from the user's own stored preferences.
        #expect(resolver.resolve(sessionId: sessionId, userId: "adult1").trackMyLocationDuringTrips == true)

        // Drain the resolver's init-time deliveries before counting (its prefs/defaults
        // subscriptions each hop RunLoop.main once on attach).
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        var resolverPublishes = 0
        let subscription = resolver.objectWillChange.sink { _ in resolverPublishes += 1 }
        defer { subscription.cancel() }

        world.fresh["adult1"] = true
        coordinator.applyPostures(trigger: .profileMerge)
        // The signal hops RunLoop.main before republishing (same as F-31's wiring).
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        #expect(resolverPublishes > 0)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == true)
        #expect(resolver.resolve(sessionId: sessionId, userId: "adult1").trackMyLocationDuringTrips == false)
    }
}

// MARK: - FR-75 amendment (OD-8): notice copy selection

@MainActor
struct ChildLocationNoticeVariantTests {

    @Test func childEvidencedRestrictionsKeepTheChildCopy() {
        #expect(ChildLocationNoticeVariant.variant(isChildEvidenced: true) == .childAccount)
        #expect(ChildLocationNoticeVariant.childAccount.messageKey == "child_gate.location_disabled")
    }

    @Test func unevidencedRestrictionsUseTheNeutralCopy() {
        #expect(ChildLocationNoticeVariant.variant(isChildEvidenced: false) == .unverifiedSession)
        #expect(ChildLocationNoticeVariant.unverifiedSession.messageKey == "child_gate.location_unverified")
    }

    @Test func theViewRendersTheVariantItWasHanded() {
        #expect(ChildLocationDisabledNotice(isChildEvidenced: true).variant == .childAccount)
        #expect(ChildLocationDisabledNotice(isChildEvidenced: false).variant == .unverifiedSession)
        // The default is the protective one: an un-updated call site over-warns, never
        // under-warns.
        #expect(ChildLocationDisabledNotice().variant == .childAccount)
        _ = ChildLocationDisabledNotice(isChildEvidenced: false).body
        _ = ChildLocationDisabledNotice(isChildEvidenced: true).body
    }

    @Test func bothCopiesAreLocalized() {
        // .localized falls back to the key itself when missing — pin both.
        for key in ["child_gate.location_disabled", "child_gate.location_unverified"] {
            #expect(key.localized != key, "missing localization for \(key)")
        }
        // ...and they must not be the same sentence, or the variant is cosmetic.
        #expect("child_gate.location_disabled".localized != "child_gate.location_unverified".localized)
    }

    /// The whole point: the residual held session is told the truth about ITS situation.
    @Test func theReinstallResidualGetsTheNeutralCopyAndAResolvedChildDoesNot() {
        let held = ChildSessionPostureCoordinatorTests.World()
        held.identity = ("adult1", false)
        let heldCoordinator = held.makeCoordinator()
        heldCoordinator.applyPostures(trigger: .launch)
        #expect(
            ChildLocationNoticeVariant.variant(
                isChildEvidenced: heldCoordinator.isLocationRestrictionChildEvidenced
            ) == .unverifiedSession
        )

        let child = ChildSessionPostureCoordinatorTests.World()
        child.identity = ("child1", false)
        child.cached["child1"] = true
        let childCoordinator = child.makeCoordinator()
        childCoordinator.applyPostures(trigger: .launch)
        #expect(
            ChildLocationNoticeVariant.variant(
                isChildEvidenced: childCoordinator.isLocationRestrictionChildEvidenced
            ) == .childAccount
        )
    }
}

// MARK: - FR-75 launch ordering: cold start captures nothing for a cached child

/// The FR-75 acceptance case end to end, through the real seams: authorized location +
/// factory-default (still `true`) privacy flags + a cached child signal, with only the
/// synchronous launch pass having run. Zero route points, zero discovery coordinates.
@MainActor
struct LaunchTimeLocationHoldTests {

    private final class FakeLocationSource: RouteTrackingLocationSource {
        let subject = PassthroughSubject<CLLocation?, Never>()
        let authorizationSubject = CurrentValueSubject<Bool, Never>(true)
        var locationPublisher: AnyPublisher<CLLocation?, Never> { subject.eraseToAnyPublisher() }
        var locationAuthorizationPublisher: AnyPublisher<Bool, Never> {
            authorizationSubject.eraseToAnyPublisher()
        }
        var isAuthorizedForLocation = true
        private(set) var beginCount = 0
        func beginRouteTracking() { beginCount += 1 }
        func endRouteTracking() {}
    }

    private func makeFactoryDefaultPrivacyDefaults() -> UserDefaults {
        LocationTestSupport.factoryDefaultPrivacyDefaults()
    }

    private func makeAllOnPrefsStore(sessionId: UUID, userId: String) -> TripParticipantPrefsStore {
        LocationTestSupport.allOnPrefsStore(sessionId: sessionId, userId: userId)
    }

    private func signal(
        from coordinator: ChildSessionPostureCoordinator
    ) -> ChildLocationRestrictionSignal {
        // Same wiring as `.live`, against a test-owned coordinator.
        ChildLocationRestrictionSignal(
            isRestricted: { coordinator.isLocationRestrictedForCurrentFlow },
            changes: coordinator.objectWillChange.eraseToAnyPublisher()
        )
    }

    @Test func cachedChildAtColdStartCapturesNothingDespiteFactoryDefaultsAndAuthorization() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("child1", false)
        world.cached["child1"] = true          // ChildSignalCache, survived the last launch
        world.ratcheted = true
        let coordinator = world.makeCoordinator()
        // The ONLY posture work that has happened: the synchronous launch pass.
        coordinator.applyPostures(trigger: .launch)
        #expect(coordinator.currentPosture == .childDirected)

        let sessionId = UUID()
        let privacy = makeFactoryDefaultPrivacyDefaults()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: makeAllOnPrefsStore(sessionId: sessionId, userId: "child1"),
            childRestriction: signal(from: coordinator)
        )

        // The stored flags are untouched and still read `true` — the pre-F-31 resolver
        // would have returned all three on. Enforcement is structural now.
        #expect(privacy.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips) == true)
        let effective = resolver.resolve(sessionId: sessionId, userId: "child1")
        #expect(effective.trackMyLocationDuringTrips == false)
        #expect(effective.saveLocationWhenMarkingPlates == false) // no discovery coordinates
        #expect(effective.showMyLocationOnLargeMap == false)

        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, resolver: resolver)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "child1")

        #expect(service.isCapturing == false)
        #expect(source.beginCount == 0)
        source.subject.send(CLLocation(latitude: 37.7749, longitude: -122.4194))
        #expect(service.routePoints.isEmpty)
    }

    /// FR-75 amendment (OD-8), end to end: the established adult who launches OFFLINE.
    /// The session never resolves (no server read is possible), but the device's
    /// server-explicit cached `false` and its clean history hand location straight back —
    /// route capture runs, from the user's own stored preferences, with no degraded
    /// session and no child-specific copy.
    @Test func establishedAdultOfflineCapturesRouteDespiteNeverResolving() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        world.cached["adult1"] = false            // last session's server-resolved value...
        world.cachedServerExplicitUids = ["adult1"] // ...from a doc that carried the key
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)
        // Offline: FR-19 keeps the session held for ads/purchases all session long.
        #expect(coordinator.currentPosture == .unresolved)
        #expect(coordinator.isAdDisplayEligible == false)
        #expect(coordinator.arePurchasesSuppressed == true)

        let sessionId = UUID()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makeFactoryDefaultPrivacyDefaults(),
            prefsStore: makeAllOnPrefsStore(sessionId: sessionId, userId: "adult1"),
            childRestriction: signal(from: coordinator)
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "adult1")
        #expect(effective.trackMyLocationDuringTrips == true)
        #expect(effective.saveLocationWhenMarkingPlates == true)
        #expect(effective.showMyLocationOnLargeMap == true)

        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, resolver: resolver)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "adult1")
        #expect(service.isCapturing == true)
        #expect(source.beginCount == 1)
        source.subject.send(CLLocation(latitude: 37.7749, longitude: -122.4194))
        #expect(service.routePoints.isEmpty == false)
    }

    /// The adult direction of the same wiring: an `.unresolved` cold start holds location,
    /// and when the fresh read confirms an adult the capability comes back — from the
    /// user's own stored preferences, which the hold never overwrote.
    @Test func adultResolutionAfterLaunchRestoresLocationFromUntouchedStoredPrefs() {
        let world = ChildSessionPostureCoordinatorTests.World()
        world.identity = ("adult1", false)
        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .launch)
        #expect(coordinator.currentPosture == .unresolved)

        let sessionId = UUID()
        let privacy = makeFactoryDefaultPrivacyDefaults()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: makeAllOnPrefsStore(sessionId: sessionId, userId: "adult1"),
            childRestriction: signal(from: coordinator)
        )
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, resolver: resolver)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "adult1")
        #expect(service.isCapturing == false)

        // The fresh `users/{uid}` read lands.
        world.fresh["adult1"] = false
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .confirmedNonChild)

        #expect(resolver.resolve(sessionId: sessionId, userId: "adult1").trackMyLocationDuringTrips == true)
        // The posture change re-publishes the resolver, so an already-active trip picks
        // capture back up without any other input (the change hops RunLoop.main).
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(service.isCapturing == true)
        #expect(source.beginCount == 1)
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
