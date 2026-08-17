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
    /// F-8 device pass wave 2 (2026-08-16): scoped per-member. Wave 1 wired a single
    /// Bool into every row's manage controls, so deleting one child's data spun a
    /// DIFFERENT child's row too whenever two were shown at once. `nil` means no
    /// deletion is in flight; a non-nil value names the one member whose row should
    /// show the "Deleting..." spinner — every other row's destructive controls still
    /// disable (not spin) via `isChildDataDeletionInFlight` while it runs.
    @Published private(set) var deletingChildDataMemberId: String?

    private let familyRepository: FamilyRepository
    private let childStatusService: FamilyChildStatusManaging
    private let analytics: AnalyticsLogging
    private let currentYearProvider: () -> Int
    private let userRepository: UserRepository
    private var authService: FirebaseAuthService
    private var childProjectionObservation: AnyCancellable?
    private(set) var familyId: String = ""
    private var lastSavedFamilyName: String = ""
    /// Fix 3 (2026-08-16) re-entrancy guard — see `refreshMemberIdentitiesIfNeeded()`.
    private var isRefreshingMemberIdentities = false

    var family: Family?

    init(
        familyRepository: FamilyRepository,
        authService: FirebaseAuthService,
        childStatusService: FamilyChildStatusManaging? = nil,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        currentYearProvider: @escaping () -> Int = { Calendar.current.component(.year, from: .now) },
        userRepository: UserRepository = .shared
    ) {
        self.familyRepository = familyRepository
        self.authService = authService
        self.childStatusService = childStatusService ?? familyRepository
        self.analytics = analytics
        self.currentYearProvider = currentYearProvider
        self.userRepository = userRepository
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

    /// Fix 3 (2026-08-16, owner report): "the captain's Family page keeps showing the
    /// old cached values indefinitely — as if it's not updating its source of truth."
    /// Root cause: `UserRepository.getUser` is cache-first and, once a member's
    /// `AppUser` is hydrated, never re-hits Firestore for that id again this session —
    /// so an avatar/username changed elsewhere never reaches an already-open roster.
    /// This forces one fresh read of the currently-known members' user docs via the
    /// repository's existing (non-cache-first) refresh path. Not a listener — the SRS
    /// direction is fetch-refresh for now; a live subscription is a reasonable
    /// follow-up.
    ///
    /// Deliberately kept OUT of `loadData`: that stays a synchronous, SwiftData-only
    /// read so the existing tests that call it directly never touch the network. The
    /// view calls this separately from `.onAppear`. Guarded so overlapping
    /// appearances only run one refresh at a time (resets once the fetch completes, so
    /// the next appearance still refreshes).
    func refreshMemberIdentitiesIfNeeded() {
        guard !isRefreshingMemberIdentities else { return }
        let userIds = Set(members.map(\.userId))
        guard !userIds.isEmpty else { return }

        isRefreshingMemberIdentities = true
        let refreshingFamilyId = familyId
        Task { [weak self] in
            guard let self else { return }
            await self.userRepository.refreshUsersFromFirestoreIfPresent(userIds: userIds)
            if self.familyId == refreshingFamilyId {
                self.publishRefreshedMembers(
                    self.familyRepository.getMembers(familyId: refreshingFamilyId)
                )
            }
            self.isRefreshingMemberIdentities = false
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
                self.publishRefreshedMembers(self.familyRepository.getMembers(familyId: familyId))
            }
    }

    /// The one write point for a roster RE-READ on this sheet. See `FamilyRosterPublishPolicy`
    /// — `isCaptainOrCreator` (and with it every manage control on this screen) is derived
    /// from finding MY row in `members`, so an empty local read must never be published over
    /// a populated roster.
    private func publishRefreshedMembers(_ refreshed: [FamilyMember]) {
        guard FamilyRosterPublishPolicy.shouldPublish(refreshed: refreshed, current: members) else {
            return
        }
        members = refreshed
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

    /// Fix 2 (2026-08-16): the row whose deletion is actually in flight — this is the
    /// only row that should spin.
    func isDeletingChildData(memberId: String) -> Bool {
        deletingChildDataMemberId == memberId
    }

    /// Every OTHER row's destructive controls disable (not spin) while any deletion is
    /// in flight, so two children can never be removed concurrently.
    var isChildDataDeletionInFlight: Bool {
        deletingChildDataMemberId != nil
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
        guard deletingChildDataMemberId == nil else { return }

        deletingChildDataMemberId = target.memberUserId
        errorMessage = nil

        Task {
            do {
                try await childStatusService.requestChildDataDeletion(
                    familyId: familyId,
                    childUserId: target.memberUserId
                )
                analytics.log(.familyMemberRemoved)
                familyRepository.removeLocalMember(familyId: familyId, memberUserId: target.memberUserId)
                deletingChildDataMemberId = nil
                refreshMembers()
            } catch {
                deletingChildDataMemberId = nil
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
