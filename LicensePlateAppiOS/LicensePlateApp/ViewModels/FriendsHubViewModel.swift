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
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: FriendsTab = .friends
    
    private let friendshipRepository: FriendshipRepository
    private let authService: FirebaseAuthService
    private var cancellables = Set<AnyCancellable>()
    
    enum FriendsTab {
        case friends
        case requests
    }
    
    init(friendshipRepository: FriendshipRepository, authService: FirebaseAuthService) {
        self.friendshipRepository = friendshipRepository
        self.authService = authService
        
        // Observe repository changes
        friendshipRepository.$friendships
            .sink { [weak self] friendships in
                self?.updateFriendships(friendships)
            }
            .store(in: &cancellables)
    }
    
    func setModelContext(_ context: ModelContext) {
        friendshipRepository.setModelContext(context)
    }
    
    func loadData() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        isLoading = true
        
        // Start listening to Firestore updates
        friendshipRepository.startListening(userId: userId)
        
        // Load from SwiftData cache
        updateFriendships(friendshipRepository.getFriendships(for: userId))
        
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
    
    func removeFriend(_ friendship: Friendship) {
        // This will be handled via Cloud Function
        // For now, just log analytics
        AnalyticsService.shared.log(.friendRemoved)
    }
}

