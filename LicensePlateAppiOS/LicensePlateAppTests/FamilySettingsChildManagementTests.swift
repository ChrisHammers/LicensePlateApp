//
//  FamilySettingsChildManagementTests.swift
//  LicensePlateAppTests
//
//  COPPA F-8 (FR-2/5/20/29/30): the manage controls' gating and flows.
//  Every dependency is injected — isolated `FamilyRepository`, in-memory store, fake
//  callable service, spy analytics — so nothing here touches a singleton or Firebase.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct FamilySettingsChildManagementTests {

    private struct Harness {
        let viewModel: FamilySettingsViewModel
        let service: MockFamilyChildStatusService
        let analytics: MockAnalyticsService
        let repository: FamilyRepository
        let familyId = "fam-1"
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    private func auth(userId: String?) -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        if let userId {
            auth.currentUser = AppUser(id: userId, userName: userId, firebaseUID: userId)
        }
        return auth
    }

    /// Builds the view model the way `FamilySettings` does: a THROWAWAY auth service in
    /// `init`, then the environment's real one via `setAuthService`.
    private func makeHarness(
        viewerId: String,
        viewerRole: FamilyMember.FamilyRole,
        creatorId: String = "creator",
        extraMembers: [(String, FamilyMember.FamilyRole)] = [("scout", .scout)],
        childMemberIds: Set<String> = [],
        configureAuthService: Bool = true
    ) throws -> Harness {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "fam-1"

        context.insert(Family(familyId: familyId, name: "Hammers", creatorId: creatorId))
        context.insert(FamilyMember(familyId: familyId, userId: creatorId, role: .creator))
        if viewerId != creatorId {
            context.insert(FamilyMember(familyId: familyId, userId: viewerId, role: viewerRole))
        }
        for (userId, role) in extraMembers where userId != viewerId && userId != creatorId {
            context.insert(FamilyMember(familyId: familyId, userId: userId, role: role))
        }
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)
        repository.applyChildMemberFlags(
            Dictionary(uniqueKeysWithValues: childMemberIds.map { ($0, true) }),
            familyId: familyId
        )

        let service = MockFamilyChildStatusService()
        let analytics = MockAnalyticsService()
        let viewModel = FamilySettingsViewModel(
            familyRepository: repository,
            // The throwaway the view builds in `init` — never the real viewer.
            authService: FirebaseAuthService(),
            childStatusService: service,
            analytics: analytics,
            currentYearProvider: { 2026 }
        )
        if configureAuthService {
            viewModel.setAuthService(auth(userId: viewerId))
        }
        viewModel.loadData(familyId: familyId)

        return Harness(viewModel: viewModel, service: service, analytics: analytics, repository: repository)
    }

    private func target(_ id: String, _ name: String = "Sam") -> FamilyChildMemberTarget {
        FamilyChildMemberTarget(memberUserId: id, displayName: name)
    }

    // MARK: - canManageChildStatus uses the CONFIGURED auth service (SRS §14)

    @Test func canManageChildStatusIsFalseWhileOnlyTheThrowawayAuthServiceIsSet() throws {
        // Regression pin: the view builds `FirebaseAuthService()` in `init` and swaps in
        // the environment instance in `onAppear`. Reading the throwaway would report a
        // signed-out viewer forever — or worse, gate off a stale identity.
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            configureAuthService: false
        )
        #expect(harness.viewModel.currentUserId == nil)
        #expect(harness.viewModel.canManageChildStatus == false)
        #expect(harness.viewModel.canManageChildStatus(memberId: "scout") == false)
    }

    @Test func canManageChildStatusFollowsTheConfiguredAuthService() throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        #expect(harness.viewModel.canManageChildStatus)
        #expect(harness.viewModel.canManageChildStatus(memberId: "scout"))

        // Swapping the configured service to a plain member revokes the controls.
        harness.viewModel.setAuthService(auth(userId: "scout"))
        #expect(harness.viewModel.canManageChildStatus == false)
        #expect(harness.viewModel.canManageChildStatus(memberId: "creator") == false)
    }

    @Test func managePolicyRefusesSelfAndCreatorTargets() throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        #expect(!harness.viewModel.canManageChildStatus(memberId: "captain"))
        #expect(!harness.viewModel.canManageChildStatus(memberId: "creator"))
        #expect(!harness.viewModel.canManageChildStatus(memberId: "not-a-member"))
    }

    // MARK: - Child projection (FR-20)

    @Test func childBadgeProjectionComesFromTheRepositoryNotTheModel() throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        #expect(harness.viewModel.isChildMember(memberId: "scout"))
        #expect(!harness.viewModel.isChildMember(memberId: "creator"))
        // §7.4: nothing was written to the frozen SwiftData model.
        #expect(harness.viewModel.members.contains { $0.userId == "scout" })
    }

    // MARK: - Mark as child (FR-2 set-true / FR-31)

    @Test func markAsChildRequiresBothAcknowledgmentsBeforeTheCallable() async throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        let vm = harness.viewModel

        vm.beginMarkAsChild(target("scout"))
        #expect(vm.childConsentTarget != nil)
        #expect(!vm.canConfirmMarkAsChild)

        vm.setChildConsentAcknowledged(true)
        #expect(!vm.canConfirmMarkAsChild)

        vm.setChildGuardianAffirmed(true)
        // Owner ruling 2026-08-28 (manager_set → email_plus): both boxes are no longer
        // enough — an existing member's only age-out source is the turns-13 attestation,
        // so Confirm stays disabled until it is chosen.
        #expect(!vm.canConfirmMarkAsChild)

        vm.setChildExpectedAgeOutYearMonth(203107)
        #expect(vm.canConfirmMarkAsChild)

        // FR-31: the acknowledgment pair is a single parent-instance event.
        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildConsentAcknowledged = event { return true }
            return false
        })

        vm.confirmMarkAsChild()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(harness.service.setChildStatusCalls.count == 1)
        let call = try #require(harness.service.setChildStatusCalls.first)
        #expect(call.isChild)
        #expect(call.consentAcknowledged)
        #expect(call.guardianAffirmed)
        #expect(call.correctionReason == nil)
        #expect(vm.childConsentTarget == nil)
        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildStatusSet(let source) = event { return source == "family_settings" }
            return false
        })
    }

    @Test func markAsChildDoesNothingWithoutConsent() async throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        harness.viewModel.beginMarkAsChild(target("scout"))
        harness.viewModel.setChildConsentAcknowledged(true)
        harness.viewModel.confirmMarkAsChild()
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(harness.service.setChildStatusCalls.isEmpty)
    }

    @Test func markAsChildCarriesTheOptionalAgeOutYear() async throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        let vm = harness.viewModel
        vm.beginMarkAsChild(target("scout"))
        vm.setChildConsentAcknowledged(true)
        vm.setChildGuardianAffirmed(true)
        vm.setChildExpectedAgeOutYearMonth(203103)
        #expect(vm.expectedAgeOutYearOptions.first == 2026)
        vm.confirmMarkAsChild()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(harness.service.setChildStatusCalls.first?.expectedAgeOutYearMonth == 203103)
    }

    @Test func markAsChildIsRefusedForNonManageableTargets() {
        let harness = try? makeHarness(viewerId: "captain", viewerRole: .captain)
        harness?.viewModel.beginMarkAsChild(target("creator"))
        #expect(harness?.viewModel.childConsentTarget == nil)
    }

    @Test func cancellingClearsAnyCapturedConsent() throws {
        let harness = try makeHarness(viewerId: "captain", viewerRole: .captain)
        let vm = harness.viewModel
        vm.beginMarkAsChild(target("scout"))
        vm.setChildConsentAcknowledged(true)
        vm.setChildGuardianAffirmed(true)
        vm.cancelMarkAsChild()
        #expect(vm.childConsentTarget == nil)
        #expect(vm.childConsentDraft == ChildConsentDraft())

        // Re-opening starts clean — a previous session's consent can never be reused.
        vm.beginMarkAsChild(target("scout"))
        #expect(!vm.canConfirmMarkAsChild)
    }

    // MARK: - Correction (FR-5)

    @Test func correctionOffersExactlyTheTwoEnumeratedReasons() {
        #expect(ChildStatusCorrectionReason.allCases.count == 2)
        #expect(ChildStatusCorrectionReason.allCases.contains(.flagSetInError))
        #expect(ChildStatusCorrectionReason.allCases.contains(.childTurned13))
    }

    @Test func applyingACorrectionSendsTheReasonAndNoConsent() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        let vm = harness.viewModel

        vm.beginCorrectChildStatus(target("scout"))
        #expect(vm.childCorrectionTarget != nil)

        vm.applyCorrection(reason: .childTurned13)
        try await Task.sleep(nanoseconds: 50_000_000)

        let call = try #require(harness.service.setChildStatusCalls.first)
        #expect(call.isChild == false)
        #expect(call.correctionReason == .childTurned13)
        #expect(call.consentAcknowledged == false)
        #expect(call.guardianAffirmed == false)
        #expect(vm.childCorrectionTarget == nil)
        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildStatusCorrected(let reason) = event { return reason == "child_turned_13" }
            return false
        })
    }

    @Test func cancellingTheCorrectionDialogSendsNothing() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        harness.viewModel.beginCorrectChildStatus(target("scout"))
        harness.viewModel.cancelCorrectChildStatus()
        harness.viewModel.applyCorrection(reason: .flagSetInError)
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(harness.service.setChildStatusCalls.isEmpty)
    }

    // MARK: - Remove a child: FR-63(a) choice → FR-30 final confirm

    /// FR-63(a), owner finding 2026-08-29: the manage control was delete-only while
    /// §312.6(a)(2) requires offering stop-collection-without-deletion on every
    /// revocation surface a parent actually uses. Its entry now routes through
    /// `confirmRemoveMember` — the SAME three-way choice swipe-Remove presents —
    /// with captain authority included (server-mirrored removal policy).
    @Test func manageControlEntryArmsTheSameRemovalChoiceAsSwipe() throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        let vm = harness.viewModel

        #expect(vm.canRemove(memberId: "scout"))
        vm.confirmRemoveMember(memberId: "scout")
        #expect(vm.memberIdPendingRemoval == "scout")
        #expect(vm.pendingRemovalIsChild)
        // The choice alone arms no deletion — keep-their-data stays a plain removal.
        #expect(vm.childDeletionFinalTarget == nil)
    }

    @Test func deletionRequiresTheChoiceAndTheFinalConfirmation() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        let vm = harness.viewModel

        vm.confirmRemoveMember(memberId: "scout")
        #expect(vm.pendingRemovalIsChild)
        #expect(vm.childDeletionFinalTarget == nil)

        // Confirming while only the choice dialog is up must not delete anything.
        vm.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(harness.service.deletionCalls.isEmpty)

        vm.chooseDeletionForPendingRemoval()
        #expect(vm.memberIdPendingRemoval == nil)
        #expect(vm.childDeletionFinalTarget != nil)

        vm.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(harness.service.deletionCalls == [
            MockFamilyChildStatusService.DeletionCall(familyId: "fam-1", childUserId: "scout")
        ])
        #expect(vm.childDeletionFinalTarget == nil)
    }

    /// Owner regression class (2026-08-12 step-8 retest, re-pinned for the FR-63(a)
    /// shape): SwiftUI dismisses an alert AFTER running the tapped button's action — so
    /// right after the choice's delete button arms the final target, the choice alert's
    /// `isPresented` binding fires `set(false)`, which routes to `cancelRemoveMember()`.
    /// That dismissal must clear only its own pending-removal state, never the
    /// just-armed final confirmation, or the second alert silently never presents.
    /// This walks the exact UI callback sequence.
    @Test func choiceDismissalAfterPickingDeleteDoesNotKillTheFinalConfirmation() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        let vm = harness.viewModel

        vm.confirmRemoveMember(memberId: "scout")
        // User taps "Remove & delete their data": action runs first…
        vm.chooseDeletionForPendingRemoval()
        // …then SwiftUI dismisses the choice alert via the isPresented binding.
        vm.cancelRemoveMember()

        // The final confirmation must still be armed (the second alert presents).
        #expect(vm.childDeletionFinalTarget != nil)

        vm.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(harness.service.deletionCalls == [
            MockFamilyChildStatusService.DeletionCall(familyId: "fam-1", childUserId: "scout")
        ])
    }

    @Test func deletionCanBeCancelledAtEitherStep() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        let vm = harness.viewModel

        vm.confirmRemoveMember(memberId: "scout")
        vm.cancelRemoveMember()
        #expect(vm.memberIdPendingRemoval == nil)
        #expect(vm.childDeletionFinalTarget == nil)

        // "Keep them in the family" on the final confirm: the child stays — nothing
        // was requested yet.
        vm.confirmRemoveMember(memberId: "scout")
        vm.chooseDeletionForPendingRemoval()
        vm.cancelChildDataDeletion()
        #expect(vm.childDeletionFinalTarget == nil)

        vm.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(harness.service.deletionCalls.isEmpty)
    }

    @Test func deletionIsOnlyArmedForFlaggedChildren() {
        // FR-30 targets `isChildAccount == true` members; the server rejects anyone
        // else. An adult's removal dialog is plain Remove — a stray delete-choice call
        // arms nothing and just closes the dialog.
        let harness = try? makeHarness(viewerId: "captain", viewerRole: .captain)
        harness?.viewModel.confirmRemoveMember(memberId: "scout")
        #expect(harness?.viewModel.pendingRemovalIsChild == false)
        harness?.viewModel.chooseDeletionForPendingRemoval()
        #expect(harness?.viewModel.childDeletionFinalTarget == nil)
        #expect(harness?.viewModel.memberIdPendingRemoval == nil)
    }

    @Test func deletionFailureSurfacesAnErrorAndKeepsTheMember() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        harness.service.deletionError = NSError(
            domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "nope"]
        )
        harness.viewModel.confirmRemoveMember(memberId: "scout")
        harness.viewModel.chooseDeletionForPendingRemoval()
        harness.viewModel.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(harness.viewModel.showErrorAlert)
        #expect(harness.viewModel.errorMessage == "nope")
    }

    /// F-8 device pass wave 2 (2026-08-16) regression: wave 1 wired a single
    /// `isDeletingChildData` Bool into every row's controls, so deleting ONE child's
    /// data showed the "Deleting..." spinner on a DIFFERENT child's row too. The
    /// scoping must be per-member: only the targeted row spins. Every row's
    /// destructive controls still disable while any deletion is in flight — this pins
    /// that OTHER rows disable (`isChildDataDeletionInFlight`) without spinning
    /// (`isDeletingChildData(memberId:)`).
    @Test func deletionSpinnerIsScopedToTheMemberBeingDeletedNotEveryRow() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            extraMembers: [("scout", .scout), ("scout2", .scout)],
            childMemberIds: ["scout", "scout2"]
        )
        let vm = harness.viewModel

        vm.confirmRemoveMember(memberId: "scout")
        vm.chooseDeletionForPendingRemoval()
        vm.confirmChildDataDeletion()

        // Synchronous, pre-Task state: `deletingChildDataMemberId` is set before the
        // callable's Task is even created, so this is deterministic without waiting.
        #expect(vm.isDeletingChildData(memberId: "scout"))
        #expect(!vm.isDeletingChildData(memberId: "scout2"))
        // ...but the sibling row's controls still disable (not spin) meanwhile.
        #expect(vm.isChildDataDeletionInFlight)

        try await Task.sleep(nanoseconds: 50_000_000)

        // Both flags clear once the callable resolves — no row is stuck busy forever.
        #expect(!vm.isDeletingChildData(memberId: "scout"))
        #expect(!vm.isChildDataDeletionInFlight)
        #expect(harness.service.deletionCalls == [
            MockFamilyChildStatusService.DeletionCall(familyId: "fam-1", childUserId: "scout")
        ])
    }

    /// The scoping fix must not reopen the door to two concurrent deletions: a second
    /// child's deletion, confirmed while the first is still in flight, is refused —
    /// single-flight, just correctly attributed to the row actually running.
    @Test func aSecondDeletionIsRefusedWhileAnotherIsInFlight() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            extraMembers: [("scout", .scout), ("scout2", .scout)],
            childMemberIds: ["scout", "scout2"]
        )
        let vm = harness.viewModel

        vm.confirmRemoveMember(memberId: "scout")
        vm.chooseDeletionForPendingRemoval()
        vm.confirmChildDataDeletion()
        #expect(vm.isDeletingChildData(memberId: "scout"))

        vm.confirmRemoveMember(memberId: "scout2")
        vm.chooseDeletionForPendingRemoval()
        vm.confirmChildDataDeletion()

        // Refused: the in-flight member id is unchanged, and scout2 never shows busy.
        #expect(vm.isDeletingChildData(memberId: "scout"))
        #expect(!vm.isDeletingChildData(memberId: "scout2"))

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(harness.service.deletionCalls == [
            MockFamilyChildStatusService.DeletionCall(familyId: "fam-1", childUserId: "scout")
        ])
    }

    // MARK: - Child privacy (FR-29)

    @Test func childPrivacyOpensOnlyForManageableMembersAndLoadsHistory() async throws {
        let harness = try makeHarness(
            viewerId: "captain",
            viewerRole: .captain,
            childMemberIds: ["scout"]
        )
        harness.service.consentStatusResult = ParentalConsentStatus(records: [
            ParentalConsentRecord(
                id: "1",
                eventType: .granted,
                rawEventType: ParentalConsentEventType.granted.rawValue,
                createdAt: Date(timeIntervalSince1970: 100),
                correctionReason: nil,
                guardianAffirmed: true,
                expectedAgeOutYearMonth: nil
            )
        ])

        harness.viewModel.openChildPrivacy(target("creator"))
        #expect(harness.viewModel.childPrivacyTarget == nil)

        harness.viewModel.openChildPrivacy(target("scout"))
        #expect(harness.viewModel.childPrivacyTarget?.memberUserId == "scout")

        let status = try await harness.viewModel.loadConsentHistory(childUserId: "scout")
        #expect(status.records.count == 1)
        #expect(harness.service.consentStatusCalls.first?.familyId == "fam-1")
    }
}

// MARK: - Child privacy view model (FR-29 graceful degradation)

@MainActor
struct FamilyChildPrivacyViewModelTests {

    @Test func loadsAndSortsHistoryNewestFirst() async {
        let older = ParentalConsentRecord(
            id: "1", eventType: .declared, rawEventType: "AUDIT_CHILD_REGISTRATION_DECLARED",
            createdAt: Date(timeIntervalSince1970: 100), correctionReason: nil,
            guardianAffirmed: nil, expectedAgeOutYearMonth: nil
        )
        let newer = ParentalConsentRecord(
            id: "2", eventType: .granted, rawEventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
            createdAt: Date(timeIntervalSince1970: 900), correctionReason: nil,
            guardianAffirmed: true, expectedAgeOutYearMonth: nil
        )
        let viewModel = FamilyChildPrivacyViewModel(
            loadConsentHistory: { _ in ParentalConsentStatus(records: [older, newer]) }
        )

        await viewModel.load(childUserId: "child-1")
        #expect(viewModel.historyState == .loaded([older, newer]))
        #expect(viewModel.recordsNewestFirst.map(\.id) == ["2", "1"])
    }

    @Test func aCallableFailureDegradesInsteadOfBlockingReview() async {
        let viewModel = FamilyChildPrivacyViewModel(
            loadConsentHistory: { _ in throw NSError(domain: "test", code: 7) }
        )
        await viewModel.load(childUserId: "child-1")
        #expect(viewModel.historyState == .unavailable)
        #expect(viewModel.recordsNewestFirst.isEmpty)
    }

    @Test func loadRunsOnlyOnce() async {
        var calls = 0
        let viewModel = FamilyChildPrivacyViewModel(
            loadConsentHistory: { _ in
                calls += 1
                return ParentalConsentStatus(records: [])
            }
        )
        await viewModel.load(childUserId: "child-1")
        await viewModel.load(childUserId: "child-1")
        #expect(calls == 1)
    }
}
