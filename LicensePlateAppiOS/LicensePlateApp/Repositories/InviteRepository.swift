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
    /// User id currently covered by personal Firestore listeners (nil after stop).
    private var listeningUserId: String?
    /// Family id currently covered by the family-scoped invite listener.
    private var listeningFamilyId: String?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    nonisolated(unsafe) private var familyListeners: [ListenerRegistration] = []
    
    @Published var invites: [Invite] = []
    /// Pending + historical family invites for `listeningFamilyId` (member-visible).
    @Published var familyInvites: [Invite] = []
    /// FR-86 render projection for OUTGOING family invites, mirroring
    /// `FamilyRepository.pendingIdentityStamps` one-to-one: the INVITEE identity the server
    /// stamped onto `invites/{id}` (`userName`/`avatarId`), keyed familyId → inviteId, so the
    /// captain's "Waiting for response" row can render a child the captain is forbidden
    /// (FR-12) from resolving via `users/{uid}`. Lives OUTSIDE the `Invite` @Model
    /// deliberately: both VersionedSchemas are frozen, and a `@Transient` would be nil on
    /// every store-fetched row — which is every row the dashboard renders (the exact trap
    /// documented on `PendingJoinRequest`).
    @Published private(set) var inviteIdentityStamps: [String: [String: PendingIdentityStamp]] = [:]
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
        // Avoid tearing down live listeners when home re-asserts the same user (appear / scene active).
        if listeningUserId == userId, !listeners.isEmpty {
            return
        }
        stopPersonalListening()
        listeningUserId = userId
        
        // Query ALL invites where user is recipient (not just pending)
        // This ensures we get updates when status changes from pending to declined/accepted
        let query = db.collection("invites")
            .whereField("toUserId", isEqualTo: userId)
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handlePersonalSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        listeners.append(listener)
        
        // Also listen to ALL invites sent by this user
        let sentQuery = db.collection("invites")
            .whereField("fromUserId", isEqualTo: userId)
        
        let sentListener = sentQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handlePersonalSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        
        listeners.append(sentListener)
    }

    /// Listen to all family-type invites for a family so every member sees outgoing pending invites.
    func startListeningForFamily(familyId: String) {
        if listeningFamilyId == familyId, !familyListeners.isEmpty {
            return
        }
        stopListeningForFamily()
        listeningFamilyId = familyId

        let query = db.collection("invites")
            .whereField("familyId", isEqualTo: familyId)
            .whereField("type", isEqualTo: "family")

        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleFamilySnapshot(snapshot: snapshot, error: error, familyId: familyId)
            }
        }
        familyListeners.append(listener)
    }
    
    private func handlePersonalSnapshot(snapshot: QuerySnapshot?, error: Error?, userId: String) {
        if let error = error {
            errorMessage = "Error fetching invites: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        upsertInvites(from: snapshot, into: modelContext)
        
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

        // Family members may also see these invites via the family listener projection.
        if let listeningFamilyId {
            refreshFamilyInvitesFromCache(familyId: listeningFamilyId)
        }
    }

    private func handleFamilySnapshot(snapshot: QuerySnapshot?, error: Error?, familyId: String) {
        if let error = error {
            errorMessage = "Error fetching family invites: \(error.localizedDescription)"
            return
        }

        guard let snapshot = snapshot, let modelContext = modelContext else { return }

        upsertInvites(from: snapshot, into: modelContext)
        // Capture the FR-86 invitee stamps off the RAW docs before the row publish below —
        // the same snapshot that writes the stamps republishes the rows immediately after,
        // so the row publish is already the render trigger (the ordering argument documented
        // at `FamilyDashboardViewModel.identityStamp(for:)`).
        applyInviteIdentityStamps(
            Self.parseInviteIdentityStamps(
                documents: snapshot.documents.map { ($0.documentID, $0.data()) }
            ),
            familyId: familyId
        )
        try? modelContext.save()
        refreshFamilyInvitesFromCache(familyId: familyId)

        if let listeningUserId {
            refreshInvitesFromCache(userId: listeningUserId)
        }
    }

    private func upsertInvites(from snapshot: QuerySnapshot, into modelContext: ModelContext) {
        for document in snapshot.documents {
            guard let invite = Invite(from: document) else { continue }

            let searchInviteId = invite.inviteId
            let descriptor = FetchDescriptor<Invite>(
                predicate: #Predicate<Invite> { i in
                    i.inviteId == searchInviteId
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
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
                existing.familyName = invite.familyName
            } else {
                modelContext.insert(invite)
            }
        }
    }
    
    /// Stop personal + family Firestore listeners.
    nonisolated func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
        for listener in familyListeners {
            listener.remove()
        }
        familyListeners.removeAll()
    }

    private func stopPersonalListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }

    func stopListeningForFamily() {
        for listener in familyListeners {
            listener.remove()
        }
        familyListeners.removeAll()
        listeningFamilyId = nil
        familyInvites = []
        inviteIdentityStamps = [:]
    }

    // MARK: - FR-86 invitee identity stamps (outgoing invites)

    /// The stamped invitee identity for one outgoing invite, or `nil` when the server
    /// stamped nothing (or the rows came from the SwiftData cache without a decode this
    /// session). Consumers keep their "Pending User" + placeholder fallback for `nil`.
    func inviteIdentityStamp(familyId: String, inviteId: String) -> PendingIdentityStamp? {
        inviteIdentityStamps[familyId]?[inviteId]
    }

    /// Test seam mirroring `FamilyRepository.applyPendingIdentityStamps`: one write point
    /// that does not require a live Firestore snapshot.
    func applyInviteIdentityStamps(_ stamps: [String: PendingIdentityStamp], familyId: String) {
        inviteIdentityStamps[familyId] = stamps
    }

    /// Parses the FR-86 stamps out of a raw invites snapshot. Split out so the decode is
    /// testable without the network — the reinstall shape (cold store, fresh decode) is
    /// exactly what this has to get right.
    static func parseInviteIdentityStamps(
        documents: [(inviteId: String, data: [String: Any])]
    ) -> [String: PendingIdentityStamp] {
        var stamps: [String: PendingIdentityStamp] = [:]
        for document in documents {
            stamps[document.inviteId] = PendingIdentityStamp(firestoreData: document.data)
        }
        return stamps
    }

    /// Hard sign-out: wipe all cached invites and clear published state.
    func deleteAllLocal() throws {
        stopListening()
        listeningUserId = nil
        listeningFamilyId = nil
        invites = []
        familyInvites = []
        inviteIdentityStamps = [:]
        errorMessage = nil
        guard let modelContext else { return }
        try modelContext.delete(model: Invite.self)
        try modelContext.save()
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

    func getInvite(inviteId: String, userId: String) -> Invite? {
        getInvites(for: userId).first { $0.inviteId == inviteId }
    }

    /// Lookup by invite id only (SwiftData cache).
    func getInvite(inviteId: String) -> Invite? {
        guard let modelContext = modelContext else { return nil }
        let searchInviteId = inviteId
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { $0.inviteId == searchInviteId }
        )
        return try? modelContext.fetch(descriptor).first
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

    /// Pending family invites for a family (any sender), from local cache.
    func getPendingFamilyInvites(familyId: String) -> [Invite] {
        FamilyOutgoingInviteFilter.pendingOutgoing(
            from: cachedFamilyInvites(familyId: familyId),
            familyId: familyId
        )
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
                existing.familyName = invite.familyName
                try? modelContext.save()
            } else {
                // Insert new if not found
                modelContext.insert(invite)
                try? modelContext.save()
            }
            
            // Refresh published array from cache
            refreshInvitesFromCache(userId: userId)
            if let listeningFamilyId {
                refreshFamilyInvitesFromCache(familyId: listeningFamilyId)
            }
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

    private func refreshFamilyInvitesFromCache(familyId: String) {
        familyInvites = cachedFamilyInvites(familyId: familyId)
    }

    private func cachedFamilyInvites(familyId: String) -> [Invite] {
        guard let modelContext = modelContext else { return [] }
        let searchFamilyId = familyId
        let familyType = Invite.InviteType.family.rawValue
        let descriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.familyId == searchFamilyId && invite.type == familyType
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    deinit {
        stopListening()
    }
}
