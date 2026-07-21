//
//  AddFamilyMemberViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class AddFamilyMemberViewModel: ObservableObject {
    let familyId: String

    @Published var searchQuery = ""
    @Published var searchType: UserRepository.SearchType = .all
    @Published var searchResults: [UserRepository.UserSearchResult] = []
    @Published var isSearching = false
    @Published var hasCompletedSearch = false
    @Published var isInviting = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccessAlert = false

    private var searchTask: Task<Void, Never>?
    private var authService: FirebaseAuthService?
    private let userRepository: UserRepository
    private let familyRepository: FamilyRepository

    var showNoUsersFoundEmptyState: Bool {
        guard let authService else { return false }
        return FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser)
            && searchQuery.count >= 3
            && !isSearching
            && hasCompletedSearch
            && searchResults.isEmpty
            && !showError
    }

    init(
        familyId: String,
        userRepository: UserRepository = .shared,
        familyRepository: FamilyRepository = .shared
    ) {
        self.familyId = familyId
        self.userRepository = userRepository
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        userRepository.setModelContext(modelContext)
        familyRepository.setModelContext(modelContext)
    }

    func cancelSearchTask() {
        searchTask?.cancel()
    }

    func onSearchQueryChange() {
        searchTask?.cancel()
        if searchQuery.count < 3 {
            searchResults = []
            isSearching = false
            hasCompletedSearch = false
            return
        }
        searchTask = Task {
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
            hasCompletedSearch = false
            return
        }

        guard let authService else {
            errorMessage = "User not authenticated".localized
            showError = true
            return
        }

        if !FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
            searchResults = []
            isSearching = false
            hasCompletedSearch = false
            errorMessage = FriendsFamilyCallableErrors.guestBlockedMessage
            showError = true
            return
        }

        guard authService.isOnline else {
            searchResults = []
            isSearching = false
            hasCompletedSearch = false
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        isSearching = true
        errorMessage = nil
        showError = false
        hasCompletedSearch = false

        do {
            let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            let results = try await userRepository.searchUsers(
                query: searchQuery,
                searchType: searchType,
                excludeUserId: currentUserId,
                searchingUser: authService.currentUser
            )
            searchResults = results
            isSearching = false
            hasCompletedSearch = true

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
            hasCompletedSearch = false
            searchResults = []
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func sendInvite(to result: UserRepository.UserSearchResult) {
        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        if !FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
            errorMessage = FriendsFamilyCallableErrors.guestBlockedMessage
            showError = true
            return
        }

        let toUserId = result.user.firebaseUID ?? result.user.id
        let inviteMethod = result.matchedField.inviteMethod

        isInviting = true
        errorMessage = nil

        Task {
            do {
                _ = try await familyRepository.sendFamilyInvite(
                    toUserId: toUserId,
                    familyId: familyId,
                    method: inviteMethod
                )
                isInviting = false
                AnalyticsService.shared.log(.familyInviteSent)
                showSuccessAlert = true
            } catch {
                FriendsFamilyInviteAnalytics.logInviteFailure(error)
                let description = error.localizedDescription
                let userFriendlyMessage: String
                if description.contains("permission-denied") {
                    userFriendlyMessage = "You don't have permission to invite members to this family.".localized
                } else if description.contains("failed-precondition") {
                    userFriendlyMessage = "Unable to invite this user. They may already be in a family or have reached the limit.".localized
                } else if description.contains("not-found") {
                    userFriendlyMessage = "User not found.".localized
                } else if description.contains("unauthenticated") {
                    userFriendlyMessage = "Please sign in to send invites.".localized
                } else {
                    userFriendlyMessage = "Failed to send invite: %@".localized(description)
                }
                isInviting = false
                errorMessage = userFriendlyMessage
                showError = true
            }
        }
    }
}
