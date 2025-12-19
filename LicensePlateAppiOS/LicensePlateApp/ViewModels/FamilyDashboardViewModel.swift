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
    private var inviteRepository: InviteRepository?
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    
    init(familyRepository: FamilyRepository, authService: FirebaseAuthService) {
        self.familyRepository = familyRepository
        self.authService = authService
        
        // Setup observers
        setupObservers()
    }
    
    func setModelContext(_ context: ModelContext) {
        familyRepository.setModelContext(context)
        if inviteRepository == nil {
            inviteRepository = InviteRepository.shared
        }
        inviteRepository?.setModelContext(context)
        
        // Start listening to invites for badge counts
        if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
            inviteRepository?.startListening(userId: userId)
            
            // Observe invite changes for real-time badge updates
            inviteRepository?.$invites
                .sink { [weak self] _ in
                    // Trigger view update by accessing the count property
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
    
    func setAuthService(_ service: FirebaseAuthService) {
        // Cancel old subscriptions
        cancellables.removeAll()
        
        // Update authService
        authService = service
        
        // Re-setup observers with new authService
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe repository changes
        familyRepository.$families
            .sink { [weak self] families in
                if let activeFamily = families.first(where: { $0.statusEnum == .active }) {
                    self?.family = activeFamily
                    self?.loadFamilyData(familyId: activeFamily.familyId)
                }
            }
            .store(in: &cancellables)
        
        // Observe user changes to reload when activeFamilyId changes
        authService.$currentUser
            .sink { [weak self] user in
                guard let self = self,
                      let activeFamilyId = user?.activeFamilyId else {
                    // If user no longer has activeFamilyId, clear family
                    if user?.activeFamilyId == nil {
                        self?.family = nil
                        self?.members = []
                        self?.pendingRequests = []
                    }
                    return
                }
                
                // If activeFamilyId changed, reload data
                if self.family?.familyId != activeFamilyId {
                    self.loadData()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadData() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let activeFamilyId = authService.currentUser?.activeFamilyId else {
            return
        }
        
        isLoading = true
        
        // Start listening to Firestore updates for real-time sync
        familyRepository.startListening(familyId: activeFamilyId)
        
        // Always fetch from Firestore first (online priority)
        Task {
            do {
                // Fetch family from Firestore
                if let fetchedFamily = try await familyRepository.fetchFamily(familyId: activeFamilyId) {
                    // Fetch members and pending requests
                    let fetchedMembers = try await familyRepository.fetchMembers(familyId: activeFamilyId)
                    let fetchedPending = try await familyRepository.fetchPendingRequests(familyId: activeFamilyId)
                    
                    await MainActor.run {
                        self.family = fetchedFamily
                        self.members = fetchedMembers
                        self.pendingRequests = fetchedPending
                        self.isLoading = false
                    }
                } else {
                    // Family doesn't exist in Firestore - might be data inconsistency
                    // Fall back to SwiftData cache in case of offline changes
                    await MainActor.run {
                        self.family = self.familyRepository.getFamily(familyId: activeFamilyId)
                        self.loadFamilyData(familyId: activeFamilyId)
                        self.isLoading = false
                        
                        if self.family == nil {
                            self.errorMessage = "Family not found"
                        }
                    }
                }
            } catch {
                // Network error or permission issue - fall back to SwiftData cache
                await MainActor.run {
                    self.family = self.familyRepository.getFamily(familyId: activeFamilyId)
                    self.loadFamilyData(familyId: activeFamilyId)
                    self.isLoading = false
                    
                    if self.family == nil {
                        self.errorMessage = "Unable to load family. Please check your connection."
                    }
                }
            }
        }
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
    
    /// Count of pending family invites received by the current user
    var pendingFamilyInvitesCount: Int {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let inviteRepository = inviteRepository else {
            return 0
        }
        let familyInvites = inviteRepository.getFamilyInvites(for: userId)
        return familyInvites.filter { 
            $0.toUserId == userId && $0.statusEnum == .pending 
        }.count
    }
    
    /// Count of pending member requests (for creators/captains to approve)
    var pendingMemberRequestsCount: Int {
        guard canManageFamily else { return 0 }
        return pendingRequests.filter { $0.statusEnum == .pending }.count
    }
}

