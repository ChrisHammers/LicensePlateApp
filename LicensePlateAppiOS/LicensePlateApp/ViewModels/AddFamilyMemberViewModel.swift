//
//  AddFamilyMemberViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine
import FirebaseFunctions

@MainActor
final class AddFamilyMemberViewModel: ObservableObject {
    let familyId: String

    @Published var searchQuery = ""
    @Published var searchType: UserRepository.SearchType = .all
    @Published var searchResults: [UserRepository.UserSearchResult] = []
    @Published var isSearching = false
    @Published var hasCompletedSearch = false
    @Published private(set) var invitingUserId: String?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccessAlert = false

    var isInviting: Bool { invitingUserId != nil }

    private var searchTask: Task<Void, Never>?
    private var authService: FirebaseAuthService?
    private let userRepository: UserRepository
    private let familyRepository: FamilyRepository
    private let inviteRepository: InviteRepository

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
        familyRepository: FamilyRepository = .shared,
        inviteRepository: InviteRepository = .shared
    ) {
        self.familyId = familyId
        self.userRepository = userRepository
        self.familyRepository = familyRepository
        self.inviteRepository = inviteRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        userRepository.setModelContext(modelContext)
        familyRepository.setModelContext(modelContext)
        inviteRepository.setModelContext(modelContext)
        // Keep pending exclusions fresh while the sheet is open (also feeds Family Dashboard).
        inviteRepository.startListeningForFamily(familyId: familyId)
        if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
            inviteRepository.startListening(userId: userId)
        }
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
            var results = try await userRepository.searchUsers(
                query: searchQuery,
                searchType: searchType,
                excludeUserId: currentUserId,
                searchingUser: authService.currentUser
            )

            let memberIds = Set(familyRepository.getMembers(familyId: familyId).map(\.userId))
            let pendingJoinIds = Set(
                familyRepository.getPendingRequests(familyId: familyId)
                    .filter { $0.statusEnum == .pending }
                    .map(\.userId)
            )
            let pendingInviteeIds = Set(
                inviteRepository.getPendingFamilyInvites(familyId: familyId).compactMap(\.toUserId)
            )
            let excludedUserIds = memberIds.union(pendingJoinIds).union(pendingInviteeIds)

            results = results.filter { result in
                let userId = result.user.firebaseUID ?? result.user.id
                return !excludedUserIds.contains(userId)
            }

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

        guard invitingUserId == nil else { return }

        let toUserId = result.user.firebaseUID ?? result.user.id
        let inviteMethod = result.matchedField.inviteMethod

        invitingUserId = toUserId
        errorMessage = nil

        Task {
            defer { invitingUserId = nil }
            do {
                _ = try await familyRepository.sendFamilyInvite(
                    toUserId: toUserId,
                    familyId: familyId,
                    method: inviteMethod
                )
                AnalyticsService.shared.log(.familyInviteSent)
                showSuccessAlert = true
            } catch {
                FriendsFamilyInviteAnalytics.logInviteFailure(error)
                errorMessage = Self.userFacingSendError(error)
                showError = true
            }
        }
    }

    private static func userFacingSendError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code),
           code == .alreadyExists {
            return "Pending invite already exists.".localized
        }

        let description = error.localizedDescription
        if description.contains("already-exists")
            || description.localizedCaseInsensitiveContains("Pending invite already exists") {
            return "Pending invite already exists.".localized
        }
        if description.contains("permission-denied") {
            return "You don't have permission to invite members to this family.".localized
        }
        if description.contains("failed-precondition") {
            return "Unable to invite this user. They may already be in a family or have reached the limit.".localized
        }
        if description.contains("not-found") {
            return "User not found.".localized
        }
        if description.contains("unauthenticated") {
            return "Please sign in to send invites.".localized
        }
        return "Failed to send invite: %@".localized(description)
    }
}
