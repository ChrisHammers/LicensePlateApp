//
//  FamilyRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import Combine

@MainActor
class FamilyRepository: ObservableObject {
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    private var listeners: [ListenerRegistration] = []
    
    @Published var families: [Family] = []
    @Published var familyMembers: [String: [FamilyMember]] = [:] // familyId -> members
    @Published var pendingRequests: [String: [PendingJoinRequest]] = [:] // familyId -> requests
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Sync from Firestore
    
    /// Start listening to a family and its members
    func startListening(familyId: String) {
        stopListening()
        
        // Listen to family document
        let familyListener = db.collection("families").document(familyId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleFamilySnapshot(snapshot: snapshot, error: error)
                }
            }
        
        listeners.append(familyListener)
        
        // Listen to members subcollection
        let membersListener = db.collection("families").document(familyId)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleMembersSnapshot(snapshot: snapshot, error: error, familyId: familyId)
                }
            }
        
        listeners.append(membersListener)
        
        // Listen to pending requests subcollection
        let pendingListener = db.collection("families").document(familyId)
            .collection("pending")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handlePendingSnapshot(snapshot: snapshot, error: error, familyId: familyId)
                }
            }
        
        listeners.append(pendingListener)
    }
    
    /// Start listening to all families for a user (via activeFamilyId)
    func startListeningForUser(userId: String) {
        // First get user's activeFamilyId
        let userDoc = db.collection("users").document(userId)
        userDoc.getDocument { [weak self] snapshot, error in
            Task { @MainActor in
                if let data = snapshot?.data(),
                   let activeFamilyId = data["activeFamilyId"] as? String {
                    self?.startListening(familyId: activeFamilyId)
                }
            }
        }
    }
    
    private func handleFamilySnapshot(snapshot: DocumentSnapshot?, error: Error?) {
        if let error = error {
            errorMessage = "Error fetching family: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, snapshot.exists,
              let modelContext = modelContext,
              let family = Family(from: snapshot) else { return }
        
        // Sync to SwiftData
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { $0.familyId == family.familyId }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = family.name
            existing.creatorId = family.creatorId
            existing.status = family.status
            existing.createdAt = family.createdAt
            existing.updatedAt = family.updatedAt
        } else {
            modelContext.insert(family)
        }
        
        // Update published array
        let allDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allDescriptor) {
            families = allFamilies
        }
        
        try? modelContext.save()
    }
    
    private func handleMembersSnapshot(snapshot: QuerySnapshot?, error: Error?, familyId: String) {
        if let error = error {
            errorMessage = "Error fetching members: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        var members: [FamilyMember] = []
        var userIdsToFetch: [String] = []
        
        for document in snapshot.documents {
            if let member = FamilyMember(from: document, familyId: familyId) {
                members.append(member)
                userIdsToFetch.append(member.userId)
            }
        }
        
        // Cache complete AppUser data for all family members
        // This is critical for offline access to full user profiles
        fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
        
        // Sync members to SwiftData
        for member in members {
            let descriptor = FetchDescriptor<FamilyMember>(
                predicate: #Predicate<FamilyMember> { $0.id == member.id }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = member.familyId
                existing.userId = member.userId
                existing.role = member.role
                existing.canInvite = member.canInvite
                existing.canEditSettings = member.canEditSettings
                existing.joinedAt = member.joinedAt
                existing.updatedAt = member.updatedAt
            } else {
                modelContext.insert(member)
            }
        }
        
        // Update published dictionary
        familyMembers[familyId] = members
        
        try? modelContext.save()
    }
    
    private func handlePendingSnapshot(snapshot: QuerySnapshot?, error: Error?, familyId: String) {
        if let error = error {
            errorMessage = "Error fetching pending requests: \(error.localizedDescription)"
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }
        
        var requests: [PendingJoinRequest] = []
        var userIdsToFetch: [String] = []
        
        for document in snapshot.documents {
            if let request = PendingJoinRequest(from: document, familyId: familyId) {
                requests.append(request)
                userIdsToFetch.append(request.userId)
            }
        }
        
        // Cache complete AppUser data for pending users
        fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
        
        // Sync requests to SwiftData
        for request in requests {
            let descriptor = FetchDescriptor<PendingJoinRequest>(
                predicate: #Predicate<PendingJoinRequest> { $0.requestId == request.requestId }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = request.familyId
                existing.userId = request.userId
                existing.requestedBy = request.requestedBy
                existing.method = request.method
                existing.status = request.status
                existing.createdAt = request.createdAt
                existing.resolvedAt = request.resolvedAt
            } else {
                modelContext.insert(request)
            }
        }
        
        // Update published dictionary
        pendingRequests[familyId] = requests
        
        try? modelContext.save()
    }
    
    /// Fetch and cache complete AppUser data for family members
    /// This ensures offline access to full user profiles
    private func fetchAndCacheUsers(userIds: [String], familyId: String) {
        guard let modelContext = modelContext else { return }
        
        Task {
            for userId in userIds {
                // Check if user already cached
                let userDescriptor = FetchDescriptor<AppUser>(
                    predicate: #Predicate<AppUser> { $0.id == userId }
                )
                
                if let existingUser = try? modelContext.fetch(userDescriptor).first {
                    // User already cached, link to members/requests
                    linkUserToMembers(userId: userId, familyId: familyId)
                    continue
                }
                
                // Fetch from Firestore
                let userDoc = try? await db.collection("users").document(userId).getDocument()
                
                if let userDoc = userDoc,
                   let data = userDoc.data(),
                   let userName = data["username"] as? String {
                    
                    // Create AppUser from Firestore data
                    let user = AppUser(
                        id: userId,
                        userName: userName,
                        firstName: data["firstName"] as? String,
                        lastName: data["lastName"] as? String,
                        email: data["email"] as? String,
                        phoneNumber: data["phone"] as? String,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                        lastUpdated: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                        isEmailPublic: (data["privacy"] as? [String: Any])?["emailSearchable"] as? Bool ?? false,
                        isPhonePublic: (data["privacy"] as? [String: Any])?["phoneSearchable"] as? Bool ?? false,
                        isRetiredGeneral: data["isRetiredGeneral"] as? Bool ?? false,
                        activeFamilyId: data["activeFamilyId"] as? String,
                        friendCount: data["friendCount"] as? Int ?? 0,
                        firebaseUID: userId
                    )
                    
                    // Set avatar if available
                    if let avatarColorString = data["avatarColor"] as? String,
                       let avatarColor = AvatarColor(rawValue: avatarColorString) {
                        user.avatarColor = avatarColor
                    }
                    if let avatarTypeString = data["avatarType"] as? String,
                       let avatarType = AvatarType(rawValue: avatarTypeString) {
                        user.avatarType = avatarType
                    }
                    
                    modelContext.insert(user)
                    try? modelContext.save()
                    
                    // Link user to members/requests
                    linkUserToMembers(userId: userId, familyId: familyId)
                }
            }
        }
    }
    
    /// Link cached AppUser to FamilyMember and PendingJoinRequest
    private func linkUserToMembers(userId: String, familyId: String) {
        guard let modelContext = modelContext else { return }
        
        let userDescriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.id == userId }
        )
        
        guard let user = try? modelContext.fetch(userDescriptor).first else { return }
        
        // Link to FamilyMember
        let memberDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == familyId && $0.userId == userId }
        )
        
        if let member = try? modelContext.fetch(memberDescriptor).first {
            member.user = user
        }
        
        // Link to PendingJoinRequest
        let requestDescriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { $0.familyId == familyId && $0.userId == userId }
        )
        
        if let request = try? modelContext.fetch(requestDescriptor).first {
            request.user = user
        }
        
        try? modelContext.save()
    }
    
    /// Stop listening to Firestore updates
    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Local Queries
    
    /// Get family by ID (from SwiftData)
    func getFamily(familyId: String) -> Family? {
        guard let modelContext = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { $0.familyId == familyId }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Get members for a family (from SwiftData)
    func getMembers(familyId: String) -> [FamilyMember] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == familyId }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get pending requests for a family (from SwiftData)
    func getPendingRequests(familyId: String) -> [PendingJoinRequest] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { $0.familyId == familyId && $0.status == "pending" }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    deinit {
        stopListening()
    }
}

