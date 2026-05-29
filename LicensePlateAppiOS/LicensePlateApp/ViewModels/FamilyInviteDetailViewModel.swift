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

    @Published var isProcessing = false
    @Published var hasAccepted = false
    @Published var errorMessage: String?

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository

    init(
        inviteId: String,
        familyId: String,
        familyRepository: FamilyRepository = .shared
    ) {
        self.inviteId = inviteId
        self.familyId = familyId
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
    }

    func respondToInvite(accept: Bool, onDeclineDismiss: @escaping () -> Void) {
        guard let authService = authService else { return }

        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            return
        }

        isProcessing = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await familyRepository.respondToFamilyInvite(inviteId: inviteId, accept: accept)

                isProcessing = false
                if accept {
                    hasAccepted = true
                    AnalyticsService.shared.log(.familyInviteUserAccepted)
                } else {
                    AnalyticsService.shared.log(.familyInviteUserDeclined)
                    onDeclineDismiss()
                }
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                if !accept {
                    onDeclineDismiss()
                }
            }
        }
    }
}
