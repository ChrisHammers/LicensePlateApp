//
//  FriendsHubViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine

@MainActor
class FriendsHubViewModel: ObservableObject {
    @Published var friends: [Friendship] = []
    @Published var incomingFriendInvites: [Invite] = []
    @Published var outgoingFriendInvites: [Invite] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: FriendsTab = .friends

    private let friendshipRepository: FriendshipRepository
    private let inviteRepository: InviteRepository
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    /// Emit `friendRequestReceived` when incoming count goes from 0 to a positive value.
    private var previousIncomingFriendInviteCount: Int = 0

    enum FriendsTab {
        case friends
        case requests
    }

    init(friendshipRepository: FriendshipRepository, inviteRepository: InviteRepository, authService: FirebaseAuthService) {
        self.friendshipRepository = friendshipRepository
        self.inviteRepository = inviteRepository
        self.authService = authService
    }

    func setModelContext(_ context: ModelContext) {
        friendshipRepository.setModelContext(context)
        inviteRepository.setModelContext(context)
    }

    func setAuthService(_ service: FirebaseAuthService) {
        cancellables.removeAll()
        authService = service

        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            setupUserObserver()
            return
        }

        setupObservers(userId: userId)
        updateFriendInvites(inviteRepository.invites, userId: userId)
    }

    private func setupUserObserver() {
        authService.$currentUser
            .sink { [weak self] user in
                guard let self = self, let user = user else { return }
                let userId = user.firebaseUID ?? user.id
                self.cancellables.removeAll()
                self.setupObservers(userId: userId)
                self.loadData()
            }
            .store(in: &cancellables)
    }

    private func setupObservers(userId: String) {
        friendshipRepository.$friendships
            .sink { [weak self] friendships in
                self?.updateFriendships(friendships)
            }
            .store(in: &cancellables)

        inviteRepository.$invites
            .sink { [weak self] invites in
                guard let self = self else { return }
                self.updateFriendInvites(invites, userId: userId)
            }
            .store(in: &cancellables)

        authService.$currentUser
            .sink { [weak self] user in
                guard let self = self, let user = user else { return }
                let currentUserId = user.firebaseUID ?? user.id
                self.loadData()
                self.updateFriendInvites(self.inviteRepository.invites, userId: currentUserId)
            }
            .store(in: &cancellables)
    }

    func loadData() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }

        isLoading = true

        friendshipRepository.startListening(userId: userId)
        inviteRepository.startListening(userId: userId)

        updateFriendships(friendshipRepository.getFriendships(for: userId))
        updateFriendInvites(inviteRepository.getFriendInvites(for: userId), userId: userId)

        isLoading = false
    }

    func logFriendsHubAppeared() {
        AnalyticsService.shared.log(.friendsScreenOpened)
        AnalyticsService.shared.logScreenView(screenName: "friends")
    }

    private func updateFriendships(_ allFriendships: [Friendship]) {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }

        friends = allFriendships.filter { $0.statusEnum == .accepted }
    }

    private func updateFriendInvites(_ allInvites: [Invite], userId: String) {
        let split = FriendsHubInviteFilter.splitFriendInvites(allInvites, userId: userId)
        incomingFriendInvites = split.incoming
        outgoingFriendInvites = split.outgoing

        let count = split.incoming.count
        if previousIncomingFriendInviteCount == 0, count > 0 {
            AnalyticsService.shared.log(.friendRequestReceived)
        }
        previousIncomingFriendInviteCount = count
    }

    func removeFriend(_ friendship: Friendship) {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            FeedbackService.shared.actionError()
            return
        }

        errorMessage = nil
        FeedbackService.shared.buttonTap()

        Task { @MainActor in
            do {
                try await friendshipRepository.removeFriend(friendshipId: friendship.friendshipId)
                AnalyticsService.shared.log(.friendRemoved)
                FeedbackService.shared.actionSuccess()
            } catch {
                self.errorMessage = error.localizedDescription
                FeedbackService.shared.actionError()
            }
        }
    }

    /// Count of pending incoming friend invites (for Requests tab badge).
    var pendingFriendRequestsCount: Int {
        incomingFriendInvites.count
    }
}
