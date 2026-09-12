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
    /// Owner ruling 2026-08-28: members whose email_plus consent still awaits the
    /// guardian's email confirmation (server `consentPending` projection).
    @Published private(set) var consentPendingMemberIds: Set<String> = []
    /// Set-as-child sheet (consent capture, FR-2 set-true / FR-31).
    @Published var childConsentTarget: FamilyChildMemberTarget?
    @Published var childConsentDraft = ChildConsentDraft()
    /// Correction dialog (FR-5): the two enumerated reasons, nothing else.
    @Published var childCorrectionTarget: FamilyChildMemberTarget?
    /// FR-30 final confirmation — the second deliberate step after the §312.6(a)(2)
    /// removal choice (FR-63(a)); the only state the irreversible delete fires from.
    @Published var childDeletionFinalTarget: FamilyChildMemberTarget?
    /// Read-only child-privacy detail (FR-29/FR-61).
    @Published var childPrivacyTarget: FamilyChildMemberTarget?
    /// FR-84 (F-41): the child whose account a guardian is moving to a new device.
    @Published var childDeviceTransferTarget: FamilyChildMemberTarget?
    /// FR-61 ex-member entry: children this account is the recorded guardian for
    /// (server-fed via `listGuardedChildren`; filtered to past members for display).
    @Published private(set) var guardedChildren: [GuardedChildSummary] = []
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
    private var consentPendingObservation: AnyCancellable?
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
        consentPendingMemberIds = familyRepository.memberConsentPendingUserIds[familyId] ?? []
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
        consentPendingObservation?.cancel()
        consentPendingObservation = familyRepository.$memberConsentPendingUserIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pendingByFamily in
                self?.consentPendingMemberIds = pendingByFamily[familyId] ?? []
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

    /// Whether the viewer can remove SOMEONE (server-mirrored: creator or captain).
    var canRemoveMembers: Bool { isCreator || isCaptainOrCreator }

    var isCaptainOrCreator: Bool {
        guard let userId = currentUserId,
              let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.isCaptainOrCreator
    }

    func canRemove(memberId: String) -> Bool {
        guard let member = members.first(where: { $0.userId == memberId }) else { return false }
        return FamilyMemberRemovalPolicy.canRemove(
            actorIsCreator: isCreator,
            actorIsCaptainOrCreator: isCaptainOrCreator,
            currentUserId: currentUserId,
            memberUserId: memberId,
            familyCreatorId: family?.creatorId,
            memberRole: member.roleEnum
        )
    }

    // MARK: - Child status projection & gating (FR-2 / FR-20)

    func isChildMember(memberId: String) -> Bool {
        childMemberIds.contains(memberId)
    }

    func isConsentPendingMember(memberId: String) -> Bool {
        consentPendingMemberIds.contains(memberId)
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
        childConsentDraft.isCompleteForMemberFlag
            && ExpectedAgeOutYearOptions.isValid(
                childConsentDraft.expectedAgeOutYearMonth,
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

    func setChildExpectedAgeOutYearMonth(_ year: Int?) {
        childConsentDraft.expectedAgeOutYearMonth = year
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
                    expectedAgeOutYearMonth: draft.expectedAgeOutYearMonth
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
                    expectedAgeOutYearMonth: nil
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

    // MARK: - Remove and delete child's data (FR-63(a) choice → FR-30 final confirm)

    func cancelChildDataDeletion() {
        childDeletionFinalTarget = nil
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
                // FR-61: deletion removes the guardianship record with the account —
                // drop the past-children row in the same motion.
                refreshGuardedChildren()
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

    // MARK: - Device transfer (FR-84 / F-41)

    /// Open the transfer-code sheet for a child. The same local manage gate as every other
    /// child control; the SERVER re-runs the FR-62 guardianship ladder and the
    /// currently-consented check, so this is a UI affordance, never the authorization.
    func openChildDeviceTransfer(_ target: FamilyChildMemberTarget) {
        guard canManageChildStatus(memberId: target.memberUserId) else { return }
        childDeviceTransferTarget = target
    }

    func loadConsentHistory(childUserId: String) async throws -> ParentalConsentStatus {
        try await childStatusService.getParentalConsentStatus(
            familyId: familyId,
            childUserId: childUserId
        )
    }

    /// FR-61: the live review inventory for the privacy surface.
    func loadChildDataInventory(childUserId: String) async throws -> ChildDataInventory? {
        try await childStatusService.getChildDataInventory(
            familyId: familyId,
            childUserId: childUserId
        )
    }

    // MARK: - Guarded children (FR-61 ex-member entry; FR-62 rights survive removal)

    /// Rows for THIS family whose child is no longer on the roster but whose account
    /// still exists — the "children you've consented for" surface. Current members'
    /// rows are covered by the live roster's own controls.
    var pastGuardedChildren: [GuardedChildSummary] {
        guardedChildren.filter { row in
            row.familyId == familyId
                && row.accountExists
                && !members.contains(where: { $0.userId == row.childUserId })
        }
    }

    /// Best-effort refresh; a failure leaves the previous rows (the section simply
    /// doesn't appear on a cold failure — rights remain reachable next load).
    func refreshGuardedChildren() {
        Task { [weak self] in
            guard let self else { return }
            if let rows = try? await self.childStatusService.listGuardedChildren() {
                self.guardedChildren = rows
            }
        }
    }

    /// Review for an EX-member. Authority is the server's guardianship gate (FR-62);
    /// this row only exists because the server said we are the recorded guardian.
    func openGuardedChildPrivacy(_ row: GuardedChildSummary) {
        childPrivacyTarget = FamilyChildMemberTarget(
            memberUserId: row.childUserId,
            displayName: row.childUserName ?? "Member".localized
        )
    }

    /// FR-63's "delete their data later", delivered: an ex-member deletion arms the
    /// SAME outcome-named final confirmation; the server authorizes the recorded
    /// guardian and the membership-exit half no-ops (FR-62).
    func beginDeleteDataForGuardedChild(_ row: GuardedChildSummary) {
        childDeletionFinalTarget = FamilyChildMemberTarget(
            memberUserId: row.childUserId,
            displayName: row.childUserName ?? "Member".localized
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

    /// Whether the removal dialog must present the §312.6(a)(2) choice (FR-63(a)):
    /// removing a CHILD is a consent revocation, and the parent chooses between
    /// stop-collection-keep-restricted and delete-the-data-now.
    var pendingRemovalIsChild: Bool {
        memberIdPendingRemoval.map(isChildMember(memberId:)) ?? false
    }

    /// FR-63(a): the parent picked deletion in the removal choice. The choice dialog is
    /// the first deliberate step, so this arms the FR-30 FINAL confirmation directly —
    /// the second confirm for an irreversible delete stays, its buttons naming both
    /// outcomes (removal + deletion happen together server-side).
    func chooseDeletionForPendingRemoval() {
        guard let memberId = memberIdPendingRemoval else { return }
        memberIdPendingRemoval = nil
        guard canManageChildStatus(memberId: memberId) else { return }
        guard isChildMember(memberId: memberId) else { return }
        guard let member = members.first(where: { $0.userId == memberId }) else { return }
        childDeletionFinalTarget = childMemberTarget(for: member)
    }

    func removeMember(memberId: String) {
        guard canRemove(memberId: memberId) else {
            errorMessage = "family.member.remove_not_allowed".localized
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
