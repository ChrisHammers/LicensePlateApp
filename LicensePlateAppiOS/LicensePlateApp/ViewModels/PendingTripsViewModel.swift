//
//  PendingTripsViewModel.swift
//  LicensePlateApp
//
//  Step 04 — ViewModel for Pending Trips (trip invites). No direct Firebase or ModelContext access.
//

import Foundation
import Combine

@MainActor
final class PendingTripsViewModel: ObservableObject {
    @Published private(set) var incomingInvites: [TripInvite] = []
    @Published private(set) var outgoingInvites: [TripInvite] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    /// True after we have subscribed to repo.$tripInvites once; prevents accumulating subscribers on every loadIfNeeded().
    private var hasSubscribedToInvites = false

    init(
        tripInviteRepository: TripInviteRepositoryProtocol,
        authService: FirebaseAuthService,
        gameInstanceRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared
    ) {
        self.tripInviteRepository = tripInviteRepository
        self.authService = authService
        self.gameInstanceRepository = gameInstanceRepository
    }

    /// Snapshot for UI: trip participation (TripMode) vs optional local game count.
    func displaySnapshot(for invite: TripInvite) -> InviteDisplaySnapshot {
        InviteDisplaySnapshot.make(from: invite, localGameCount: localGameCount(for: invite.tripSessionId))
    }

    private func localGameCount(for tripSessionId: String) -> Int? {
        guard let sessionUUID = UUID(uuidString: tripSessionId) else { return nil }
        return try? gameInstanceRepository.gameCount(sessionId: sessionUUID)
    }

    private func gameCountForAnalytics(invite: TripInvite) -> Int? {
        localGameCount(for: invite.tripSessionId)
    }

    func setAuthService(_ service: FirebaseAuthService) {
        self.authService = service
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    /// Call after repository context is set. Loads invites and subscribes to updates (subscription is added only once).
    func loadIfNeeded() {
        guard let userId = currentUserId else { return }
        loadInvites(userId: userId)
        guard let repo = tripInviteRepository as? TripInviteRepository else { return }
        guard !hasSubscribedToInvites else { return }
        hasSubscribedToInvites = true
        repo.$tripInvites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let uid = self.currentUserId else { return }
                self.loadInvites(userId: uid)
            }
            .store(in: &cancellables)
    }

    func loadInvites(userId: String) {
        isLoading = true
        errorMessage = nil
        do {
            incomingInvites = try tripInviteRepository.getIncomingInvites(userId: userId)
            outgoingInvites = try tripInviteRepository.getOutgoingInvites(userId: userId)
            if let repo = tripInviteRepository as? TripInviteRepository {
                repo.refreshPublishedInvites(userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func accept(invite: TripInvite) {
        guard let userId = currentUserId else { return }
        FeedbackService.shared.buttonTap()
        errorMessage = nil
        do {
            try tripInviteRepository.acceptInvite(inviteId: invite.inviteId, userId: userId)
            AnalyticsService.shared.log(.tripInviteAcceptedWithContext(
                inviteTripId: invite.tripSessionId,
                inviteGameCount: gameCountForAnalytics(invite: invite),
                participantCountAfterJoin: nil
            ))
            FeedbackService.shared.actionSuccess()
            loadInvites(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            FeedbackService.shared.actionError()
        }
    }

    func decline(invite: TripInvite) {
        guard let userId = currentUserId else { return }
        FeedbackService.shared.buttonTap()
        errorMessage = nil
        do {
            try tripInviteRepository.declineInvite(inviteId: invite.inviteId, userId: userId)
            AnalyticsService.shared.log(.tripInviteDeclinedWithContext(
                inviteTripId: invite.tripSessionId,
                inviteGameCount: gameCountForAnalytics(invite: invite)
            ))
            FeedbackService.shared.actionSuccess()
            loadInvites(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            FeedbackService.shared.actionError()
        }
    }

    func cancel(invite: TripInvite) {
        guard let userId = currentUserId else { return }
        FeedbackService.shared.buttonTap()
        errorMessage = nil
        do {
            try tripInviteRepository.cancelInvite(inviteId: invite.inviteId, userId: userId)
            AnalyticsService.shared.log(.tripInviteCanceled)
            FeedbackService.shared.actionSuccess()
            loadInvites(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            FeedbackService.shared.actionError()
        }
    }

    /// Call when screen appears to log analytics.
    func onAppear() {
        AnalyticsService.shared.log(.tripInvitesScreenOpened)
        loadIfNeeded()
    }
}
