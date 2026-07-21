//
//  CreateFamilyShareCodeViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import SwiftUI
import UIKit
import Combine

@MainActor
final class CreateFamilyShareCodeViewModel: ObservableObject {
    let familyId: String
    private let existingShareCode: ShareCode?

    @Published var shareCode: String?
    @Published var expiresAt: Date?
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var qrCodeImage: UIImage?
    @Published var currentTime = Date()
    @Published var currentShareCodeId: String?
    @Published var showShareSheet = false
    @Published var copiedToClipboard = false

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository

    init(
        familyId: String,
        existingShareCode: ShareCode? = nil,
        familyRepository: FamilyRepository = .shared
    ) {
        self.familyId = familyId
        self.existingShareCode = existingShareCode
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
    }

    func onAppear() {
        currentTime = Date()
        if let existing = existingShareCode, !existing.isExpired {
            shareCode = existing.code
            expiresAt = existing.expiresAt
            currentShareCodeId = existing.codeId
            qrCodeImage = QRCodeService.shared.generateQRCode(from: existing.code)
        } else if shareCode == nil {
            if let existing = existingShareCode, existing.isExpired {
                AnalyticsService.shared.log(.shareCodeExpired)
            }
            generateCode()
        }
    }

    func tickClock() {
        currentTime = Date()
    }

    func copyShareCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedToClipboard = true
        UIAccessibility.post(notification: .announcement, argument: "share_code.a11y.copied".localized)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copiedToClipboard = false
        }
    }

    func generateCode() {
        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let result = try await familyRepository.createShareCode(type: "family", familyId: familyId)
                let qrImage = QRCodeService.shared.generateQRCode(from: result.code)
                shareCode = result.code
                expiresAt = result.expiresAt
                currentShareCodeId = result.codeId
                qrCodeImage = qrImage
                isGenerating = false
                AnalyticsService.shared.log(.shareCodeGenerated(type: "family"))
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
                showError = true
                FriendsFamilyInviteAnalytics.logInviteFailure(error)
            }
        }
    }

    func refreshShareCode() {
        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        if let expiresAt, expiresAt <= currentTime {
            AnalyticsService.shared.log(.shareCodeExpired)
        }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                if let codeId = currentShareCodeId {
                    try? await familyRepository.revokeShareCode(codeId: codeId)
                    AnalyticsService.shared.log(.shareCodeRevoked)
                }

                let result = try await familyRepository.createShareCode(type: "family", familyId: familyId)
                let qrImage = QRCodeService.shared.generateQRCode(from: result.code)
                shareCode = result.code
                expiresAt = result.expiresAt
                currentShareCodeId = result.codeId
                qrCodeImage = qrImage
                isGenerating = false
                currentTime = Date()
                AnalyticsService.shared.log(.shareCodeGenerated(type: "family"))
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
                showError = true
                FriendsFamilyInviteAnalytics.logInviteFailure(error)
            }
        }
    }

    func timeUntilExpiration(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSince(currentTime)
        guard timeInterval > 0 else {
            return "Expired".localized
        }
        let minutes = Int(timeInterval / 60)
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))

        if minutes > 0 {
            return "share_code.minutes".localized(minutes)
        }
        return "share_code.seconds".localized(seconds)
    }
}
