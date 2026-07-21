//
//  JoinFamilyViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class JoinFamilyViewModel: ObservableObject {
    @Published var shareCode = ""
    @Published var isJoining = false
    @Published var showQRScanner = false
    @Published var scannedCode: String?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var redeemedInviteId: String?
    @Published var redeemedFamilyId: String?
    @Published var showInviteDetail = false

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository
    private let inviteRepository: InviteRepository

    init(
        familyRepository: FamilyRepository = .shared,
        inviteRepository: InviteRepository = .shared
    ) {
        self.familyRepository = familyRepository
        self.inviteRepository = inviteRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
        inviteRepository.setModelContext(modelContext)
    }

    func onAppear() {
        AnalyticsService.shared.log(.familyJoinCTATapped)
        AnalyticsService.shared.log(.inviteViaCodeOpened)
    }

    func applyScannedCode(_ scannedString: String) {
        shareCode = extractCode(from: scannedString)
    }

    func requestCameraPermissionAndScan() {
        Task {
            let hasPermission = await QRCodeService.shared.requestCameraPermission()
            if hasPermission {
                AnalyticsService.shared.log(.inviteViaQROpened)
                showQRScanner = true
            } else {
                errorMessage = "Camera permission is required to scan QR codes".localized
                showError = true
            }
        }
    }

    func joinWithCode() {
        let trimmedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        isJoining = true
        errorMessage = nil

        Task {
            do {
                let inviteId = try await familyRepository.redeemShareCode(code: trimmedCode)
                let familyId = try? await familyRepository.getFamilyIdFromInvite(inviteId: inviteId)
                isJoining = false
                redeemedInviteId = inviteId
                redeemedFamilyId = familyId
                AnalyticsService.shared.log(.familyJoinCodeRedeemed)
                AnalyticsService.shared.log(.shareCodeUsed(type: "family"))
                showInviteDetail = true
            } catch {
                isJoining = false
                errorMessage = error.localizedDescription
                showError = true
                AnalyticsService.shared.log(.familyJoinFailed(error: error.localizedDescription))
                FriendsFamilyInviteAnalytics.logInviteFailure(error)
            }
        }
    }

    private func extractCode(from scannedString: String) -> String {
        if let url = URL(string: scannedString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let codeItem = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return codeItem
        }
        return scannedString
    }
}
