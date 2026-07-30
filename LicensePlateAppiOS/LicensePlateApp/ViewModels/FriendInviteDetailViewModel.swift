//
//  FriendInviteDetailViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class FriendInviteDetailViewModel: ObservableObject {
    let inviteId: String

    @Published private(set) var processingAction: InviteBusyKind?
    @Published var hasAccepted = false
    @Published var errorMessage: String?
    @Published var user: AppUser?
    @Published var isLoadingUser = true

    var isProcessing: Bool { processingAction != nil }

    private var authService: FirebaseAuthService?
    private var modelContext: ModelContext?
    private let friendshipRepository: FriendshipRepository
    private let inviteRepository: InviteRepository

    init(
        inviteId: String,
        friendshipRepository: FriendshipRepository = .shared,
        inviteRepository: InviteRepository = .shared
    ) {
        self.inviteId = inviteId
        self.friendshipRepository = friendshipRepository
        self.inviteRepository = inviteRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        self.modelContext = modelContext
        friendshipRepository.setModelContext(modelContext)
        inviteRepository.setModelContext(modelContext)
    }

    func loadInviteAndUser() async {
        isLoadingUser = true

        guard let authService = authService,
              let modelContext = modelContext else {
            isLoadingUser = false
            return
        }

        let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id

        let searchInviteId = inviteId
        let inviteDescriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.inviteId == searchInviteId
            }
        )

        var fromUserId: String?

        if let cachedInvite = try? modelContext.fetch(inviteDescriptor).first {
            fromUserId = cachedInvite.fromUserId
        } else if let currentUserId = currentUserId {
            await inviteRepository.refreshInvite(inviteId: inviteId, userId: currentUserId)
            fromUserId = inviteRepository.getInvite(inviteId: inviteId, userId: currentUserId)?.fromUserId
        }

        guard let userId = fromUserId else {
            isLoadingUser = false
            return
        }

        do {
            if let fetchedUser = try await UserRepository.shared.getUser(userId: userId) {
                self.user = fetchedUser
                isLoadingUser = false
                return
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
            #endif
        }

        isLoadingUser = false
    }

    func respondToInvite(accept: Bool, onDeclineDismiss: @escaping () -> Void) {
        guard let authService = authService else { return }
        guard processingAction == nil else { return }

        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            return
        }

        processingAction = accept ? .accept : .decline
        errorMessage = nil

        Task { @MainActor in
            defer { processingAction = nil }
            do {
                try await friendshipRepository.respondToFriendInvite(inviteId: inviteId, accept: accept)

                if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                    await inviteRepository.refreshInvite(inviteId: inviteId, userId: userId)
                }

                if accept {
                    hasAccepted = true
                    AnalyticsService.shared.log(.friendRequestAccepted)
                } else {
                    AnalyticsService.shared.log(.friendRequestDeclined)
                    onDeclineDismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
