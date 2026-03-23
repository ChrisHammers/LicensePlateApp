//
//  PendingTripsViewModel.swift
//  LicensePlateApp
//
//  Step 04 — ViewModel for Pending Trips (trip invites). Step 08 — backend mirror via repository only.
//

import Combine
import Foundation

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
    /// True after we have subscribed to `inviteSnapshotSignal` once; prevents accumulating subscribers on every loadIfNeeded().
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

    /// Snapshot for UI: inviter/status and optional local game count.
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

    /// Call after repository context is set. Starts Firestore listening, loads invites, and subscribes to mirror updates once.
    func loadIfNeeded() {
        guard let userId = currentUserId else { return }
        tripInviteRepository.startListening(userId: userId)
        loadInvites(userId: userId)
        guard !hasSubscribedToInvites else { return }
        hasSubscribedToInvites = true
        tripInviteRepository.inviteSnapshotSignal
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, let uid = self.currentUserId else { return }
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
        Task {
            do {
                try await tripInviteRepository.acceptInvite(inviteId: invite.inviteId, userId: userId)
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
    }

    func decline(invite: TripInvite) {
        guard let userId = currentUserId else { return }
        FeedbackService.shared.buttonTap()
        errorMessage = nil
        Task {
            do {
                try await tripInviteRepository.declineInvite(inviteId: invite.inviteId, userId: userId)
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
    }

    func cancel(invite: TripInvite) {
        guard let userId = currentUserId else { return }
        FeedbackService.shared.buttonTap()
        errorMessage = nil
        Task {
            do {
                try await tripInviteRepository.cancelInvite(inviteId: invite.inviteId, userId: userId)
                AnalyticsService.shared.log(.tripInviteCanceled)
                FeedbackService.shared.actionSuccess()
                loadInvites(userId: userId)
            } catch {
                errorMessage = error.localizedDescription
                FeedbackService.shared.actionError()
            }
        }
    }

    /// Sends a trip invite via Cloud Function; logs analytics on success.
    /// TODO(step-08-ui-wire): Connect from a production invite/send-trip UI flow.
    func sendTripInvite(tripSessionId: UUID, tripName: String, toUserId: String, expiresAt: Date?) async {
        guard let fromUserId = currentUserId else { return }
        errorMessage = nil
        do {
            _ = try await tripInviteRepository.sendTripInvite(
                tripSessionId: tripSessionId.uuidString,
                tripName: tripName,
                fromUserId: fromUserId,
                toUserId: toUserId,
                expiresAt: expiresAt
            )
            AnalyticsService.shared.log(.tripInviteSent(
                tripSessionId: tripSessionId.uuidString,
                tripNameLength: tripName.count
            ))
            loadInvites(userId: fromUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call when screen appears to log analytics.
    func onAppear() {
        AnalyticsService.shared.log(.tripInvitesScreenOpened)
        loadIfNeeded()
    }
}
