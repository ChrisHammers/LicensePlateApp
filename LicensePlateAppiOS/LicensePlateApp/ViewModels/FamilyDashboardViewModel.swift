//
//  FamilyDashboardViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine
import FirebaseAuth

@MainActor
class FamilyDashboardViewModel: ObservableObject {
    @Published var family: Family?
    @Published var members: [FamilyMember] = []
    @Published var pendingRequests: [PendingJoinRequest] = []
    @Published var activeShareCode: ShareCode?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let familyRepository: FamilyRepository
    private let userRepository: UserRepository
    private var inviteRepository: InviteRepository?
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    private var isLoadingData = false
    
    init(familyRepository: FamilyRepository, userRepository: UserRepository, authService: FirebaseAuthService) {
        self.familyRepository = familyRepository
        self.userRepository = userRepository
        self.authService = authService
        
        // Setup observers
        setupObservers()
        
        // Start expiration timer
        startExpirationTimer()
    }
    
    func setModelContext(_ context: ModelContext) {
        familyRepository.setModelContext(context)
        userRepository.setModelContext(context)
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
        // Note: This observer may trigger with stale SwiftData, but loadData() will fetch fresh from Firestore
        familyRepository.$families
            .sink { [weak self] families in
                // Only use SwiftData cache if we don't have family loaded yet
                // Otherwise, wait for loadData() to fetch from Firestore
                if self?.family == nil,
                   let activeFamily = families.first(where: { $0.statusEnum == .active }) {
                    // This is just initial state - loadData() will fetch fresh from Firestore
                    self?.family = activeFamily
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
                } else if !repositoryMembers.isEmpty {
                    self.members = repositoryMembers
                }
            }
            .store(in: &cancellables)

        // Observe pending requests the same way so linked users refresh the hub
        familyRepository.$pendingRequests
            .sink { [weak self] pendingByFamily in
                guard let self = self,
                      let familyId = self.family?.familyId,
                      pendingByFamily[familyId] != nil else {
                    return
                }
                
                let pendingWithUsers = self.familyRepository.getPendingRequests(familyId: familyId)
                self.pendingRequests = pendingWithUsers
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
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        // Prevent multiple simultaneous loads
        guard !isLoadingData else { return }
        isLoadingData = true
        
        // First, refresh user from Firestore to get latest activeFamilyId (source of truth)
        Task {
            defer {
                Task { @MainActor in
                    self.isLoadingData = false
                }
            }
            // Refresh user to ensure we have latest activeFamilyId
            try? await authService.refreshCurrentUserFromFirestore()
            
            let activeFamilyId: String? = await MainActor.run {
                guard let activeFamilyId = self.authService.currentUser?.activeFamilyId else {
                    // No active family — clear dashboard UI and hand listen ownership back to the badge.
                    self.family = nil
                    self.members = []
                    self.pendingRequests = []
                    self.activeShareCode = nil
                    self.isLoading = false
                    self.handFamilyListeningBackToBadge()
                    return nil
                }
                
                self.isLoading = true
                
                return activeFamilyId
            }
            
            guard let activeFamilyId = activeFamilyId else {
                return
            }
            
            // Always fetch from Firestore first (source of truth)
            do {
                // Fetch family from Firestore (source of truth)
                if let fetchedFamily = try await familyRepository.fetchFamily(familyId: activeFamilyId) {
                    // Check if family is inactive - if so, clear everything and stop listeners
                    if fetchedFamily.statusEnum == .inactive {
                        await MainActor.run {
                            self.familyRepository.clearFamilyFromCache(familyId: activeFamilyId)
                            self.family = nil
                            self.members = []
                            self.pendingRequests = []
                            self.activeShareCode = nil
                            self.isLoading = false
                        }
                        // Clear activeFamilyId from user document
                        await self.clearActiveFamilyId()
                        await MainActor.run {
                            self.handFamilyListeningBackToBadge()
                        }
                        return
                    }
                    
                    // Fetch members and pending requests (awaitable hydration links AppUser)
                    let membersWithUsers = try await familyRepository.fetchMembers(familyId: activeFamilyId)
                    let pendingWithUsers = try await familyRepository.fetchPendingRequests(familyId: activeFamilyId)
                    
                    // Only start listening if we successfully fetched members (have permissions)
                    await MainActor.run {
                        self.familyRepository.startListening(familyId: activeFamilyId)
                        // Keep badge projection in sync with the shared family listen.
                        SocialInboxBadgeService.shared.reassertBoundFamilyListening()
                    }
                    
                    let canManage = await MainActor.run {
                        self.family = fetchedFamily
                        self.members = membersWithUsers
                        self.pendingRequests = pendingWithUsers
                        self.isLoading = false
                        
                        // Check if user can manage family (needs members to be set first)
                        return self.canManageFamily
                    }
                    
                    // Load active share code if user can manage family
                    if canManage {
                        await loadActiveShareCode(familyId: activeFamilyId)
                    }
                } else {
                    // Family doesn't exist in Firestore - clear local cache and hand listen back to badge.
                    await MainActor.run {
                        self.familyRepository.clearFamilyFromCache(familyId: activeFamilyId)
                        
                        self.family = nil
                        self.members = []
                        self.pendingRequests = []
                        self.activeShareCode = nil
                        self.isLoading = false
                    }
                    // Clear activeFamilyId from user document
                    await self.clearActiveFamilyId()
                    await MainActor.run {
                        self.handFamilyListeningBackToBadge()
                    }
                }
            } catch {
                // Network error or permission issue - check if family exists and is active
                let cachedFamily = await MainActor.run {
                    self.familyRepository.getFamily(familyId: activeFamilyId)
                }
                
                // If cached family is inactive, clear it and hand listen back to badge
                if let cached = cachedFamily, cached.statusEnum == .inactive {
                    await MainActor.run {
                        self.familyRepository.clearFamilyFromCache(familyId: activeFamilyId)
                        self.family = nil
                        self.members = []
                        self.pendingRequests = []
                        self.activeShareCode = nil
                        self.isLoading = false
                        self.handFamilyListeningBackToBadge()
                    }
                } else {
                    // Fall back to SwiftData cache only if online fetch failed
                    // Don't start listeners if we're offline - wait for next successful fetch
                    let canManage = await MainActor.run {
                        self.family = cachedFamily
                        self.loadFamilyData(familyId: activeFamilyId)
                        self.isLoading = false
                        
                        if self.family == nil {
                            self.errorMessage = "Unable to load family. Please check your connection."
                            self.activeShareCode = nil
                        }
                        
                        // Re-assert badge listen so home approvals stay live after a failed fetch.
                        self.handFamilyListeningBackToBadge()
                        
                        return self.canManageFamily
                    }
                    
                    // Load active share code if user can manage family
                    if canManage {
                        await loadActiveShareCode(familyId: activeFamilyId)
                    }
                }
            }
        }
    }

    /// Family dashboard must not permanently own/tear down listeners the social inbox badge needs.
    private func handFamilyListeningBackToBadge() {
        let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        SocialInboxBadgeService.shared.bind(
            userId: userId,
            activeFamilyId: authService.currentUser?.activeFamilyId
        )
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
    
    /// Clear activeFamilyId from user document (both SwiftData and Firestore)
    private func clearActiveFamilyId() async {
        guard let user = authService.currentUser,
              let firebaseUID = user.firebaseUID ?? Auth.auth().currentUser?.uid else {
            return
        }
        
        // Clear from SwiftData
        await MainActor.run {
            user.activeFamilyId = nil
        }
        
        do {
            try await userRepository.clearActiveFamilyIdFromServer(firebaseUID: firebaseUID)
            try? await authService.saveUserDataToFirestore(user)
        } catch {
            // If update fails, mark for sync
            await MainActor.run {
                user.needsSync = true
            }
            try? await authService.saveUserDataToFirestore(user)
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

