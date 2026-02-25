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
    /// Listens to ALL invites (not just pending) so we get updates when status changes
    func startListening(userId: String) {
        stopListening()
        
        // Query ALL invites where user is recipient (not just pending)
        // This ensures we get updates when status changes from pending to declined/accepted
        let query = db.collection("invites")
            .whereField("toUserId", isEqualTo: userId)
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId, isIncoming: true)
            }
        }
        
        listeners.append(listener)
        
        // Also listen to ALL invites sent by this user
        let sentQuery = db.collection("invites")
            .whereField("fromUserId", isEqualTo: userId)
        
        let sentListener = sentQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleSnapshot(snapshot: snapshot, error: error, userId: userId, isIncoming: false)
            }
        }
        
        listeners.append(sentListener)
    }
    
    private func handleSnapshot(snapshot: QuerySnapshot?, error: Error?, userId: String, isIncoming: Bool) {
        if let error = error {
            errorMessage = "Error fetching invites: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        // Process all documents in the snapshot (including status changes)
        // Since we're listening to ALL invites (not just pending), we'll get updates when status changes
        for document in snapshot.documents {
            if let invite = Invite(from: document) {
                // Sync to SwiftData - always update status
                let searchInviteId = invite.inviteId
                let descriptor = FetchDescriptor<Invite>(
                    predicate: #Predicate<Invite> { i in
                        i.inviteId == searchInviteId
                    }
                )
                
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update existing - including status changes (pending -> declined/accepted)
                    existing.type = invite.type
                    existing.fromUserId = invite.fromUserId
                    existing.toUserId = invite.toUserId
                    existing.familyId = invite.familyId
                    existing.status = invite.status  // This will update when declined/accepted
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
        
        // Update published invites array with all invites for this user
        // The ViewModel will filter for pending status
        let searchUserId = userId
        let allInvitesDescriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.fromUserId == searchUserId || invite.toUserId == searchUserId
            }
        )
        
        if let allInvites = try? modelContext.fetch(allInvitesDescriptor) {
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
    
    /// Refresh a specific invite from Firestore to get latest status
    /// Also refreshes the published invites array from cache
    func refreshInvite(inviteId: String, userId: String) async {
        guard let modelContext = modelContext else { return }
        
        let db = Firestore.firestore()
        do {
            let inviteDoc = try await db.collection("invites").document(inviteId).getDocument()
            
            guard let data = inviteDoc.data(),
                  let invite = Invite(from: data, id: inviteId) else {
                // If invite not found, refresh from cache anyway
                refreshInvitesFromCache(userId: userId)
                return
            }
            
            // Update in SwiftData
            let searchInviteId = invite.inviteId
            let descriptor = FetchDescriptor<Invite>(
                predicate: #Predicate<Invite> { i in
                    i.inviteId == searchInviteId
                }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                // Update existing with latest status
                existing.status = invite.status
                existing.respondedAt = invite.respondedAt
                try? modelContext.save()
            } else {
                // Insert new if not found
                modelContext.insert(invite)
                try? modelContext.save()
            }
            
            // Refresh published array from cache
            refreshInvitesFromCache(userId: userId)
        } catch {
            print("⚠️ Failed to refresh invite \(inviteId): \(error.localizedDescription)")
            // Still refresh from cache even if Firestore fetch failed
            refreshInvitesFromCache(userId: userId)
        }
    }
    
    /// Refresh the published invites array from SwiftData cache
    private func refreshInvitesFromCache(userId: String) {
        guard let modelContext = modelContext else { return }
        
        let searchUserId = userId
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.fromUserId == searchUserId || invite.toUserId == searchUserId
            }
        )
        
        if let allInvites = try? modelContext.fetch(descriptor) {
            invites = allInvites
        }
    }
    
    deinit {
        stopListening()
    }
}

