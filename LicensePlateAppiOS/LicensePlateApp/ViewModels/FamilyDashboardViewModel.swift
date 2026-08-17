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
    /// Pending outgoing family invites (any sender) for the active family — visible to all members.
    @Published var outgoingPendingInvites: [Invite] = []
    /// Accepted family invite while the user has no active family (awaiting captain approval).
    @Published var awaitingApprovalInvite: Invite?
    @Published var activeShareCode: ShareCode?
    /// COPPA F-8 (FR-20): read-only mirror of the repository's member-doc `isChild`
    /// projection, so dashboard rows render a badge without deriving anything.
    @Published private(set) var childMemberIds: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let familyRepository: FamilyRepository
    private let userRepository: UserRepository
    private let inviteConsumptionStore: FamilyInviteConsumptionStore
    private var inviteRepository: InviteRepository?
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    private var isLoadingData = false
    private var hasInviteObservation = false
    /// Fix 3 (2026-08-16) re-entrancy guard — see `refreshMemberIdentitiesIfNeeded()`.
    private var isRefreshingMemberIdentities = false

    init(
        familyRepository: FamilyRepository,
        userRepository: UserRepository,
        authService: FirebaseAuthService,
        inviteConsumptionStore: FamilyInviteConsumptionStore = .shared
    ) {
        self.familyRepository = familyRepository
        self.userRepository = userRepository
        self.authService = authService
        self.inviteConsumptionStore = inviteConsumptionStore

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
            
            // Observe invite changes once — setAuthService no longer clears sinks every appear.
            if !hasInviteObservation {
                inviteRepository?.$invites
                    .sink { [weak self] _ in
                        self?.refreshOutgoingPendingInvites()
                        self?.refreshAwaitingApprovalInvite()
                        self?.objectWillChange.send()
                    }
                    .store(in: &cancellables)

                inviteRepository?.$familyInvites
                    .sink { [weak self] _ in
                        self?.refreshOutgoingPendingInvites()
                    }
                    .store(in: &cancellables)

                hasInviteObservation = true
                refreshAwaitingApprovalInvite()
            }
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
        // Same instance every appear after the first swap from the temp init service.
        guard service !== authService else { return }
        
        // Cancel old subscriptions
        cancellables.removeAll()
        hasInviteObservation = false
        
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

        // FR-20: the child projection lives beside the member rows (frozen schema,
        // §7.4), so it publishes on its own channel.
        familyRepository.$childMemberFlags
            .sink { [weak self] flagsByFamily in
                guard let self, let familyId = self.family?.familyId else { return }
                self.childMemberIds = Set((flagsByFamily[familyId] ?? [:]).filter { $0.value }.keys)
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
                        self?.childMemberIds = []
                        self?.pendingRequests = []
                        self?.outgoingPendingInvites = []
                        self?.activeShareCode = nil
                        self?.inviteRepository?.stopListeningForFamily()
                        self?.refreshAwaitingApprovalInvite()
                    }
                    return
                }
                
                // If activeFamilyId changed, reload data without wiping a seeded/cached List.
                if self.family?.familyId != activeFamilyId {
                    self.loadData(showLoading: self.family == nil)
                }
            }
            .store(in: &cancellables)
    }
    
    func onAppear() {
        AnalyticsService.shared.log(.familyScreenOpened)
        AnalyticsService.shared.logScreenView(screenName: "family_dashboard")
        seedFromCacheIfNeeded()
        // Soft-refresh when cache already painted the List; spinner only on true first load.
        loadData(showLoading: family == nil)
    }

    /// Fix 3 (2026-08-16, owner report): "the captain's Family page keeps showing the
    /// old cached values indefinitely — as if it's not updating its source of truth."
    /// Root cause: `UserRepository.getUser` is cache-first and, once a member's
    /// `AppUser` is hydrated, never re-hits Firestore for that id again this session —
    /// so an avatar/username changed elsewhere never reaches an already-open roster.
    /// This forces one fresh read of the currently-known member and pending-request
    /// user docs via the repository's existing (non-cache-first) refresh path. Not a
    /// listener — the SRS direction is fetch-refresh for now; a live subscription is a
    /// reasonable follow-up.
    ///
    /// Deliberately kept OUT of `onAppear`/`loadData`: `FamilyDashboardViewModel` has
    /// no dedicated tests today, but keeping this a separate, guarded call preserves
    /// the option to test `loadData` without touching the network later. The view
    /// calls this separately from `.onAppear`. Guarded so overlapping appearances only
    /// run one refresh at a time (resets once the fetch completes, so the next
    /// appearance still refreshes).
    func refreshMemberIdentitiesIfNeeded() {
        guard !isRefreshingMemberIdentities else { return }
        guard let refreshingFamilyId = family?.familyId else { return }
        let userIds = Set(members.map(\.userId)).union(pendingRequests.map(\.userId))
        guard !userIds.isEmpty else { return }

        isRefreshingMemberIdentities = true
        Task { [weak self] in
            guard let self else { return }
            await self.userRepository.refreshUsersFromFirestoreIfPresent(userIds: userIds)
            if self.family?.familyId == refreshingFamilyId {
                self.members = self.familyRepository.getMembers(familyId: refreshingFamilyId)
                self.pendingRequests = self.familyRepository.getPendingRequests(familyId: refreshingFamilyId)
            }
            self.isRefreshingMemberIdentities = false
        }
    }

    /// Paint SwiftData cache immediately so re-entry does not flash empty → spinner → list.
    private func seedFromCacheIfNeeded() {
        guard family == nil,
              let activeFamilyId = authService.currentUser?.activeFamilyId,
              let cached = familyRepository.getFamily(familyId: activeFamilyId),
              cached.statusEnum == .active else {
            return
        }
        family = cached
        loadFamilyData(familyId: activeFamilyId)
        inviteRepository?.startListeningForFamily(familyId: activeFamilyId)
        refreshOutgoingPendingInvites(familyId: activeFamilyId)
        awaitingApprovalInvite = nil
    }

    func loadData(showLoading: Bool = true) {
        guard (authService.currentUser?.firebaseUID ?? authService.currentUser?.id) != nil else {
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
                    self.childMemberIds = []
                    self.pendingRequests = []
                    self.outgoingPendingInvites = []
                    self.activeShareCode = nil
                    self.isLoading = false
                    self.inviteRepository?.stopListeningForFamily()
                    self.refreshAwaitingApprovalInvite()
                    self.handFamilyListeningBackToBadge()
                    return nil
                }
                
                // Full-screen spinner only when there is nothing to show yet.
                if showLoading && self.family == nil {
                    self.isLoading = true
                }
                
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
                            self.childMemberIds = []
                            self.pendingRequests = []
                            self.outgoingPendingInvites = []
                            self.activeShareCode = nil
                            self.isLoading = false
                            self.inviteRepository?.stopListeningForFamily()
                            self.refreshAwaitingApprovalInvite()
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
                        self.inviteRepository?.startListeningForFamily(familyId: activeFamilyId)
                        self.refreshOutgoingPendingInvites(familyId: activeFamilyId)
                        // Keep badge projection in sync with the shared family listen.
                        SocialInboxBadgeService.shared.reassertBoundFamilyListening()
                    }
                    
                    let canManage = await MainActor.run {
                        self.family = fetchedFamily
                        self.members = membersWithUsers
                        self.pendingRequests = pendingWithUsers
                        self.childMemberIds = self.familyRepository.childMemberIds(familyId: activeFamilyId)
                        self.awaitingApprovalInvite = nil
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
                        self.childMemberIds = []
                        self.pendingRequests = []
                        self.outgoingPendingInvites = []
                        self.activeShareCode = nil
                        self.isLoading = false
                        self.inviteRepository?.stopListeningForFamily()
                        self.refreshAwaitingApprovalInvite()
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
                        self.childMemberIds = []
                        self.pendingRequests = []
                        self.outgoingPendingInvites = []
                        self.activeShareCode = nil
                        self.isLoading = false
                        self.inviteRepository?.stopListeningForFamily()
                        self.refreshAwaitingApprovalInvite()
                        self.handFamilyListeningBackToBadge()
                    }
                } else {
                    // Fall back to SwiftData cache only if online fetch failed
                    // Don't start listeners if we're offline - wait for next successful fetch
                    let canManage = await MainActor.run {
                        self.family = cachedFamily
                        self.loadFamilyData(familyId: activeFamilyId)
                        if cachedFamily != nil {
                            self.inviteRepository?.startListeningForFamily(familyId: activeFamilyId)
                            self.refreshOutgoingPendingInvites(familyId: activeFamilyId)
                            self.awaitingApprovalInvite = nil
                        } else {
                            self.refreshAwaitingApprovalInvite()
                        }
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
        childMemberIds = familyRepository.childMemberIds(familyId: familyId)
        refreshOutgoingPendingInvites(familyId: familyId)
    }

    /// FR-20 render projection for member rows.
    func isChildMember(memberId: String) -> Bool {
        childMemberIds.contains(memberId)
    }

    /// FR-86 render projection for pending rows (device pass 2026-08-17).
    ///
    /// Read straight through to the repository rather than mirrored into a `@Published`, and
    /// that is deliberate: unlike `childMemberIds` — which can change on its own when a
    /// correction lands with no row change — the stamps are only ever written by the same
    /// decode that republishes `pendingRequests` immediately afterwards, so the row publish
    /// is already the render trigger and a mirror would only add a way for the two to drift.
    /// `nil` keeps the existing "Pending User" + placeholder fallback.
    func identityStamp(for request: PendingJoinRequest) -> PendingIdentityStamp? {
        familyRepository.pendingIdentityStamp(
            familyId: request.familyId,
            requestId: request.requestId
        )
    }

    private func refreshOutgoingPendingInvites(familyId: String? = nil) {
        let resolvedFamilyId = familyId ?? family?.familyId
        guard let resolvedFamilyId,
              let inviteRepository else {
            outgoingPendingInvites = []
            return
        }
        outgoingPendingInvites = inviteRepository.getPendingFamilyInvites(familyId: resolvedFamilyId)
    }

    /// Accepted invite(s) while the user has no active family — empty dashboard "waiting for approval".
    private func refreshAwaitingApprovalInvite() {
        guard family == nil,
              authService.currentUser?.activeFamilyId == nil,
              let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id,
              let inviteRepository else {
            awaitingApprovalInvite = nil
            return
        }
        awaitingApprovalInvite = FamilyAwaitingApprovalFilter.primaryAwaitingApprovalInvite(
            from: inviteRepository.invites,
            userId: userId,
            consumedInviteIds: inviteConsumptionStore.consumedInviteIds
        )
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
        
        // Clear from SwiftData; sticky family unlock until cloud hydrate
        await MainActor.run {
            user.activeFamilyId = nil
            user.wasEverInFamily = true
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

