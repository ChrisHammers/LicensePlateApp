//
//  ChildDeviceCorrectionTests.swift
//  LicensePlateAppTests
//
//  COPPA F-8 handoff into F-7 (owner-approved): a manager CORRECTION lifts the child
//  device posture; a REVOCATION does not. Both directions are pinned here, because
//  getting the second one wrong would silently un-protect a child who is still a child.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - The rule itself

struct ChildDeviceCorrectionPolicyTests {

    @Test func aFreshExplicitFalseOnADeclaredUidIsACorrection() {
        #expect(
            ChildDeviceCorrectionPolicy.isCorrection(
                freshIsChildAccount: false,
                isFreshValueServerExplicit: true,
                wasDeclaredChildIdentity: true
            )
        )
    }

    @Test func aRevocationIsNotACorrection() {
        // Revocation = membership ended, flag STAYS true (§4 sticky).
        #expect(
            !ChildDeviceCorrectionPolicy.isCorrection(
                freshIsChildAccount: true,
                isFreshValueServerExplicit: true,
                wasDeclaredChildIdentity: true
            )
        )
    }

    @Test func anUnresolvedOrCachedValueIsNeverACorrection() {
        #expect(
            !ChildDeviceCorrectionPolicy.isCorrection(
                freshIsChildAccount: nil,
                isFreshValueServerExplicit: false,
                wasDeclaredChildIdentity: true
            )
        )
    }

    @Test func aFreshFalseOnANeverDeclaredUidChangesNothing() {
        #expect(
            !ChildDeviceCorrectionPolicy.isCorrection(
                freshIsChildAccount: false,
                isFreshValueServerExplicit: true,
                wasDeclaredChildIdentity: false
            )
        )
    }

    /// GAP 1(b), the crux: a document with NO `isChildAccount` key also reads as
    /// `false` under §4, but it is the absence of evidence — never a manager's
    /// decision. Honoring it would let any writer that creates a flagless
    /// `users/{uid}` manufacture a "correction" that erases a real child's lineage
    /// permanently, with nothing able to re-flag the account.
    @Test func anAbsentServerFlagIsNeverACorrection() {
        #expect(
            !ChildDeviceCorrectionPolicy.isCorrection(
                freshIsChildAccount: false,
                isFreshValueServerExplicit: false,
                wasDeclaredChildIdentity: true
            )
        )
    }

    @Test func deviceMarkersLiftOnlyWhenNoLineageRemains() {
        #expect(
            ChildDeviceCorrectionPolicy.liftsDeviceMarkers(
                hasAnyCachedChildTrue: false,
                hasDeclaredChildHistory: false,
                hasOutstandingChildDeclaration: false
            )
        )
        #expect(
            !ChildDeviceCorrectionPolicy.liftsDeviceMarkers(
                hasAnyCachedChildTrue: true,
                hasDeclaredChildHistory: false,
                hasOutstandingChildDeclaration: false
            )
        )
        #expect(
            !ChildDeviceCorrectionPolicy.liftsDeviceMarkers(
                hasAnyCachedChildTrue: false,
                hasDeclaredChildHistory: true,
                hasOutstandingChildDeclaration: false
            )
        )
        // An undelivered declaration for ANY uid outranks a correction for another.
        #expect(
            !ChildDeviceCorrectionPolicy.liftsDeviceMarkers(
                hasAnyCachedChildTrue: false,
                hasDeclaredChildHistory: false,
                hasOutstandingChildDeclaration: true
            )
        )
    }
}

// MARK: - Store-level effects

@MainActor
struct ChildCorrectionStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "ChildCorrectionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func clearingADeclaredUidRemovesOnlyThatIdentity() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "child-1")
        store.markChildDeclarationSent(userId: "child-1")
        store.markChildDeclarationSent(userId: "child-2")

        store.clearDeclaredChildUserId("child-1")

        #expect(!store.isDeclaredChildUserId("child-1"))
        #expect(store.isDeclaredChildUserId("child-2"))
        #expect(store.hasDeclaredChildHistory)
    }

    @Test func clearingAnUnknownUidIsANoOp() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.under13)
        store.markChildDeclarationSent(userId: "child-1")
        let revisionBefore = store.revision

        store.clearDeclaredChildUserId("stranger")
        #expect(store.revision == revisionBefore)
        #expect(store.isDeclaredChildUserId("child-1"))
    }

    @Test func theUnder13AnswerIsDroppedOnlyByTheCorrectionPath() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.under13)
        #expect(store.category == .under13)

        store.clearUnder13AnswerAfterCorrection()
        #expect(store.category == nil)
        #expect(!store.isResolved)
        #expect(!store.hasPendingChildDeclaration)
    }

    /// MERGE DECISION pin (F-6 pending set × F-8 correction): a correction retires only
    /// CONFIRMED declared uids. A uid whose declaration never reached the server keeps
    /// both its obligation and its profile-write hold — otherwise the account this
    /// device knows to be a child gets written out as an adult.
    @Test func aCorrectionNeverDropsAnUndeliveredDeclaration() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "child-undelivered")

        store.clearDeclaredChildUserId("child-undelivered")

        #expect(store.isPendingDeclaration(userId: "child-undelivered") == true)
        #expect(store.hasOutstandingChildDeclaration)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "child-undelivered",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == true)
    }

    /// Fail-closed guard independent of the caller: the device-level answer cannot be
    /// dropped while any declaration is still outstanding.
    @Test func theUnder13AnswerSurvivesWhileADeclarationIsOutstanding() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "child-undelivered")

        store.clearUnder13AnswerAfterCorrection()

        #expect(store.category == .under13)
        #expect(store.isResolved)
    }

    @Test func aTeenAdultAnswerIsLeftAlone() {
        let store = AgeGateStore(defaults: makeDefaults())
        store.recordAnswer(.teenAdult)
        store.clearUnder13AnswerAfterCorrection()
        #expect(store.category == .teenAdult)
    }

    @Test func theRatchetLiftsOnlyThroughTheDedicatedCorrectionCall() {
        let cache = ChildSignalCache(defaults: makeDefaults())
        cache.setCachedIsChildAccount(true, for: "child-1")
        #expect(cache.isDeviceRatcheted)

        // Writing false does NOT lift it (that is the F-7 invariant).
        cache.setCachedIsChildAccount(false, for: "child-1")
        #expect(cache.isDeviceRatcheted)

        cache.clearCachedIsChildAccount(for: "child-1")
        #expect(cache.cachedIsChildAccount(for: "child-1") == nil)
        #expect(cache.isDeviceRatcheted)

        cache.disengageDeviceRatchet()
        #expect(!cache.isDeviceRatcheted)
    }
}

// MARK: - Coordinator behavior (the seam that actually runs on the child's device)

@MainActor
struct ChildCorrectionPostureTests {

    @MainActor
    private final class World {
        var identity: (uid: String, isAnonymous: Bool)?
        var fresh: [String: Bool] = [:]
        /// Uids whose resolution came from a doc that EXPLICITLY carried the key.
        /// Defaults to "explicit" for any uid seeded in `fresh`, so the pre-existing
        /// scenarios below read unchanged; the absent-field case opts out via
        /// `freshFlagAbsent`.
        var freshFlagAbsent: Set<String> = []
        var cached: [String: Bool] = [:]
        var declaredUids: Set<String> = []
        var pendingDeclarationUids: Set<String> = []
        var under13Answer = false
        var ratcheted = false
        var events: [String] = []

        func makeCoordinator() -> ChildSessionPostureCoordinator {
            let deps = ChildSessionPostureCoordinator.Dependencies(
                currentAuthIdentity: { [weak self] in self?.identity },
                freshIsChildAccount: { [weak self] uid in self?.fresh[uid] },
                isFreshChildFlagExplicit: { [weak self] uid in
                    guard let self else { return false }
                    return self.fresh[uid] != nil && !self.freshFlagAbsent.contains(uid)
                },
                cachedIsChildAccount: { [weak self] uid in self?.cached[uid] },
                storeCachedIsChildAccount: { [weak self] uid, value in
                    self?.cached[uid] = value
                    if value { self?.ratcheted = true }
                },
                isDeclaredChildIdentity: { [weak self] uid in
                    guard let self, let uid else { return false }
                    return self.declaredUids.contains(uid)
                        || self.pendingDeclarationUids.contains(uid)
                },
                isUnder13FlowAnswer: { [weak self] in self?.under13Answer ?? false },
                isAgeResolved: { true },
                isDeviceRatcheted: { [weak self] in self?.ratcheted ?? false },
                engageDeviceRatchet: { [weak self] in self?.ratcheted = true },
                clearChildIdentityLineage: { [weak self] uid in
                    self?.declaredUids.remove(uid)
                    self?.cached.removeValue(forKey: uid)
                    self?.events.append("clearLineage(\(uid))")
                },
                hasAnyCachedChildTrue: { [weak self] in self?.cached.values.contains(true) ?? false },
                hasDeclaredChildHistory: { [weak self] in !(self?.declaredUids.isEmpty ?? true) },
                hasConfirmedChildDeclaration: { [weak self] uid in
                    guard let self else { return false }
                    return self.declaredUids.contains(uid)
                        && !self.pendingDeclarationUids.contains(uid)
                },
                hasOutstandingChildDeclaration: { [weak self] in
                    !(self?.pendingDeclarationUids.isEmpty ?? true)
                },
                liftDeviceChildMarkers: { [weak self] in
                    self?.ratcheted = false
                    self?.under13Answer = false
                    self?.events.append("liftDeviceMarkers")
                },
                applyChildDirectedTreatment: { [weak self] in self?.events.append("tfcd(\($0))") },
                setAdPersonalizationSignalsDisabled: { _ in },
                setLocationForcedOff: { [weak self] in self?.events.append("location(forcedOff=\($0))") }
            )
            return ChildSessionPostureCoordinator(dependencies: deps)
        }
    }

    /// A declared child whose parent corrects the record. The child's own device must
    /// stop applying child postures without a reinstall.
    @Test func correctionLiftsTheChildDevice() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1"]
        world.cached["child-1"] = true
        world.under13Answer = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-1"] = true
        coordinator.applyPostures(trigger: .identityTransition)
        #expect(coordinator.currentPosture == .childDirected)

        // Parent corrects; the self-listener delivers the fresh false.
        world.fresh["child-1"] = false
        world.events.removeAll()
        coordinator.noteUserProfilesMerged(userIds: ["child-1"])

        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(world.events.contains("clearLineage(child-1)"))
        #expect(world.events.contains("liftDeviceMarkers"))
        #expect(world.declaredUids.isEmpty)
        #expect(world.cached["child-1"] == nil)
        #expect(world.ratcheted == false)
        #expect(coordinator.isLocationRestrictedForCurrentFlow == false)
        #expect(coordinator.arePurchasesSuppressed == false)
        #expect(coordinator.isAdDisplayEligible)
    }

    /// Revocation: removed from the family, still under 13 — the flag stays true.
    /// Nothing lifts.
    @Test func revocationDoesNotLiftTheChildDevice() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1"]
        world.cached["child-1"] = true
        world.under13Answer = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-1"] = true
        coordinator.applyPostures(trigger: .identityTransition)

        // The membership ended; the sticky flag is still true.
        world.events.removeAll()
        coordinator.noteUserProfilesMerged(userIds: ["child-1"])

        #expect(coordinator.currentPosture == .childDirected)
        #expect(!world.events.contains("liftDeviceMarkers"))
        #expect(world.declaredUids == ["child-1"])
        #expect(world.ratcheted)
        #expect(coordinator.isLocationRestrictedForCurrentFlow)
        #expect(coordinator.arePurchasesSuppressed)
        #expect(!coordinator.isAdDisplayEligible)
    }

    /// A second child still on the device keeps the ratchet engaged even though the
    /// corrected identity's own lineage is retired.
    @Test func deviceMarkersSurviveWhileAnotherChildRemains() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1", "sibling-2"]
        world.cached["child-1"] = true
        world.cached["sibling-2"] = true
        world.under13Answer = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-1"] = false
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(world.events.contains("clearLineage(child-1)"))
        #expect(!world.events.contains("liftDeviceMarkers"))
        #expect(world.ratcheted)
        #expect(world.declaredUids == ["sibling-2"])
    }

    @Test func aNeverDeclaredAdultNeverTriggersTheCorrectionPath() {
        let world = World()
        world.identity = ("adult-1", false)
        world.fresh["adult-1"] = false

        let coordinator = world.makeCoordinator()
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(coordinator.currentPosture == .confirmedNonChild)
        #expect(!world.events.contains { $0.hasPrefix("clearLineage") })
        #expect(!world.events.contains("liftDeviceMarkers"))
    }

    /// GAP 1(b) end-to-end, the round-2 regression: the child's `users/{uid}` was
    /// created WITHOUT `isChildAccount` (a prefs writer, or any non-choke-point writer,
    /// got there first). A server-resolved read of that doc yields `false`, but the key
    /// was never written — so this must NOT be treated as a manager correction. Before
    /// this fix it fired the correction path and permanently erased the device's
    /// under-13 answer and ratchet, with nothing able to re-flag the account.
    @Test func anAbsentServerFlagNeverCorrectsOrLiftsTheDevice() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1"]
        world.cached["child-1"] = true
        world.under13Answer = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        // Fresh SERVER read (not cached, no pending writes) of a doc with NO
        // `isChildAccount` key: §4 resolves it to false for gating.
        world.fresh["child-1"] = false
        world.freshFlagAbsent = ["child-1"]
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(!world.events.contains { $0.hasPrefix("clearLineage") })
        #expect(!world.events.contains("liftDeviceMarkers"))
        #expect(world.declaredUids == ["child-1"])
        #expect(world.ratcheted)
        #expect(world.under13Answer)
        // Lineage intact ⇒ still child-directed, so no ads.
        #expect(coordinator.currentPosture == .childDirected)
        #expect(!coordinator.isAdDisplayEligible)
    }

    /// A uid that only OWES a declaration is not correctable: the server was never told
    /// it is a child, so a `false` there is the missing declaration, not a decision.
    @Test func aUidStillOwingItsDeclarationIsNeverCorrected() {
        let world = World()
        world.identity = ("child-pending", false)
        world.pendingDeclarationUids = ["child-pending"]
        world.under13Answer = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-pending"] = false // explicit false, but declaration never landed
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(!world.events.contains { $0.hasPrefix("clearLineage") })
        #expect(!world.events.contains("liftDeviceMarkers"))
        #expect(world.pendingDeclarationUids == ["child-pending"])
        #expect(coordinator.currentPosture == .childDirected)
        #expect(!coordinator.isAdDisplayEligible)
    }

    /// A genuine correction for one child must not lift the device while a DIFFERENT
    /// uid still owes its declaration.
    @Test func anOutstandingDeclarationElsewhereBlocksTheDeviceLift() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1"]
        world.pendingDeclarationUids = ["sibling-undeclared"]
        world.cached["child-1"] = true
        world.under13Answer = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-1"] = false
        coordinator.applyPostures(trigger: .identityTransition)

        #expect(world.events.contains("clearLineage(child-1)"))
        #expect(!world.events.contains("liftDeviceMarkers"))
        #expect(world.ratcheted)
        #expect(world.under13Answer)
    }

    @Test func correctionIsIdempotent() {
        let world = World()
        world.identity = ("child-1", false)
        world.declaredUids = ["child-1"]
        world.cached["child-1"] = true
        world.ratcheted = true

        let coordinator = world.makeCoordinator()
        world.fresh["child-1"] = false
        coordinator.applyPostures(trigger: .identityTransition)
        coordinator.applyPostures(trigger: .profileMerge)

        #expect(world.events.filter { $0 == "liftDeviceMarkers" }.count == 1)
        #expect(coordinator.currentPosture == .confirmedNonChild)
    }
}

// MARK: - Restricted-state banner (F-8 polish)

@MainActor
struct ChildFamilyPromptBannerStateTests {

    private func makeService(under13: Bool, declaredUid: String?, familyId: String?) -> ChildRestrictedModeService {
        let suite = "ChildFamilyPromptTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let ageStore = AgeGateStore(defaults: defaults)
        if under13 {
            ageStore.recordAnswer(.under13)
            if let declaredUid {
                ageStore.bindPendingDeclaration(toUserId: declaredUid)
                ageStore.markChildDeclarationSent(userId: declaredUid)
            }
        }
        let service = ChildRestrictedModeService(ageGateStore: ageStore, defaults: defaults)
        service.configure(
            currentUserIdProvider: { declaredUid },
            activeFamilyIdProvider: { familyId }
        )
        return service
    }

    @Test func hiddenForAnyoneWhoIsNotARestrictedChild() {
        #expect(
            ChildFamilyPromptPolicy.presentation(
                isRestrictedUnconsentedChild: false,
                hasPresentedFullBanner: false
            ) == .hidden
        )
        #expect(
            ChildFamilyPromptPolicy.presentation(
                isRestrictedUnconsentedChild: false,
                hasPresentedFullBanner: true
            ) == .hidden
        )
    }

    @Test func fullOnFirstAppearanceThenCompactForever() {
        #expect(
            ChildFamilyPromptPolicy.presentation(
                isRestrictedUnconsentedChild: true,
                hasPresentedFullBanner: false
            ) == .full
        )
        #expect(
            ChildFamilyPromptPolicy.presentation(
                isRestrictedUnconsentedChild: true,
                hasPresentedFullBanner: true
            ) == .compact
        )
    }

    @Test func bothVisibleStatesRemainVisible() {
        #expect(ChildFamilyPromptPresentation.full.isVisible)
        #expect(ChildFamilyPromptPresentation.compact.isVisible)
        #expect(!ChildFamilyPromptPresentation.hidden.isVisible)
    }

    @Test func theServiceCollapsesAfterTheFullPresentationIsRecorded() {
        let service = makeService(under13: true, declaredUid: "child-1", familyId: nil)
        #expect(service.isRestrictedUnconsentedChild)
        #expect(service.familyPromptPresentation == .full)

        service.markFullFamilyPromptPresented()
        #expect(service.hasPresentedFullFamilyPrompt)
        #expect(service.familyPromptPresentation == .compact)
    }

    @Test func joiningAFamilyHidesThePromptEvenAfterItWasShown() {
        let consented = makeService(under13: true, declaredUid: "child-1", familyId: "fam-1")
        consented.markFullFamilyPromptPresented()
        #expect(!consented.isRestrictedUnconsentedChild)
        #expect(consented.familyPromptPresentation == .hidden)
    }

    @Test func adultsNeverSeeThePrompt() {
        let adult = makeService(under13: false, declaredUid: "adult-1", familyId: nil)
        #expect(adult.familyPromptPresentation == .hidden)
    }
}
