//
//  FriendsHubViewModel.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import Combine

@MainActor
class FriendsHubViewModel: ObservableObject {
    @Published var friends: [Friendship] = []
    @Published var incomingRequests: [Friendship] = []
    @Published var outgoingRequests: [Friendship] = []
    @Published var incomingFriendInvites: [Invite] = []
    @Published var outgoingFriendInvites: [Invite] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: FriendsTab = .friends
    
    private let friendshipRepository: FriendshipRepository
    private let inviteRepository: InviteRepository
    private var authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    
    enum FriendsTab {
        case friends
        case requests
    }
    
    init(friendshipRepository: FriendshipRepository, inviteRepository: InviteRepository, authService: FirebaseAuthService) {
        self.friendshipRepository = friendshipRepository
        self.inviteRepository = inviteRepository
        self.authService = authService
        // Don't set up observers here - wait until we have the real authService with a user
    }
    
    func setModelContext(_ context: ModelContext) {
        friendshipRepository.setModelContext(context)
        inviteRepository.setModelContext(context)
    }
    
    func setAuthService(_ service: FirebaseAuthService) {
        // Cancel old subscriptions
        cancellables.removeAll()
        
        // Update authService
        authService = service
        
        // Only set up observers if we have a valid user
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            print("⚠️ FriendsHubViewModel.setAuthService: No user available yet, will wait for user")
            // Set up observer to wait for user
            setupUserObserver()
            return
        }
        
        print("🔍 FriendsHubViewModel.setAuthService: User available: \(userId), setting up observers")
        // We have a user, set up all observers
        setupObservers(userId: userId)
        // Immediately process current invites
        updateFriendInvites(inviteRepository.invites, userId: userId)
    }
    
    private func setupUserObserver() {
        // Wait for user to become available
        authService.$currentUser
            .sink { [weak self] user in
                guard let self = self, let user = user else { return }
                let userId = user.firebaseUID ?? user.id
                print("🔍 FriendsHubViewModel: User became available: \(userId), setting up observers")
                // Cancel the user observer and set up all observers
                self.cancellables.removeAll()
                self.setupObservers(userId: userId)
                self.loadData()
            }
            .store(in: &cancellables)
    }
    
    private func setupObservers(userId: String) {
        // Observe repository changes
        friendshipRepository.$friendships
            .sink { [weak self] friendships in
                self?.updateFriendships(friendships)
            }
            .store(in: &cancellables)
        
        // Observe invite changes - we know we have a user here
        inviteRepository.$invites
            .sink { [weak self] invites in
                guard let self = self else { return }
                print("🔍 FriendsHubViewModel: Received \(invites.count) invites from publisher, userId: \(userId)")
                self.updateFriendInvites(invites, userId: userId)
            }
            .store(in: &cancellables)
        
        // Observe auth service changes to reload data when user changes
        authService.$currentUser
            .sink { [weak self] user in
                guard let self = self, let user = user else { return }
                let currentUserId = user.firebaseUID ?? user.id
                self.loadData()
                // Update invites with current data
                self.updateFriendInvites(self.inviteRepository.invites, userId: currentUserId)
            }
            .store(in: &cancellables)
    }
    
    func loadData() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        isLoading = true
        
        // Start listening to Firestore updates
        friendshipRepository.startListening(userId: userId)
        inviteRepository.startListening(userId: userId)
        
        // Load from SwiftData cache
        updateFriendships(friendshipRepository.getFriendships(for: userId))
        updateFriendInvites(inviteRepository.getFriendInvites(for: userId), userId: userId)
        
        isLoading = false
    }
    
    private func updateFriendships(_ allFriendships: [Friendship]) {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        friends = allFriendships.filter { $0.statusEnum == .accepted }
        incomingRequests = allFriendships.filter { 
            $0.statusEnum == .pending && $0.initiatedBy != userId
        }
        outgoingRequests = allFriendships.filter { 
            $0.statusEnum == .pending && $0.initiatedBy == userId
        }
    }
    
    private func updateFriendInvites(_ allInvites: [Invite], userId: String) {
        print("🔍 FriendsHubViewModel.updateFriendInvites: Processing \(allInvites.count) total invites for userId: \(userId)")
        
        for invite in allInvites {
            print(invite.toFirestoreData())
        }
        // Filter for friend invites that are pending
        // Friend invites don't expire, so we don't check isExpired
        let friendInvites = allInvites.filter { invite in
            invite.typeEnum == .friend && 
            invite.statusEnum == .pending
        }
        print("  - After filtering for friend type, pending: \(friendInvites.count) invites")
        
        let incoming = friendInvites.filter { $0.toUserId == userId }
        let outgoing = friendInvites.filter { $0.fromUserId == userId }
        
        print("  - Incoming friend invites: \(incoming.count)")
        print("  - Outgoing friend invites: \(outgoing.count)")
        
        incomingFriendInvites = incoming
        outgoingFriendInvites = outgoing
    }
    
    func removeFriend(_ friendship: Friendship) {
        // This will be handled via Cloud Function
        // For now, just log analytics
        AnalyticsService.shared.log(.friendRemoved)
    }
    
    /// Count of pending friend requests (incoming) - includes both invites and legacy friendships
    var pendingFriendRequestsCount: Int {
        return incomingRequests.count + incomingFriendInvites.count
    }
}

