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
    static let shared = FriendshipRepository()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    /// Last `userId` passed to `startListening`, used to refresh `friendships` after local deletes.
    private var lastListeningUserId: String?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    
    @Published var friendships: [Friendship] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        // Private initializer prevents external instantiation
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Sync from Firestore
    
    /// Start listening to friendships for a user
    func startListening(userId: String) {
        stopListening()
        lastListeningUserId = userId
        
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
    
    // MARK: - Cloud Functions
    
    /// Send a friend invite to a user
    func sendFriendInvite(toUserId: String, method: String = "search") async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FriendshipRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let sendInviteFunction = functions.httpsCallable("sendFriendInvite")
        
        let result = try await sendInviteFunction.call(([
            "toUserId": toUserId,
            "method": method
        ] as [String: Any]).addingClientMetadata())
        
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
        
        _ = try await respondFunction.call(([
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline"
        ] as [String: Any]).addingClientMetadata())
    }

    /// Remove an accepted friendship via Cloud Function; drops local SwiftData row when the server succeeds.
    func removeFriend(friendshipId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FriendshipRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }

        let functions = Functions.functions()
        let fn = functions.httpsCallable("removeFriend")

        _ = try await fn.call(([
            "friendshipId": friendshipId
        ] as [String: Any]).addingClientMetadata())

        deleteLocalFriendship(friendshipId: friendshipId)
    }

    private func deleteLocalFriendship(friendshipId: String) {
        guard let modelContext = modelContext else { return }
        let searchId = friendshipId
        let descriptor = FetchDescriptor<Friendship>(
            predicate: #Predicate<Friendship> { $0.friendshipId == searchId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }

        if let userId = lastListeningUserId {
            let uid = userId
            let refreshDescriptor = FetchDescriptor<Friendship>(
                predicate: #Predicate<Friendship> { $0.userA == uid || $0.userB == uid }
            )
            if let allFriendships = try? modelContext.fetch(refreshDescriptor) {
                friendships = allFriendships
            }
        }
    }
    
    deinit {
        stopListening()
    }
}

