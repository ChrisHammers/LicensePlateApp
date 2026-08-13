//
//  FamilySettingsViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine

/// A member targeted by a child-management control. `Identifiable` so sheets present
/// through `item:` and keep their identity across member-list refreshes.
struct FamilyChildMemberTarget: Identifiable, Equatable, Sendable {
    let memberUserId: String
    let displayName: String

    var id: String { memberUserId }
}

@MainActor
class FamilySettingsViewModel: ObservableObject {
    @Published var familyName: String = ""
    @Published var members: [FamilyMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showErrorAlert = false
    @Published var isLeavingFamily = false
    @Published var isDeletingFamily = false
    @Published var isSavingName = false
    @Published var isRemovingMember = false
    @Published var didLeaveOrDelete = false
    @Published var memberIdPendingRemoval: String?

    // MARK: Child management (COPPA F-8: FR-2/5/20/29/30)

    /// §7.2 projection mirror, refreshed from the repository — never a stored property
    /// on `FamilyMember` (frozen SwiftData schema, §7.4).
    @Published private(set) var childMemberIds: Set<String> = []
    /// Set-as-child sheet (consent capture, FR-2 set-true / FR-31).
    @Published var childConsentTarget: FamilyChildMemberTarget?
    @Published var childConsentDraft = ChildConsentDraft()
    /// Correction dialog (FR-5): the two enumerated reasons, nothing else.
    @Published var childCorrectionTarget: FamilyChildMemberTarget?
    /// Remove-and-delete (FR-30) — deliberately two steps.
    @Published var childDeletionTarget: FamilyChildMemberTarget?
    @Published var childDeletionFinalTarget: FamilyChildMemberTarget?
    /// Read-only child-privacy detail (FR-29).
    @Published var childPrivacyTarget: FamilyChildMemberTarget?
    @Published private(set) var isSavingChildStatus = false
    @Published private(set) var isDeletingChildData = false

    private let familyRepository: FamilyRepository
    private let childStatusService: FamilyChildStatusManaging
    private let analytics: AnalyticsLogging
    private let currentYearProvider: () -> Int
    private var authService: FirebaseAuthService
    private var childProjectionObservation: AnyCancellable?
    private(set) var familyId: String = ""
    private var lastSavedFamilyName: String = ""

    var family: Family?

    init(
        familyRepository: FamilyRepository,
        authService: FirebaseAuthService,
        childStatusService: FamilyChildStatusManaging? = nil,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        currentYearProvider: @escaping () -> Int = { Calendar.current.component(.year, from: .now) }
    ) {
        self.familyRepository = familyRepository
        self.authService = authService
        self.childStatusService = childStatusService ?? familyRepository
        self.analytics = analytics
        self.currentYearProvider = currentYearProvider
    }

    func setModelContext(_ context: ModelContext) {
        familyRepository.setModelContext(context)
    }

    func setAuthService(_ service: FirebaseAuthService) {
        authService = service
    }

    func loadData(familyId: String) {
        self.familyId = familyId
        family = familyRepository.getFamily(familyId: familyId)
        members = familyRepository.getMembers(familyId: familyId)
        childMemberIds = familyRepository.childMemberIds(familyId: familyId)
        observeChildProjection(familyId: familyId)

        if let family = family {
            familyName = family.name
            lastSavedFamilyName = family.name
        }
    }

    /// The members listener (owned by the dashboard, live while this sheet is up) is the
    /// authority on the server-written `isChild` projection — badges and controls follow
    /// it without this screen issuing its own fetch.
    private func observeChildProjection(familyId: String) {
        childProjectionObservation?.cancel()
        childProjectionObservation = familyRepository.$childMemberFlags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flagsByFamily in
                guard let self else { return }
                self.childMemberIds = Set((flagsByFamily[familyId] ?? [:]).filter { $0.value }.keys)
                self.members = self.familyRepository.getMembers(familyId: familyId)
            }
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    var isCreator: Bool {
        guard let userId = currentUserId else {
            return false
        }
        if let creatorId = family?.creatorId {
            return creatorId == userId
        }
        guard let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.roleEnum == .creator
    }

    var canRemoveMembers: Bool { isCreator }

    var isCaptainOrCreator: Bool {
        guard let userId = currentUserId,
              let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.isCaptainOrCreator
    }

    func canRemove(memberId: String) -> Bool {
        guard canRemoveMembers else { return false }
        guard let userId = currentUserId else { return false }
        return memberId != userId
    }

    // MARK: - Child status projection & gating (FR-2 / FR-20)

    func isChildMember(memberId: String) -> Bool {
        childMemberIds.contains(memberId)
    }

    /// FR-2 mirror of the server's target rules. Reads `isCaptainOrCreator`, which is
    /// derived from the CONFIGURED auth service (`setAuthService` from the view's
    /// environment) — never the throwaway instance the view builds in `init`.
    var canManageChildStatus: Bool {
        isCaptainOrCreator
    }

    func canManageChildStatus(memberId: String) -> Bool {
        guard let member = members.first(where: { $0.userId == memberId }) else { return false }
        return FamilyChildManagePolicy.canManageChildStatus(
            isCaptainOrCreator: isCaptainOrCreator,
            currentUserId: currentUserId,
            memberUserId: memberId,
            familyCreatorId: family?.creatorId,
            memberRole: member.roleEnum
        )
    }

    func childMemberTarget(for member: FamilyMember) -> FamilyChildMemberTarget {
        FamilyChildMemberTarget(
            memberUserId: member.userId,
            displayName: member.user?.displayName ?? "Member".localized
        )
    }

    var expectedAgeOutYearOptions: [Int] {
        ExpectedAgeOutYearOptions.options(currentYear: currentYearProvider())
    }

    // MARK: - Mark as child (FR-2 set-true, FR-31 consent capture)

    func beginMarkAsChild(_ target: FamilyChildMemberTarget) {
        guard canManageChildStatus(memberId: target.memberUserId) else { return }
        childConsentDraft = ChildConsentDraft()
        childConsentTarget = target
    }

    func cancelMarkAsChild() {
        childConsentTarget = nil
        childConsentDraft = ChildConsentDraft()
    }

    /// FR-31: both acknowledgments gate the callable. The server re-checks them.
    var canConfirmMarkAsChild: Bool {
        childConsentDraft.isComplete
            && ExpectedAgeOutYearOptions.isValid(
                childConsentDraft.expectedAgeOutYear,
                currentYear: currentYearProvider()
            )
    }

    func setChildConsentAcknowledged(_ acknowledged: Bool) {
        let wasComplete = childConsentDraft.isComplete
        childConsentDraft.consentAcknowledged = acknowledged
        logConsentAcknowledged(wasComplete: wasComplete)
    }

    func setChildGuardianAffirmed(_ affirmed: Bool) {
        let wasComplete = childConsentDraft.isComplete
        childConsentDraft.guardianAffirmed = affirmed
        logConsentAcknowledged(wasComplete: wasComplete)
    }

    func setChildExpectedAgeOutYear(_ year: Int?) {
        childConsentDraft.expectedAgeOutYear = year
    }

    /// SRS §12: one parent-instance event per completed consent capture, no parameters.
    private func logConsentAcknowledged(wasComplete: Bool) {
        guard !wasComplete, childConsentDraft.isComplete else { return }
        analytics.log(.familyChildConsentAcknowledged)
    }

    func confirmMarkAsChild() {
        guard let target = childConsentTarget, canConfirmMarkAsChild else { return }
        guard requireOnline() else { return }
        guard !isSavingChildStatus else { return }

        let draft = childConsentDraft
        isSavingChildStatus = true
        errorMessage = nil

        Task {
            do {
                try await childStatusService.setChildStatus(
                    familyId: familyId,
                    memberUserId: target.memberUserId,
                    isChild: true,
                    consentAcknowledged: draft.consentAcknowledged,
                    guardianAffirmed: draft.guardianAffirmed,
                    correctionReason: nil,
                    expectedAgeOutYear: draft.expectedAgeOutYear
                )
                analytics.log(
                    .familyChildStatusSet(source: FamilyChildStatusAnalyticsSource.familySettings.rawValue)
                )
                isSavingChildStatus = false
                cancelMarkAsChild()
                refreshMembers()
            } catch {
                isSavingChildStatus = false
                cancelMarkAsChild()
                presentReconcilingMembershipLoss(error, memberId: target.memberUserId)
            }
        }
    }

    // MARK: - Correction (FR-5) — never a withdrawal

    func beginCorrectChildStatus(_ target: FamilyChildMemberTarget) {
        guard canManageChildStatus(memberId: target.memberUserId) else { return }
        childCorrectionTarget = target
    }

    func cancelCorrectChildStatus() {
        childCorrectionTarget = nil
    }

    func applyCorrection(reason: ChildStatusCorrectionReason) {
        guard let target = childCorrectionTarget else { return }
        childCorrectionTarget = nil
        guard requireOnline() else { return }
        guard !isSavingChildStatus else { return }

        isSavingChildStatus = true
        errorMessage = nil

        Task {
            do {
                try await childStatusService.setChildStatus(
                    familyId: familyId,
                    memberUserId: target.memberUserId,
                    isChild: false,
                    consentAcknowledged: false,
                    guardianAffirmed: false,
                    correctionReason: reason,
                    expectedAgeOutYear: nil
                )
                analytics.log(.familyChildStatusCorrected(reason: reason.rawValue))
                isSavingChildStatus = false
                refreshMembers()
            } catch {
                isSavingChildStatus = false
                presentReconcilingMembershipLoss(error, memberId: target.memberUserId)
            }
        }
    }

    // MARK: - Remove and delete child's data (FR-30)

    func beginRemoveAndDeleteChildData(_ target: FamilyChildMemberTarget) {
        guard canManageChildStatus(memberId: target.memberUserId) else { return }
        guard isChildMember(memberId: target.memberUserId) else { return }
        childDeletionTarget = target
    }

    /// Second, deliberate confirmation before an irreversible deletion.
    func advanceToFinalDeletionConfirmation() {
        guard let target = childDeletionTarget else { return }
        childDeletionTarget = nil
        childDeletionFinalTarget = target
    }

    func cancelChildDataDeletion() {
        childDeletionTarget = nil
        childDeletionFinalTarget = nil
    }

    /// Step-1 alert dismissal callback ONLY. SwiftUI runs the tapped button's action
    /// and THEN sets `isPresented = false` — for the "Continue" tap that dismissal
    /// arrives right after `advanceToFinalDeletionConfirmation()` has armed the final
    /// target, so a full `cancelChildDataDeletion()` here would clear it and the
    /// second alert would never present (the FR-30 flow silently dead-ends). Explicit
    /// Cancel buttons keep calling the full cancel.
    func dismissInitialDeletionConfirmation() {
        childDeletionTarget = nil
    }

    func confirmChildDataDeletion() {
        guard let target = childDeletionFinalTarget else { return }
        childDeletionFinalTarget = nil
        guard requireOnline() else { return }
        guard !isDeletingChildData else { return }

        isDeletingChildData = true
        errorMessage = nil

        Task {
            do {
                try await childStatusService.requestChildDataDeletion(
                    familyId: familyId,
                    childUserId: target.memberUserId
                )
                analytics.log(.familyMemberRemoved)
                familyRepository.removeLocalMember(familyId: familyId, memberUserId: target.memberUserId)
                isDeletingChildData = false
                refreshMembers()
            } catch {
                isDeletingChildData = false
                presentReconcilingMembershipLoss(error, memberId: target.memberUserId)
            }
        }
    }

    // MARK: - Child privacy detail (FR-29)

    func openChildPrivacy(_ target: FamilyChildMemberTarget) {
        guard canManageChildStatus(memberId: target.memberUserId) else { return }
        childPrivacyTarget = target
    }

    func loadConsentHistory(childUserId: String) async throws -> ParentalConsentStatus {
        try await childStatusService.getParentalConsentStatus(
            familyId: familyId,
            childUserId: childUserId
        )
    }

    // MARK: - Shared helpers

    /// Re-reads the local projection after a mutation. No extra fetch: the family
    /// members listener started by the dashboard is live while this screen is open and
    /// pushes the server's `isChild` write through `$childMemberFlags` (observed below),
    /// so this is just the immediate, synchronous half.
    private func refreshMembers() {
        members = familyRepository.getMembers(familyId: familyId)
        childMemberIds = familyRepository.childMemberIds(familyId: familyId)
    }

    private func requireOnline() -> Bool {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return false
        }
        return true
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showErrorAlert = true
    }

    func saveFamilyName() {
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            familyName = lastSavedFamilyName
            errorMessage = "Enter family name".localized
            showErrorAlert = true
            return
        }
        guard trimmed != lastSavedFamilyName else { return }
        guard authService.isOnline else {
            familyName = lastSavedFamilyName
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }

        isSavingName = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.updateFamilyName(familyId: familyId, name: trimmed)
                familyName = trimmed
                lastSavedFamilyName = trimmed
                family?.name = trimmed
                isSavingName = false
                AnalyticsService.shared.log(.familyNameChanged)
            } catch {
                familyName = lastSavedFamilyName
                isSavingName = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    func cancelFamilyNameEditing() {
        familyName = lastSavedFamilyName
    }

    func leaveFamily() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }

        isLeavingFamily = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.leaveFamily(familyId: familyId)
                AnalyticsService.shared.log(.familyMemberRemoved)
                isLeavingFamily = false
                didLeaveOrDelete = true
            } catch {
                isLeavingFamily = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    func confirmRemoveMember(memberId: String) {
        guard canRemove(memberId: memberId) else { return }
        memberIdPendingRemoval = memberId
    }

    func cancelRemoveMember() {
        memberIdPendingRemoval = nil
    }

    func removePendingMember() {
        guard let memberId = memberIdPendingRemoval else { return }
        memberIdPendingRemoval = nil
        removeMember(memberId: memberId)
    }

    func removeMember(memberId: String) {
        guard canRemove(memberId: memberId) else {
            errorMessage = "Only the family creator can remove members.".localized
            showErrorAlert = true
            return
        }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        guard !isRemovingMember else { return }

        isRemovingMember = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.removeMember(familyId: familyId, memberId: memberId)
                AnalyticsService.shared.log(.familyMemberRemoved)
                // The server deleted the member doc; reconcile locally in the same motion
                // so the roster can never show a ghost the next action would fail on.
                familyRepository.removeLocalMember(familyId: familyId, memberUserId: memberId)
                refreshMembers()
                isRemovingMember = false
            } catch {
                isRemovingMember = false
                presentReconcilingMembershipLoss(error, memberId: memberId)
            }
        }
    }

    /// Membership-scoped callables answer `not-found` when the target is already gone.
    /// That is a stale-roster signal, not an actionable failure: reconcile and say so.
    private func presentReconcilingMembershipLoss(_ error: Error, memberId: String) {
        guard FamilyMembershipRecoveryPolicy.isAlreadyRemoved(error) else {
            present(error)
            return
        }
        familyRepository.removeLocalMember(familyId: familyId, memberUserId: memberId)
        refreshMembers()
        errorMessage = "family.child.error.already_removed".localized
        showErrorAlert = true
    }

    func deleteFamily() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        guard !isDeletingFamily else { return }

        isDeletingFamily = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.deleteFamily(familyId: familyId)
                try? await authService.refreshCurrentUserFromFirestore()
                let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
                SocialInboxBadgeService.shared.bind(
                    userId: userId,
                    activeFamilyId: authService.currentUser?.activeFamilyId
                )
                AnalyticsService.shared.log(.familyMarkedInactiveCreatorLeftOrDeleted)
                isDeletingFamily = false
                didLeaveOrDelete = true
            } catch {
                isDeletingFamily = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
