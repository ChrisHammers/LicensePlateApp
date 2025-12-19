//
//  InviteRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import Combine

@MainActor
class InviteRepository: ObservableObject {
    static let shared = InviteRepository()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    
    @Published var invites: [Invite] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        // Private initializer prevents external instantiation
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Sync from Firestore
    
    /// Start listening to invites for a user (both sent and received)
  // TODO: do we want this to not just use WHO you are?
    func startListening(userId: String) {
        stopListening()
        
        // Query invites where user is sender or recipient
        let query = db.collection("invites")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        listeners.append(listener)
        
        // Also listen to invites sent by this user
        let sentQuery = db.collection("invites")
            .whereField("fromUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
        
        let sentListener = sentQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        listeners.append(sentListener)
    }
    
    private func handleSnapshot(snapshot: QuerySnapshot?, error: Error?, userId: String) {
        if let error = error {
            errorMessage = "Error fetching invites: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        var updatedInvites: [Invite] = []
        
        for document in snapshot.documents {
            if let invite = Invite(from: document) {
                updatedInvites.append(invite)
                
                // Sync to SwiftData
                let searchInviteId = invite.inviteId
                let descriptor = FetchDescriptor<Invite>(
                    predicate: #Predicate<Invite> { i in
                        i.inviteId == searchInviteId
                    }
                )
                
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update existing
                    existing.type = invite.type
                    existing.fromUserId = invite.fromUserId
                    existing.toUserId = invite.toUserId
                    existing.familyId = invite.familyId
                    existing.status = invite.status
                    existing.method = invite.method
                    existing.codeId = invite.codeId
                    existing.expiresAt = invite.expiresAt
                    existing.createdAt = invite.createdAt
                    existing.respondedAt = invite.respondedAt
                } else {
                    // Insert new
                    modelContext.insert(invite)
                }
            }
        }
        
        // Merge all invites
        let searchUserId = userId
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.fromUserId == searchUserId || invite.toUserId == searchUserId
            }
        )
        
        if let allInvites = try? modelContext.fetch(descriptor) {
            invites = allInvites
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
    
    /// Get all invites for a user (from SwiftData)
    func getInvites(for userId: String) -> [Invite] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { $0.fromUserId == userId || $0.toUserId == userId }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get incoming invites
    func getIncomingInvites(for userId: String) -> [Invite] {
        guard let modelContext = modelContext else { return [] }
        
        let searchUserId = userId
        let pendingStatus = "pending"
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.toUserId == searchUserId && invite.status == pendingStatus
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get outgoing invites
    func getOutgoingInvites(for userId: String) -> [Invite] {
        guard let modelContext = modelContext else { return [] }
        
        let searchUserId = userId
        let pendingStatus = "pending"
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.fromUserId == searchUserId && invite.status == pendingStatus
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get friend invites
    func getFriendInvites(for userId: String) -> [Invite] {
        getInvites(for: userId).filter { $0.typeEnum == .friend }
    }
    
    /// Get family invites
    func getFamilyInvites(for userId: String) -> [Invite] {
        getInvites(for: userId).filter { $0.typeEnum == .family }
    }
    
    deinit {
        stopListening()
    }
}

