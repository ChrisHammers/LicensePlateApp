//
//  AddFriendViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class AddFriendViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchType: UserRepository.SearchType = .all
    @Published var searchResults: [UserRepository.UserSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccessAlert = false
    @Published private(set) var invitingUserId: String?

    private var searchTask: Task<Void, Never>?
    private var authService: FirebaseAuthService?
    private var modelContext: ModelContext?
    private let userRepository: UserRepository
    private let friendshipRepository: FriendshipRepository
    private let inviteRepository: InviteRepository

    init(
        userRepository: UserRepository = .shared,
        friendshipRepository: FriendshipRepository = .shared,
        inviteRepository: InviteRepository = .shared
    ) {
        self.userRepository = userRepository
        self.friendshipRepository = friendshipRepository
        self.inviteRepository = inviteRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        self.modelContext = modelContext
        userRepository.setModelContext(modelContext)
        friendshipRepository.setModelContext(modelContext)
        inviteRepository.setModelContext(modelContext)
    }

    func onAppear() {
        AnalyticsService.shared.log(.addFriendCTATapped)
    }

    func cancelSearchTask() {
        searchTask?.cancel()
    }

    func onSearchQueryChange() {
        searchTask?.cancel()
        if searchQuery.count < 3 {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                await performSearch()
            } catch {}
        }
    }

    func performSearch() async {
        guard searchQuery.count >= 3 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            guard let currentUserId = authService?.currentUser?.firebaseUID ?? authService?.currentUser?.id else {
                isSearching = false
                errorMessage = "User not authenticated".localized
                showError = true
                return
            }

            var results = try await userRepository.searchUsers(
                query: searchQuery,
                searchType: searchType,
                excludeUserId: currentUserId
            )

            let acceptedFriendships = friendshipRepository.getAcceptedFriendships(for: currentUserId)
            let friendUserIds = Set(acceptedFriendships.compactMap { $0.otherUser(than: currentUserId) })

            let pendingInvites = inviteRepository.getFriendInvites(for: currentUserId)
                .filter { $0.statusEnum == .pending }
            let inviteUserIds = Set(pendingInvites.compactMap { invite in
                invite.fromUserId == currentUserId ? invite.toUserId : invite.fromUserId
            })

            let excludedUserIds = friendUserIds.union(inviteUserIds)

            results = results.filter { result in
                let userId = result.user.firebaseUID ?? result.user.id
                return !excludedUserIds.contains(userId)
            }

            searchResults = results
            isSearching = false

            let queryType: String
            switch searchType {
            case .all: queryType = "all"
            case .username: queryType = "username"
            case .email: queryType = "email"
            case .phone: queryType = "phone"
            }
            AnalyticsService.shared.log(.userSearchPerformed(queryType: queryType))
        } catch {
            isSearching = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func sendInvite(to result: UserRepository.UserSearchResult) {
        guard let authService = authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        let toUserId = result.user.firebaseUID ?? result.user.id
        errorMessage = nil

        Task { @MainActor in
            invitingUserId = toUserId
            defer { invitingUserId = nil }
            do {
                _ = try await friendshipRepository.sendFriendInvite(toUserId: toUserId, method: "search")
                AnalyticsService.shared.log(.userSearchResultSelected)
                AnalyticsService.shared.log(.friendRequestSent)
                showSuccessAlert = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
