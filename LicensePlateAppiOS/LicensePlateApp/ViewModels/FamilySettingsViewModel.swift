//
//  FamilySettingsViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine

@MainActor
class FamilySettingsViewModel: ObservableObject {
    @Published var familyName: String = ""
    @Published var members: [FamilyMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showErrorAlert = false
    @Published var isLeavingFamily = false
    @Published var isDeletingFamily = false
    @Published var isSavingName = false
    @Published var isRemovingMember = false
    @Published var didLeaveOrDelete = false
    @Published var memberIdPendingRemoval: String?

    private let familyRepository: FamilyRepository
    private var authService: FirebaseAuthService
    private(set) var familyId: String = ""
    private var lastSavedFamilyName: String = ""

    var family: Family?

    init(familyRepository: FamilyRepository, authService: FirebaseAuthService) {
        self.familyRepository = familyRepository
        self.authService = authService
    }

    func setModelContext(_ context: ModelContext) {
        familyRepository.setModelContext(context)
    }

    func setAuthService(_ service: FirebaseAuthService) {
        authService = service
    }

    func loadData(familyId: String) {
        self.familyId = familyId
        family = familyRepository.getFamily(familyId: familyId)
        members = familyRepository.getMembers(familyId: familyId)

        if let family = family {
            familyName = family.name
            lastSavedFamilyName = family.name
        }
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    var isCreator: Bool {
        guard let userId = currentUserId else {
            return false
        }
        if let creatorId = family?.creatorId {
            return creatorId == userId
        }
        guard let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.roleEnum == .creator
    }

    var canRemoveMembers: Bool { isCreator }

    var isCaptainOrCreator: Bool {
        guard let userId = currentUserId,
              let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.isCaptainOrCreator
    }

    func canRemove(memberId: String) -> Bool {
        guard canRemoveMembers else { return false }
        guard let userId = currentUserId else { return false }
        return memberId != userId
    }

    func saveFamilyName() {
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            familyName = lastSavedFamilyName
            errorMessage = "Enter family name".localized
            showErrorAlert = true
            return
        }
        guard trimmed != lastSavedFamilyName else { return }
        guard authService.isOnline else {
            familyName = lastSavedFamilyName
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }

        isSavingName = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.updateFamilyName(familyId: familyId, name: trimmed)
                familyName = trimmed
                lastSavedFamilyName = trimmed
                family?.name = trimmed
                isSavingName = false
                AnalyticsService.shared.log(.familyNameChanged)
            } catch {
                familyName = lastSavedFamilyName
                isSavingName = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    func cancelFamilyNameEditing() {
        familyName = lastSavedFamilyName
    }

    func leaveFamily() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }

        isLeavingFamily = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.leaveFamily(familyId: familyId)
                AnalyticsService.shared.log(.familyMemberRemoved)
                isLeavingFamily = false
                didLeaveOrDelete = true
            } catch {
                isLeavingFamily = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    func confirmRemoveMember(memberId: String) {
        guard canRemove(memberId: memberId) else { return }
        memberIdPendingRemoval = memberId
    }

    func cancelRemoveMember() {
        memberIdPendingRemoval = nil
    }

    func removePendingMember() {
        guard let memberId = memberIdPendingRemoval else { return }
        memberIdPendingRemoval = nil
        removeMember(memberId: memberId)
    }

    func removeMember(memberId: String) {
        guard canRemove(memberId: memberId) else {
            errorMessage = "Only the family creator can remove members.".localized
            showErrorAlert = true
            return
        }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        guard !isRemovingMember else { return }

        isRemovingMember = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.removeMember(familyId: familyId, memberId: memberId)
                AnalyticsService.shared.log(.familyMemberRemoved)
                members = familyRepository.getMembers(familyId: familyId)
                isRemovingMember = false
            } catch {
                isRemovingMember = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    func deleteFamily() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        guard !isDeletingFamily else { return }

        isDeletingFamily = true
        errorMessage = nil

        Task {
            do {
                try await familyRepository.deleteFamily(familyId: familyId)
                try? await authService.refreshCurrentUserFromFirestore()
                let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
                SocialInboxBadgeService.shared.bind(
                    userId: userId,
                    activeFamilyId: authService.currentUser?.activeFamilyId
                )
                AnalyticsService.shared.log(.familyMarkedInactiveCreatorLeftOrDeleted)
                isDeletingFamily = false
                didLeaveOrDelete = true
            } catch {
                isDeletingFamily = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
