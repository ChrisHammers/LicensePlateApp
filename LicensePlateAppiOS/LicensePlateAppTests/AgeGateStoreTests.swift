//
//  AgeGateStoreTests.swift
//  LicensePlateAppTests
//
//  COPPA F-6 (FR-27, flow-scoped rework): age-gate store, derivation, flow-bound
//  declaration lifecycle, profile-write policy, and the age screen view model's
//  minimization contract — including the two owner-reported incident regressions.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AgeGateStoreTests {

    private func makeStore(suite: String = "AgeGateStoreTests-\(UUID().uuidString)") -> (AgeGateStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AgeGateStore(defaults: defaults), defaults)
    }

    // MARK: - Derivation (year-only, D-3)

    @Test func derivationClassifiesBelowThirteenAsChild() {
        #expect(AgeGateStore.category(forBirthYear: 2014, currentYear: 2026) == .under13)
        #expect(AgeGateStore.category(forBirthYear: 2026, currentYear: 2026) == .under13)
        // FR-55: the ambiguous cohort (could be 12 or 13) fails closed to under13.
        #expect(AgeGateStore.category(forBirthYear: 2013, currentYear: 2026) == .under13)
    }

    @Test func derivationClassifiesThirteenOrOlderAsTeenAdult() {
        #expect(AgeGateStore.category(forBirthYear: 1990, currentYear: 2026) == .teenAdult)
        // FR-55: one year past the ambiguous cohort is unambiguously 13+, the boundary's other side.
        #expect(AgeGateStore.category(forBirthYear: 2012, currentYear: 2026) == .teenAdult)
    }

    // MARK: - Persistence

    @Test func startsUnresolved() {
        let (store, _) = makeStore()
        #expect(store.isResolved == false)
        #expect(store.category == nil)
        #expect(store.answeredAt == nil)
        #expect(store.hasPendingChildDeclaration == false)
        #expect(store.pendingDeclarationUserIds.isEmpty)
    }

    @Test func recordAnswerPersistsCategoryAndTimestampOnly() {
        let (store, defaults) = makeStore()
        let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordAnswer(.teenAdult, at: answeredAt)

        #expect(store.isResolved == true)
        #expect(store.category == .teenAdult)
        #expect(store.answeredAt == answeredAt)
        #expect(store.hasPendingChildDeclaration == false)

        // D-3: nothing beyond the derived category / timestamp / declaration
        // bookkeeping is persisted — in particular, no birth year.
        let ageGateKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("ageGate.") }
        #expect(Set(ageGateKeys).isSubset(of: [
            AgeGateStoreKeys.category,
            AgeGateStoreKeys.answeredAt,
            AgeGateStoreKeys.pendingChildDeclaration,
            AgeGateStoreKeys.pendingDeclarationUserIds,
            AgeGateStoreKeys.declaredChildUserIds,
            // FR-60(c): uids retired because the account behind them is gone server-side.
            // Uid bookkeeping like the two above it — still no birth year, still nothing
            // about the answer beyond the derived category.
            AgeGateStoreKeys.detachedIdentityUserIds,
        ]))
    }

    @Test func under13AnswerMarksDeclarationPending() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        #expect(store.category == .under13)
        #expect(store.hasPendingChildDeclaration == true)
        #expect(store.pendingDeclarationUserIds.isEmpty)
    }

    @Test func under13AnswerIsProtectiveDirectionOnly() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.recordAnswer(.teenAdult)
        #expect(store.category == .under13)
    }

    // MARK: - Flow binding (declaration can only target the flow-created uid)

    @Test func bindThenSendClearsThatUidsHoldAndRecordsIt() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-flow-1")
        #expect(store.pendingDeclarationUserIds == ["uid-flow-1"])
        #expect(store.isPendingDeclaration(userId: "uid-flow-1") == true)

        store.markChildDeclarationSent(userId: "uid-flow-1")
        // The uid's own obligation is discharged...
        #expect(store.isPendingDeclaration(userId: "uid-flow-1") == false)
        #expect(store.pendingDeclarationUserIds.isEmpty)
        #expect(store.hasOutstandingChildDeclaration == false)
        // ...but the EPOCH's answer is NOT spent: any further uid this same flow
        // provisions must be declared too (the second-uid defect).
        #expect(store.hasPendingChildDeclaration == true)
        #expect(store.isDeclaredChildUserId("uid-flow-1") == true)
        #expect(store.isDeclaredChildUserId("uid-other") == false)
        #expect(store.isDeclaredChildUserId(nil) == false)
    }

    @Test func bindIsNoOpWithoutAnUnder13Answer() {
        let (store, _) = makeStore()
        store.recordAnswer(.teenAdult)
        store.bindPendingDeclaration(toUserId: "uid-x")
        #expect(store.pendingDeclarationUserIds.isEmpty)
    }

    /// The obligation is a SET: a second uid provisioned inside one epoch binds too,
    /// and binding it must not release the first uid's hold.
    @Test func everyUidProvisionedInOneEpochIsBound() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-guest")
        store.bindPendingDeclaration(toUserId: "uid-registered")

        #expect(store.pendingDeclarationUserIds == ["uid-guest", "uid-registered"])
        store.markChildDeclarationSent(userId: "uid-registered")
        #expect(store.isPendingDeclaration(userId: "uid-guest") == true)
        #expect(store.hasOutstandingChildDeclaration == true)
    }

    // MARK: - Incident regressions (owner device, 2026-08-11)

    /// Incident 1: an existing signed-in captain answered a startup gate under-13 and
    /// the stored answer declared their account a child. The rework makes this
    /// structurally impossible: the profile-write policy takes only the FLOW-BOUND uid
    /// (never the category/answer), so an unbound stale answer can neither hold nor
    /// declare any pre-existing signed-in account.
    @Test func incident1Regression_staleUnder13AnswerNeverHoldsOrTargetsExistingAccount() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13) // stale, unbound answer sitting on the device

        // No flow bound a uid, so NO account's profile write is held — captain included.
        #expect(store.pendingDeclarationUserIds.isEmpty)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "captain-uid",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)

        // And the hold can only ever match the uid a flow explicitly bound.
        store.bindPendingDeclaration(toUserId: "uid-flow-child")
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "captain-uid",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-flow-child",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == true)
    }

    /// Incident 2: after sign-out → new signup, the device-persisted answer silently
    /// carried over and declared the NEW uid a child. Sign-out clears the answer, so
    /// the next registration flow asks fresh; the declared-uid history persists.
    @Test func incident2Regression_clearAnswerResetsFlowStateButKeepsDeclaredHistory() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-old-child")
        store.markChildDeclarationSent(userId: "uid-old-child")
        store.recordAnswer(.under13) // a later stale answer, mid-flow

        store.clearAnswer()

        #expect(store.isResolved == false)
        #expect(store.category == nil)
        #expect(store.answeredAt == nil)
        #expect(store.hasPendingChildDeclaration == false)
        #expect(store.pendingDeclarationUserIds.isEmpty)
        // Uid-bound protective history survives (F-7 ratchet consumes it).
        #expect(store.isDeclaredChildUserId("uid-old-child") == true)
    }

    /// Sign-out ends the epoch, but an UNDELIVERED declaration is a promise about one
    /// specific account and outlives it — otherwise that account's next profile write
    /// would sail through as an adult with no child evidence anywhere.
    @Test func clearAnswerKeepsUndeliveredDeclarationObligations() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-undelivered")

        store.clearAnswer()

        #expect(store.isResolved == false)
        #expect(store.isPendingDeclaration(userId: "uid-undelivered") == true)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-undelivered",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == true)
    }

    /// Pure pins for `GuestProvisioningPolicy`: no NEW anonymous uid without an epoch
    /// answer; ask-sites gate only unprovisioned identities; signed-in sessions never
    /// gate. (The full option-B rebirth narrative lives in
    /// `ChildRestrictedModeServiceTests.signOutRebirth_producesRestrictedGuestNotPrompt`;
    /// the FR-60 under-13 half is `FR60ProvisioningPolicyTests`.)
    @Test func guestProvisioningPolicyMatrix() {
        let (store, _) = makeStore()

        store.recordAnswer(.teenAdult)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == true)

        store.clearAnswer()
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == false)
        #expect(GuestProvisioningPolicy.requiresAgeGate(
            hasFirebaseUid: false, isResolved: store.isResolved
        ) == true)
        #expect(GuestProvisioningPolicy.requiresAgeGate(
            hasFirebaseUid: true, isResolved: store.isResolved
        ) == false)

        // FR-60(a): an under-13 answer records the epoch's obligation but NO LONGER
        // provisions. Share-code entry is the only caller that may (FR-60(b)).
        store.recordAnswer(.under13)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == false)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: store.category, isConsentSeekingRedemption: true
        ) == true)
        #expect(store.hasPendingChildDeclaration == true)
    }

    // MARK: - Profile-write policy

    @Test func profileWriteHeldOnlyForBoundUids() {
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-1", pendingDeclarationUserIds: []
        ) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: nil, pendingDeclarationUserIds: ["uid-1"]
        ) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-2", pendingDeclarationUserIds: ["uid-1"]
        ) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-1", pendingDeclarationUserIds: ["uid-1"]
        ) == true)
        // Every bound uid is held, not just one.
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-2", pendingDeclarationUserIds: ["uid-1", "uid-2"]
        ) == true)
    }

    /// GAP 1(a): the prefs writers share the profile write's hold, so none of them can
    /// be the creator of a flagless `users/{uid}`.
    @Test func everyUserDocWriterHonorsTheSameHold() {
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: "uid-child", pendingDeclarationUserIds: ["uid-child"]
        ) == true)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: "uid-adult", pendingDeclarationUserIds: ["uid-child"]
        ) == false)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: "uid-adult", pendingDeclarationUserIds: []
        ) == false)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: nil, pendingDeclarationUserIds: ["uid-child"]
        ) == false)
    }

    /// FR-19 provenance gate: only a fresh SERVER snapshot may resolve the projection.
    @Test func onlyServerResolvedSnapshotsMayIngestTheChildFlag() {
        #expect(ChildFlagIngestPolicy.mayIngest(isFromCache: false, hasPendingWrites: false) == true)
        #expect(ChildFlagIngestPolicy.mayIngest(isFromCache: true, hasPendingWrites: false) == false)
        #expect(ChildFlagIngestPolicy.mayIngest(isFromCache: false, hasPendingWrites: true) == false)
        #expect(ChildFlagIngestPolicy.mayIngest(isFromCache: true, hasPendingWrites: true) == false)
    }

    // MARK: - View model (SRS §12: shown/completed only, never the answer)

    @Test func viewModelDerivesAndRecordsWithoutLoggingTheAnswer() {
        let (store, _) = makeStore()
        let spy = AnalyticsSpy()
        let vm = AgeGateViewModel(source: .launch, store: store, analytics: spy, currentYear: 2026)

        vm.recordShown()
        vm.recordShown()
        vm.selectedBirthYear = 2014
        #expect(vm.submit() == true)

        #expect(store.category == .under13)
        #expect(store.hasPendingChildDeclaration == true)

        // Exactly one shown + one completed; parameters carry the source only.
        #expect(spy.events.count == 2)
        #expect(spy.events[0].name == "age_gate_shown")
        #expect(spy.events[1].name == "age_gate_completed")
        for event in spy.events {
            let values = (event.parameters ?? [:]).values.map { "\($0)" }
            #expect(!values.contains("2014"))
            #expect(!values.contains("under13"))
            #expect(!values.contains("teen_adult"))
        }
    }

    @Test func viewModelRequiresASelection() {
        let (store, _) = makeStore()
        let spy = AnalyticsSpy()
        let vm = AgeGateViewModel(source: .registration, store: store, analytics: spy, currentYear: 2026)
        #expect(vm.canContinue == false)
        #expect(vm.submit() == false)
        #expect(store.isResolved == false)
    }
}

@MainActor
private final class AnalyticsSpy: AnalyticsLogging {
    var events: [AnalyticsService.Event] = []

    func log(_ event: AnalyticsService.Event) {
        events.append(event)
    }

    func log(_ name: String, parameters: [String: Any]) {}
    func setUserProperty(_ value: String?, forName name: String) {}
}
