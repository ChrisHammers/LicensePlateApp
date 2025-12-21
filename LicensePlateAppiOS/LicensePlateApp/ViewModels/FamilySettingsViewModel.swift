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
    
    private let familyRepository: FamilyRepository
    private var authService: FirebaseAuthService
    
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
        family = familyRepository.getFamily(familyId: familyId)
        members = familyRepository.getMembers(familyId: familyId)
        
        if let family = family {
            familyName = family.name
        }
    }
    
    var family: Family?
    
    var isCreator: Bool {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.roleEnum == .creator
    }
    
    var isCaptainOrCreator: Bool {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let member = members.first(where: { $0.userId == userId }) else {
            return false
        }
        return member.isCaptainOrCreator
    }
}

