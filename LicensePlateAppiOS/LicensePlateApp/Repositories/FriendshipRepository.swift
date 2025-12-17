//
//  FriendshipRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import Combine

@MainActor
class FriendshipRepository: ObservableObject {
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    
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
                let searchFriendshipId = friendship.friendshipId
                let descriptor = FetchDescriptor<Friendship>(
                    predicate: #Predicate<Friendship> { f in
                        f.friendshipId == searchFriendshipId
                    }
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
    nonisolated func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }
    
    // MARK: - Local Queries
    
    /// Get all friendships for a user (from SwiftData)
    func getFriendships(for userId: String) -> [Friendship] {
        guard let modelContext = modelContext else { return [] }
        
        // Extract to local constant for predicate
        let searchUserId = userId
        
        let descriptor = FetchDescriptor<Friendship>(
            predicate: #Predicate<Friendship> { friendship in
                friendship.userA == searchUserId || friendship.userB == searchUserId
            }
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
    
    // MARK: - Cloud Functions
    
    /// Send a friend invite to a user
    func sendFriendInvite(toUserId: String, method: String = "search") async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FriendshipRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let sendInviteFunction = functions.httpsCallable("sendFriendInvite")
        
        let result = try await sendInviteFunction.call([
            "toUserId": toUserId,
            "method": method
        ])
        
        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FriendshipRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from sendFriendInvite"])
        }
        
        return inviteId
    }
    
    /// Respond to a friend invite (accept or decline)
    func respondToFriendInvite(inviteId: String, accept: Bool) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FriendshipRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let respondFunction = functions.httpsCallable("respondToFriendInvite")
        
        _ = try await respondFunction.call([
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline"
        ])
    }
    
    deinit {
        stopListening()
    }
}

