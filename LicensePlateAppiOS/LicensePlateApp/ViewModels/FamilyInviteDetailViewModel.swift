//
//  FamilyInviteDetailViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class FamilyInviteDetailViewModel: ObservableObject {
    let inviteId: String
    let familyId: String

    @Published private(set) var processingAction: InviteBusyKind?
    @Published var hasAccepted = false
    @Published var errorMessage: String?
    @Published var invite: Invite?
    @Published var inviter: AppUser?
    @Published var isLoadingInviter = true

    var isProcessing: Bool { processingAction != nil }

    private var authService: FirebaseAuthService?
    private var modelContext: ModelContext?
    private let familyRepository: FamilyRepository
    private let inviteRepository: InviteRepository

    init(
        inviteId: String,
        familyId: String,
        familyRepository: FamilyRepository = .shared,
        inviteRepository: InviteRepository = .shared
    ) {
        self.inviteId = inviteId
        self.familyId = familyId
        self.familyRepository = familyRepository
        self.inviteRepository = inviteRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        self.modelContext = modelContext
        familyRepository.setModelContext(modelContext)
        inviteRepository.setModelContext(modelContext)
        UserRepository.shared.setModelContext(modelContext)
    }

    /// Loads invite (for familyName) and inviter profile via fromUserId.
    func loadInviteAndInviter() async {
        isLoadingInviter = true

        guard let authService = authService,
              let modelContext = modelContext else {
            isLoadingInviter = false
            return
        }

        let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        let searchInviteId = inviteId
        let inviteDescriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.inviteId == searchInviteId
            }
        )

        var loaded = try? modelContext.fetch(inviteDescriptor).first

        if loaded == nil, let currentUserId {
            await inviteRepository.refreshInvite(inviteId: inviteId, userId: currentUserId)
            loaded = inviteRepository.getInvite(inviteId: inviteId)
                ?? inviteRepository.getInvite(inviteId: inviteId, userId: currentUserId)
        } else if let currentUserId {
            // Refresh to pick up familyName from server
            await inviteRepository.refreshInvite(inviteId: inviteId, userId: currentUserId)
            loaded = inviteRepository.getInvite(inviteId: inviteId)
                ?? inviteRepository.getInvite(inviteId: inviteId, userId: currentUserId)
                ?? loaded
        }

        invite = loaded

        guard let fromUserId = loaded?.fromUserId, !fromUserId.isEmpty else {
            isLoadingInviter = false
            return
        }

        do {
            inviter = try await UserRepository.shared.getUser(userId: fromUserId)
        } catch {
            #if DEBUG
            print("⚠️ Failed to load inviter \(fromUserId): \(error.localizedDescription)")
            #endif
        }

        isLoadingInviter = false
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
                // COPPA FR-60(b)/FR-26: this is the SECOND consent exit, and for a child it is
                // the call that actually creates the pending row the captain sees — so it is
                // the moment FR-86's identity stamp is read off `users/{uid}`, and the moment a
                // sticky post-revocation child most needs their identity recovered if its
                // session died. It ran bare while `redeemShareCode` got the whole sequence,
                // which left the two exits FR-26 names as equals behaving differently. A no-op
                // for adults and for a decline that needs no identity work.
                try await authService.withConsentSeekingRedemption {
                    try await familyRepository.respondToFamilyInvite(inviteId: inviteId, accept: accept)
                }

                if accept {
                    hasAccepted = true
                    AnalyticsService.shared.log(.familyInviteUserAccepted)
                    AnalyticsService.shared.log(.familyJoinRequestCreated)
                } else {
                    AnalyticsService.shared.log(.familyInviteUserDeclined)
                    onDeclineDismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
