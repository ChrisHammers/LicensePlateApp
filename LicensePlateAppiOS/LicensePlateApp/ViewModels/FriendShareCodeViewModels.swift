//
//  FriendShareCodeViewModels.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import SwiftUI
import UIKit
import Combine

@MainActor
final class CreateFriendShareCodeViewModel: ObservableObject {
    @Published var shareCode: String?
    @Published var expiresAt: Date?
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var qrCodeImage: UIImage?
    private var hasRequestedGeneration = false

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository

    init(familyRepository: FamilyRepository = .shared) {
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
    }

    func generateCode() {
        guard !hasRequestedGeneration else { return }
        guard let authService = authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        hasRequestedGeneration = true
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let result = try await familyRepository.createShareCode(type: "friend")
                let qrImage = QRCodeService.shared.generateQRCode(from: result.code)
                await MainActor.run {
                    shareCode = result.code
                    expiresAt = result.expiresAt
                    qrCodeImage = qrImage
                    isGenerating = false
                    AnalyticsService.shared.log(.shareCodeGenerated(type: "friend"))
                }
            } catch {
                await MainActor.run {
                    hasRequestedGeneration = false
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    func timeUntilExpiration(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        guard timeInterval > 0 else {
            return "Expired".localized
        }
        let minutes = max(1, Int(timeInterval / 60))
        return "share_code.minutes".localized(minutes)
    }
}

@MainActor
final class JoinFriendByCodeViewModel: ObservableObject {
    @Published var shareCode = ""
    @Published var isRedeeming = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var redeemedInviteId: String?
    @Published var showInviteDetail = false

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository

    init(familyRepository: FamilyRepository = .shared) {
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
        InviteRepository.shared.setModelContext(modelContext)
    }

    func redeemCode() {
        let trimmedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        guard let authService = authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        isRedeeming = true
        errorMessage = nil

        Task {
            do {
                let inviteId = try await familyRepository.redeemShareCode(code: trimmedCode)
                await MainActor.run {
                    isRedeeming = false
                    redeemedInviteId = inviteId
                    AnalyticsService.shared.log(.shareCodeUsed(type: "friend"))
                    showInviteDetail = true
                }
            } catch {
                await MainActor.run {
                    isRedeeming = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
