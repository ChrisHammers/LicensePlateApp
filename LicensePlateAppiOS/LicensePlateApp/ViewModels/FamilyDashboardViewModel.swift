//
//  FamilyDashboardViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine

@MainActor
class FamilyDashboardViewModel: ObservableObject {
    @Published var family: Family?
    @Published var members: [FamilyMember] = []
    @Published var pendingRequests: [PendingJoinRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let familyRepository: FamilyRepository
    private let authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    
    init(familyRepository: FamilyRepository, authService: FirebaseAuthService) {
        self.familyRepository = familyRepository
        self.authService = authService
        
        // Observe repository changes
        familyRepository.$families
            .sink { [weak self] families in
                if let activeFamily = families.first(where: { $0.statusEnum == .active }) {
                    self?.family = activeFamily
                    self?.loadFamilyData(familyId: activeFamily.familyId)
                }
            }
            .store(in: &cancellables)
    }
    
    func setModelContext(_ context: ModelContext) {
        familyRepository.setModelContext(context)
    }
    
    func loadData() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let activeFamilyId = authService.currentUser?.activeFamilyId else {
            return
        }
        
        isLoading = true
        
        // Start listening to Firestore updates
        familyRepository.startListening(familyId: activeFamilyId)
        
        // Load from SwiftData cache
        family = familyRepository.getFamily(familyId: activeFamilyId)
        loadFamilyData(familyId: activeFamilyId)
        
        isLoading = false
    }
    
    private func loadFamilyData(familyId: String) {
        members = familyRepository.getMembers(familyId: familyId)
        pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
    }
    
    var currentUserRole: FamilyMember.FamilyRole? {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let member = members.first(where: { $0.userId == userId }) else {
            return nil
        }
        return member.roleEnum
    }
    
    var canManageFamily: Bool {
        guard let role = currentUserRole else { return false }
        return role == .creator || role == .captain
    }
}

