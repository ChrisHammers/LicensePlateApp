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

    private func requireRegisteredAccount() throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(
                domain: "FriendshipRepository",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You are not signed in. Sign in and try again."]
            )
        }
        guard Auth.auth().currentUser?.isAnonymous == false else {
            throw NSError(
                domain: "FriendshipRepository",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Create an account to use Friends & Family features."]
            )
        }
    }

    private func invokeCallable(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        try requireRegisteredAccount()
        try await AppCheckReadiness.ensureCallablePrerequisites()

        let fn = Functions.functions().httpsCallable(name)
        let result: HTTPSCallableResult
        do {
            result = try await fn.call(data.addingClientMetadata())
        } catch {
            throw Self.userFacingCallableError(error)
        }

        guard let response = result.data as? [String: Any] else {
            throw NSError(
                domain: "FriendshipRepository",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from \(name)"]
            )
        }
        return response
    }
    
    /// Send a friend invite to a user
    func sendFriendInvite(toUserId: String, method: String = "search") async throws -> String {
        let data = try await invokeCallable("sendFriendInvite", data: [
            "toUserId": toUserId,
            "method": method,
        ])

        guard let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FriendshipRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from sendFriendInvite"])
        }

        return inviteId
    }
    
    /// Respond to a friend invite (accept or decline)
    func respondToFriendInvite(inviteId: String, accept: Bool) async throws {
        _ = try await invokeCallable("respondToFriendInvite", data: [
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline",
        ])
    }

    /// Remove an accepted friendship via Cloud Function; drops local SwiftData row when the server succeeds.
    func removeFriend(friendshipId: String) async throws {
        _ = try await invokeCallable("removeFriend", data: [
            "friendshipId": friendshipId,
        ])

        deleteLocalFriendship(friendshipId: friendshipId)
    }

    private static func userFacingCallableError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }

        let message: String
        switch code {
        case .unauthenticated:
            if Auth.auth().currentUser == nil {
                message = "You are not signed in. Sign in and try again."
            } else if Auth.auth().currentUser?.isAnonymous == true {
                message = "Create an account to use Friends & Family features."
            } else {
                message = "The server rejected this request. Sign in and try again."
            }
        case .failedPrecondition:
            message = "Create an account to use Friends & Family features."
        case .permissionDenied:
            message = "You do not have permission to perform this friend action."
        case .alreadyExists:
            message = "A friend request already exists for this user."
        case .unavailable:
            message = "The server is temporarily unavailable. Try again shortly."
        case .internal:
            message = "The server encountered an error. Try again in a moment."
        default:
            return error
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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

