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
    @Published var activeShareCode: ShareCode?
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
        
        // Start expiration timer
        startExpirationTimer()
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
    
    private func startExpirationTimer() {
        // Timer that fires every 5 seconds to check for share code expiration
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Check if current share code has expired
                    if let shareCode = self.activeShareCode {
                        // Check expiration by comparing dates directly
                        if shareCode.expiresAt <= Date() || shareCode.isRevoked {
                            // Share code expired, clear it
                            self.activeShareCode = nil
                            
                            // Optionally reload to check for a new active code
                            if let familyId = self.family?.familyId, self.canManageFamily {
                                await self.loadActiveShareCode(familyId: familyId)
                            }
                        }
                    } else {
                        // If no active code, check if one exists now
                        if let familyId = self.family?.familyId, self.canManageFamily {
                            await self.loadActiveShareCode(familyId: familyId)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func setAuthService(_ service: FirebaseAuthService) {
        // Cancel old subscriptions
        cancellables.removeAll()
        
        // Update authService
        authService = service
        
        // Re-setup observers with new authService
        setupObservers()
        
        // Restart expiration timer
        startExpirationTimer()
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
        
        // Observe repository familyMembers to get updates with user relationships
        familyRepository.$familyMembers
            .sink { [weak self] familyMembers in
                guard let self = self,
                      let familyId = self.family?.familyId,
                      let repositoryMembers = familyMembers[familyId] else {
                    return
                }
                
                // Reload members from SwiftData to get user relationships
                // This ensures we have the linked user data
                let membersWithUsers = self.familyRepository.getMembers(familyId: familyId)
                if !membersWithUsers.isEmpty {
                    self.members = membersWithUsers
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
                        self?.activeShareCode = nil
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
                    
                    // Wait a bit for user linking to complete (fetchAndCacheUsers runs asynchronously)
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Reload members from SwiftData to get user relationships
                    let membersWithUsers = familyRepository.getMembers(familyId: activeFamilyId)
                    
                    let canManage = await MainActor.run {
                        self.family = fetchedFamily
                        self.members = membersWithUsers // Use members with user relationships
                        self.pendingRequests = fetchedPending
                        self.isLoading = false
                        
                        // Check if user can manage family (needs members to be set first)
                        return self.canManageFamily
                    }
                    
                    // Load active share code if user can manage family
                    if canManage {
                        await loadActiveShareCode(familyId: activeFamilyId)
                    }
                } else {
                    // Family doesn't exist in Firestore - might be data inconsistency
                    // Fall back to SwiftData cache in case of offline changes
                    let canManage = await MainActor.run {
                        self.family = self.familyRepository.getFamily(familyId: activeFamilyId)
                        self.loadFamilyData(familyId: activeFamilyId)
                        self.isLoading = false
                        
                        if self.family == nil {
                            self.errorMessage = "Family not found"
                            self.activeShareCode = nil
                        }
                        
                        return self.canManageFamily
                    }
                    
                    // Load active share code if user can manage family
                    if canManage {
                        await loadActiveShareCode(familyId: activeFamilyId)
                    }
                }
            } catch {
                // Network error or permission issue - fall back to SwiftData cache
                let canManage = await MainActor.run {
                    self.family = self.familyRepository.getFamily(familyId: activeFamilyId)
                    self.loadFamilyData(familyId: activeFamilyId)
                    self.isLoading = false
                    
                    if self.family == nil {
                        self.errorMessage = "Unable to load family. Please check your connection."
                        self.activeShareCode = nil
                    }
                    
                    return self.canManageFamily
                }
                
                // Load active share code if user can manage family
                if canManage {
                    await loadActiveShareCode(familyId: activeFamilyId)
                }
            }
        }
    }
    
    private func loadFamilyData(familyId: String) {
        members = familyRepository.getMembers(familyId: familyId)
        pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
    }
    
    /// Load active share code for the family
    func loadActiveShareCode(familyId: String) async {
        do {
            let shareCode = try await familyRepository.getActiveShareCode(familyId: familyId)
            await MainActor.run {
                self.activeShareCode = shareCode
            }
        } catch {
            // If no active share code exists or error occurs, set to nil
            await MainActor.run {
                self.activeShareCode = nil
            }
        }
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
    
    /// Computed property for share code button text
    var shareCodeButtonText: String {
        if let shareCode = activeShareCode, !shareCode.isExpired {
            return "View Active Share Code".localized
        } else {
            return "Create Share Code".localized
        }
    }
}

