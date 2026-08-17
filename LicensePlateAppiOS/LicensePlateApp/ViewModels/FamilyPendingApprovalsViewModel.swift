//
//  FamilyPendingApprovalsViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class FamilyPendingApprovalsViewModel: ObservableObject {
    let familyId: String

    @Published var pendingRequests: [PendingJoinRequest] = []
    @Published var errorMessage: String?
    @Published var showError = false
    @Published private(set) var busyRequestId: String?
    @Published private(set) var busyKind: InviteBusyKind?
    @Published private(set) var processedRequestIds: Set<String> = []

    /// COPPA FR-1/FR-25 approval-time child declaration, one draft per pending request.
    @Published private(set) var childTargetStates: [String: ChildApprovalTargetState] = [:]
    @Published private(set) var childDrafts: [String: ChildApprovalDraft] = [:]

    var isProcessing: Bool { busyRequestId != nil }

    /// Firebase-touching seams, isolated so the declaration state machine is testable
    /// without the network (same idiom as `ChildSessionPostureCoordinator.Dependencies`).
    struct Dependencies {
        /// Fresh read of a pending target's `isChildAccount`; `nil` = unreadable.
        var resolveIsChildAccount: (String) async -> Bool?
        var respondToPendingRequest: (
            _ familyId: String,
            _ requestId: String,
            _ approve: Bool,
            _ declaration: ChildApprovalDraft?
        ) async throws -> Void
        var fetchPendingRequests: (String) async throws -> [PendingJoinRequest]

        @MainActor
        static func live(
            familyRepository: FamilyRepository,
            userRepository: UserRepository
        ) -> Dependencies {
            Dependencies(
                resolveIsChildAccount: { await userRepository.fetchIsChildAccount(userId: $0) },
                respondToPendingRequest: { familyId, requestId, approve, declaration in
                    try await familyRepository.respondToPendingRequest(
                        familyId: familyId,
                        requestId: requestId,
                        approve: approve,
                        childDeclaration: declaration
                    )
                },
                fetchPendingRequests: { try await familyRepository.fetchPendingRequests(familyId: $0) }
            )
        }
    }

    private var authService: FirebaseAuthService?
    private var pendingObservation: AnyCancellable?
    private let familyRepository: FamilyRepository
    private let userRepository: UserRepository
    private let analytics: AnalyticsLogging
    private let deps: Dependencies

    init(
        familyId: String,
        familyRepository: FamilyRepository = .shared,
        userRepository: UserRepository = .shared,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        dependencies: Dependencies? = nil
    ) {
        self.familyId = familyId
        self.familyRepository = familyRepository
        self.userRepository = userRepository
        self.analytics = analytics
        self.deps = dependencies ?? .live(
            familyRepository: familyRepository,
            userRepository: userRepository
        )
    }

    func isBusy(requestId: String, kind: InviteBusyKind) -> Bool {
        busyRequestId == requestId && busyKind == kind
    }

    func isRowDisabled(requestId: String) -> Bool {
        processedRequestIds.contains(requestId) || busyRequestId == requestId
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
        userRepository.setModelContext(modelContext)
    }

    func onAppear() {
        loadPendingRequests()
        startObservingPendingRequests()
    }

    func onDisappear() {
        pendingObservation?.cancel()
        pendingObservation = nil
    }

    func refreshPendingRequests() async {
        do {
            let linked = try await deps.fetchPendingRequests(familyId)
            pendingRequests = linked.filter { $0.statusEnum == .pending }
        } catch {
            loadPendingRequests()
        }
        await resolveChildTargetStates()
    }

    /// FR-86 render projection for the approve screen (device pass 2026-08-17). The stamp is
    /// parsed at decode and published by the repository beside the rows — it cannot live on
    /// `PendingJoinRequest` itself (frozen V1 schema), and as a `@Transient` it never
    /// survived the `getPendingRequests` fetch the rows actually come from. `nil` keeps the
    /// existing generic-placeholder fallback.
    func identityStamp(for request: PendingJoinRequest) -> PendingIdentityStamp? {
        familyRepository.pendingIdentityStamp(
            familyId: request.familyId,
            requestId: request.requestId
        )
    }

    // MARK: - Child declaration (FR-1 / FR-25)

    func childTargetState(for request: PendingJoinRequest) -> ChildApprovalTargetState {
        childTargetStates[request.requestId] ?? .unknown
    }

    func childDraft(for request: PendingJoinRequest) -> ChildApprovalDraft {
        childDrafts[request.requestId] ?? .initial(for: childTargetState(for: request))
    }

    /// Whether the consent block is expanded for this request.
    func showsConsentBlock(for request: PendingJoinRequest) -> Bool {
        ChildApprovalPolicy.showsConsentBlock(draft: childDraft(for: request))
    }

    /// FR-1/FR-25: Approve stays disabled until the declaration is complete. The server
    /// enforces the same rule; blocking here is what keeps a manager off a raw error.
    func canApprove(request: PendingJoinRequest) -> Bool {
        ChildApprovalPolicy.canApprove(
            state: childTargetState(for: request),
            draft: childDraft(for: request)
        )
    }

    func setIsChild(_ isChild: Bool, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        guard draft.isChild != isChild else { return }
        draft.isChild = isChild
        // Turning the answer back to "not a child" discards any captured consent so a
        // stale acknowledgment can never ride along with a later `true`.
        if !isChild {
            draft.consent.reset()
        } else {
            // ...and symmetrically, answering "yes, a child" discards a half-filled
            // FR-66(b) correction, so clear-evidence can never ride along with a capture.
            draft.correction.reset()
        }
        childDrafts[request.requestId] = draft
    }

    func setConsentAcknowledged(_ acknowledged: Bool, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        let wasComplete = draft.consent.isComplete
        draft.consent.consentAcknowledged = acknowledged
        childDrafts[request.requestId] = draft
        logConsentAcknowledged(wasComplete: wasComplete, isComplete: draft.consent.isComplete)
    }

    func setGuardianAffirmed(_ affirmed: Bool, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        let wasComplete = draft.consent.isComplete
        draft.consent.guardianAffirmed = affirmed
        childDrafts[request.requestId] = draft
        logConsentAcknowledged(wasComplete: wasComplete, isComplete: draft.consent.isComplete)
    }

    func setExpectedAgeOutYear(_ year: Int?, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        draft.consent.expectedAgeOutYear = year
        childDrafts[request.requestId] = draft
    }

    // MARK: - FR-66(b) new-guardian correction

    func setCorrectionReason(
        _ reason: ChildStatusCorrectionReason?,
        for request: PendingJoinRequest
    ) {
        var draft = childDraft(for: request)
        draft.correction.reason = reason
        childDrafts[request.requestId] = draft
    }

    func setCorrectionAcknowledged(_ acknowledged: Bool, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        draft.correction.statusAcknowledged = acknowledged
        childDrafts[request.requestId] = draft
    }

    func setCorrectionGuardianAffirmed(_ affirmed: Bool, for request: PendingJoinRequest) {
        var draft = childDraft(for: request)
        draft.correction.guardianAffirmed = affirmed
        childDrafts[request.requestId] = draft
    }

    /// One fresh read per pending target. `nil` (unreadable — FR-12 denies peer reads of
    /// a non-family child's doc) is `.unknown`, which demands the same explicit answer as
    /// a confirmed child: nothing is ever assumed to be an adult.
    func resolveChildTargetStates() async {
        for request in pendingRequests {
            let resolved = await deps.resolveIsChildAccount(request.userId)
            let state: ChildApprovalTargetState
            switch resolved {
            case .some(true): state = .alreadyChild
            case .some(false): state = .notChild
            case .none: state = .unknown
            }
            applyTargetState(state, requestId: request.requestId)
        }
    }

    private func applyTargetState(_ state: ChildApprovalTargetState, requestId: String) {
        let previous = childTargetStates[requestId]
        childTargetStates[requestId] = state
        // Re-seed only an UNTOUCHED draft: a manager's own answer is never overwritten,
        // but a seeded "not a child" default is, the moment the target turns out to be
        // (or might be) flagged.
        let untouched = childDrafts[requestId] == nil
            || childDrafts[requestId] == .initial(for: previous ?? state)
        if untouched {
            childDrafts[requestId] = .initial(for: state)
        }
    }

    /// SRS §12: one event per consent capture, on the parent's instance, no parameters.
    private func logConsentAcknowledged(wasComplete: Bool, isComplete: Bool) {
        guard !wasComplete, isComplete else { return }
        analytics.log(.familyChildConsentAcknowledged)
    }

    // MARK: - Actions

    func approve(request: PendingJoinRequest) async -> Bool {
        guard canApprove(request: request) else { return false }
        return await respond(to: request, approve: true)
    }

    func decline(request: PendingJoinRequest) async -> Bool {
        await respond(to: request, approve: false)
    }

    private func respond(to request: PendingJoinRequest, approve: Bool) async -> Bool {
        guard busyRequestId == nil else { return false }
        guard !processedRequestIds.contains(request.requestId) else { return false }

        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return false
        }

        let declaration = approve ? childDraft(for: request) : nil

        busyRequestId = request.requestId
        busyKind = approve ? .approve : .decline
        defer {
            busyRequestId = nil
            busyKind = nil
        }

        do {
            try await deps.respondToPendingRequest(
                familyId,
                request.requestId,
                approve,
                declaration
            )
            if approve {
                analytics.log(.familyJoinRequestApproved)
                logChildDeclarationOutcome(declaration, targetState: childTargetState(for: request))
            } else {
                analytics.log(.familyJoinRequestDeclined)
            }
            processedRequestIds.insert(request.requestId)
            childDrafts.removeValue(forKey: request.requestId)
            childTargetStates.removeValue(forKey: request.requestId)
            await refreshPendingRequests()
            return true
        } catch {
            // FR-25 race: the target was flagged after our read (or their doc was never
            // readable). Convert the server's rejection into the explicit-choice state
            // instead of surfacing a raw error the manager cannot act on.
            if approve, FamilyChildApprovalRejection.isMissingExplicitChildDeclaration(error) {
                applyTargetState(.alreadyChild, requestId: request.requestId)
                var draft = childDraft(for: request)
                draft.isChild = nil
                draft.consent.reset()
                draft.correction.reset()
                childDrafts[request.requestId] = draft
                return false
            }
            // The request was already resolved (approved/declined elsewhere, or its doc
            // is gone). Reconcile the list instead of alerting on something the manager
            // cannot act on.
            if FamilyMembershipRecoveryPolicy.isAlreadyRemoved(error) {
                processedRequestIds.insert(request.requestId)
                childDrafts.removeValue(forKey: request.requestId)
                childTargetStates.removeValue(forKey: request.requestId)
                await refreshPendingRequests()
                return false
            }
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
    }

    /// SRS §12: parent-instance events only, with fixed slugs — never a uid or a name.
    private func logChildDeclarationOutcome(
        _ declaration: ChildApprovalDraft?,
        targetState: ChildApprovalTargetState
    ) {
        guard let isChild = declaration?.isChild else { return }
        if isChild {
            analytics.log(.familyChildStatusSet(source: FamilyChildStatusAnalyticsSource.approval.rawValue))
        } else if targetState == .alreadyChild, let reason = declaration?.correction.reason?.rawValue {
            // FR-25: an explicit `false` on a flagged target is a new-guardian correction.
            // FR-66(b): the manager's enumerated reason is what both the server audit row
            // and this event record. A reason-less clear cannot reach here — the UI blocks
            // approval until one is chosen and the server rejects the payload without it.
            analytics.log(.familyChildStatusCorrected(reason: reason))
        }
    }

    private func loadPendingRequests() {
        pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
            .filter { $0.statusEnum == .pending }
    }

    private func startObservingPendingRequests() {
        pendingObservation?.cancel()
        pendingObservation = familyRepository.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pendingByFamily in
                guard let self, pendingByFamily[self.familyId] != nil else { return }
                self.loadPendingRequests()
            }
    }
}
