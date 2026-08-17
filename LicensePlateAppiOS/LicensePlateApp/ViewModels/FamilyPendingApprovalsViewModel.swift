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
    /// Busy state PER ROW.
    ///
    /// Device pass 2026-08-17: this was one `busyRequestId` for the whole surface, so while a
    /// call was in flight on row A, row B's Approve and Decline silently no-op'd — the guard
    /// returned `false` before touching anything, while the buttons stayed enabled and gave no
    /// feedback whatsoever ("declining the second row was blocked while the first was in
    /// flight"). Pending rows resolve independently server-side; nothing ever justified
    /// serialising them, and serialising them turned one stalled call into a dead screen.
    @Published private(set) var busyKindByRequestId: [String: InviteBusyKind] = [:]
    @Published private(set) var processedRequestIds: Set<String> = []

    /// COPPA FR-1/FR-25 approval-time child declaration, one draft per pending request.
    @Published private(set) var childTargetStates: [String: ChildApprovalTargetState] = [:]
    @Published private(set) var childDrafts: [String: ChildApprovalDraft] = [:]

    var isProcessing: Bool { !busyKindByRequestId.isEmpty }

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
        busyKindByRequestId[requestId] == kind
    }

    func isRowDisabled(requestId: String) -> Bool {
        if processedRequestIds.contains(requestId) { return true }
        if busyKindByRequestId[requestId] != nil { return true }
        guard let request = pendingRequests.first(where: { $0.requestId == requestId }) else {
            return false
        }
        return isExpired(request)
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

    /// Reconciles the list against the server.
    ///
    /// Both halves run under `FamilyCallable.bounded` because both are chains of Firestore
    /// reads, and a Firestore read has NO client-side deadline — offline it serves cache, but
    /// against a wedged stream it simply never returns. `.refreshable` and `.task` await this
    /// directly, so an unbounded hang here is a pull-to-refresh spinner that never stops.
    /// Timing out falls back to the local store, which is the same path an error already took.
    func refreshPendingRequests() async {
        do {
            let linked = try await FamilyCallable.bounded(name: "fetchPendingRequests") {
                [deps, familyId] in try await deps.fetchPendingRequests(familyId)
            }
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
        guard !isExpired(request) else { return false }
        return ChildApprovalPolicy.canApprove(
            state: childTargetState(for: request),
            draft: childDraft(for: request)
        )
    }

    // MARK: - Decision window (device pass 2026-08-17)

    /// Past its 7-day decision window. The server sweep retires the row within five minutes;
    /// until it does, the row renders TERMINAL rather than offering actions the server refuses.
    func isExpired(_ request: PendingJoinRequest) -> Bool {
        FamilyPendingRequestLifetime.isExpired(createdAt: request.createdAt)
    }

    /// "Expires in 4 days" / "Expires today" / "Expired". On screen from the moment the row
    /// appears, so its eventual retirement is foreseeable instead of a row that vanishes.
    func expiryLabel(for request: PendingJoinRequest) -> String {
        FamilyPendingRequestLifetime.localizedLabel(createdAt: request.createdAt)
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
    ///
    /// Bounded as a whole rather than per row: N rows under N separate deadlines would be N
    /// times the worst case. An abandoned pass leaves the rows it had not reached at
    /// `.unknown`, which is the fail-closed direction — `.unknown` demands the same explicit
    /// declaration a confirmed child does, so a timeout can never soften an approval.
    func resolveChildTargetStates() async {
        try? await FamilyCallable.bounded(name: "resolveChildTargetStates") { [weak self] in
            guard let self else { return }
            for request in self.pendingRequests {
                let resolved = await self.deps.resolveIsChildAccount(request.userId)
                let state: ChildApprovalTargetState
                switch resolved {
                case .some(true): state = .alreadyChild
                case .some(false): state = .notChild
                case .none: state = .unknown
                }
                self.applyTargetState(state, requestId: request.requestId)
            }
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
        // Per-row, not per-surface: a second row must stay actionable while this one runs.
        guard busyKindByRequestId[request.requestId] == nil else { return false }
        guard !processedRequestIds.contains(request.requestId) else { return false }

        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return false
        }

        let declaration = approve ? childDraft(for: request) : nil

        busyKindByRequestId[request.requestId] = approve ? .approve : .decline

        let outcome: Result<Void, Error>
        do {
            try await deps.respondToPendingRequest(
                familyId,
                request.requestId,
                approve,
                declaration
            )
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }

        // Release the row BEFORE any reconcile, and outside a `defer` that would only fire
        // once the whole function — reconcile included — had returned. The reconcile awaits
        // Firestore reads that carry no client deadline of their own, so holding the flag
        // across them is what let a SUCCESSFUL approve leave its row disabled until the app
        // was relaunched. The decision is already made at this point; nothing below needs
        // the row locked.
        busyKindByRequestId.removeValue(forKey: request.requestId)

        do {
            try outcome.get()
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
