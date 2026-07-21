//
//  CreateFamilyViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class CreateFamilyViewModel: ObservableObject {
    @Published var familyName = ""
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published private(set) var didCreateSuccessfully = false

    private var authService: FirebaseAuthService?
    private let familyRepository: FamilyRepository

    init(familyRepository: FamilyRepository = .shared) {
        self.familyRepository = familyRepository
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
    }

    func onAppear() {
        AnalyticsService.shared.log(.familyCreateCTATapped)
    }

    func createFamily() {
        let trimmedName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                _ = try await familyRepository.createFamily(name: trimmedName)
                try await authService.refreshCurrentUserFromFirestore()
                isCreating = false
                didCreateSuccessfully = true
                AnalyticsService.shared.log(.familyCreated)
            } catch {
                isCreating = false
                errorMessage = error.localizedDescription
                showError = true
                AnalyticsService.shared.log(.familyCreateFailed(error: error.localizedDescription))
            }
        }
    }
}
