//
//  FriendshipRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import Combine

@MainActor
class FriendshipRepository: ObservableObject {
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    private var listeners: [ListenerRegistration] = []
    
    @Published var friendships: [Friendship] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Sync from Firestore
    
    /// Start listening to friendships for a user
    func startListening(userId: String) {
        stopListening()
        
        // Query where user is either userA or userB
        let queryA = db.collection("friends")
            .whereField("userA", isEqualTo: userId)
        
        let queryB = db.collection("friends")
            .whereField("userB", isEqualTo: userId)
        
        let listenerA = queryA.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        let listenerB = queryB.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        listeners.append(listenerA)
        listeners.append(listenerB)
    }
    
    private func handleSnapshot(snapshot: QuerySnapshot?, error: Error?, userId: String) {
        if let error = error {
            errorMessage = "Error fetching friendships: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        var updatedFriendships: [Friendship] = []
        
        for document in snapshot.documents {
            if let friendship = Friendship(from: document) {
                updatedFriendships.append(friendship)
                
                // Sync to SwiftData
                let descriptor = FetchDescriptor<Friendship>(
                    predicate: #Predicate<Friendship> { $0.friendshipId == friendship.friendshipId }
                )
                
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update existing
                    existing.userA = friendship.userA
                    existing.userB = friendship.userB
                    existing.status = friendship.status
                    existing.initiatedBy = friendship.initiatedBy
                    existing.createdAt = friendship.createdAt
                    existing.respondedAt = friendship.respondedAt
                } else {
                    // Insert new
                    modelContext.insert(friendship)
                }
            }
        }
        
        // Merge all friendships
        let descriptor = FetchDescriptor<Friendship>(
            predicate: #Predicate<Friendship> { $0.userA == userId || $0.userB == userId }
        )
        
        if let allFriendships = try? modelContext.fetch(descriptor) {
            friendships = allFriendships
        }
        
        try? modelContext.save()
    }
    
    /// Stop listening to Firestore updates
    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Local Queries
    
    /// Get all friendships for a user (from SwiftData)
    func getFriendships(for userId: String) -> [Friendship] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Friendship>(
            predicate: #Predicate<Friendship> { $0.userA == userId || $0.userB == userId }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get accepted friendships only
    func getAcceptedFriendships(for userId: String) -> [Friendship] {
        getFriendships(for: userId).filter { $0.statusEnum == .accepted }
    }
    
    /// Get pending friendships (incoming or outgoing)
    func getPendingFriendships(for userId: String) -> [Friendship] {
        getFriendships(for: userId).filter { $0.statusEnum == .pending }
    }
    
    /// Get incoming friend requests
    func getIncomingRequests(for userId: String) -> [Friendship] {
        getPendingFriendships(for: userId).filter { $0.initiatedBy != userId }
    }
    
    /// Get outgoing friend requests
    func getOutgoingRequests(for userId: String) -> [Friendship] {
        getPendingFriendships(for: userId).filter { $0.initiatedBy == userId }
    }
    
    deinit {
        stopListening()
    }
}

