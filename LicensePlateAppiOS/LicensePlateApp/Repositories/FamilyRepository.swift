//
//  FamilyRepository.swift
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
class FamilyRepository: ObservableObject {
    static let shared = FamilyRepository()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    
    @Published var families: [Family] = []
    @Published var familyMembers: [String: [FamilyMember]] = [:] // familyId -> members
    @Published var pendingRequests: [String: [PendingJoinRequest]] = [:] // familyId -> requests
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        // Private initializer prevents external instantiation
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
        let searchFamilyId = family.familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { f in
                f.familyId == searchFamilyId
            }
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
                let searchMemberId = member.id
                let descriptor = FetchDescriptor<FamilyMember>(
                    predicate: #Predicate<FamilyMember> { m in
                        m.id == searchMemberId
                    }
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
            let searchRequestId = request.requestId
            let descriptor = FetchDescriptor<PendingJoinRequest>(
                predicate: #Predicate<PendingJoinRequest> { r in
                    r.requestId == searchRequestId
                }
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
                let searchUserId = userId
                let userDescriptor = FetchDescriptor<AppUser>(
                    predicate: #Predicate<AppUser> { user in
                        user.id == searchUserId
                    }
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
        let searchFamilyId = familyId
        let searchUserId = userId
        let memberDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { member in
                member.familyId == searchFamilyId && member.userId == searchUserId
            }
        )
        
        if let member = try? modelContext.fetch(memberDescriptor).first {
            member.user = user
        }
        
        // Link to PendingJoinRequest
        let requestDescriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { request in
                request.familyId == searchFamilyId && request.userId == searchUserId
            }
        )
        
        if let request = try? modelContext.fetch(requestDescriptor).first {
            request.user = user
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
    
    /// Get family by ID (from SwiftData)
    func getFamily(familyId: String) -> Family? {
        guard let modelContext = modelContext else { return nil }
        
        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { family in
                family.familyId == searchFamilyId
            }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Get members for a family (from SwiftData)
    func getMembers(familyId: String) -> [FamilyMember] {
        guard let modelContext = modelContext else { return [] }
        
        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { member in
                member.familyId == searchFamilyId
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get pending requests for a family (from SwiftData)
    func getPendingRequests(familyId: String) -> [PendingJoinRequest] {
        guard let modelContext = modelContext else { return [] }
        
        let searchFamilyId = familyId
        let pendingStatus = "pending"
        let descriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { request in
                request.familyId == searchFamilyId && request.status == pendingStatus
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Firestore Fetch (Online Priority)
    
    /// Fetch family directly from Firestore (prioritizes online data)
    func fetchFamily(familyId: String) async throws -> Family? {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let doc = try await db.collection("families").document(familyId).getDocument()
        
        guard doc.exists else {
            return nil
        }
        
        guard let family = Family(from: doc) else {
            return nil
        }
        
        // Sync to SwiftData
        let searchFamilyId = family.familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { f in
                f.familyId == searchFamilyId
            }
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
        
        try? modelContext.save()
        
        // Update published array
        let allDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allDescriptor) {
            families = allFamilies
        }
        
        return family
    }
    
    /// Fetch members directly from Firestore (prioritizes online data)
    func fetchMembers(familyId: String) async throws -> [FamilyMember] {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let snapshot = try await db.collection("families").document(familyId)
            .collection("members")
            .getDocuments()
        
        var members: [FamilyMember] = []
        var userIdsToFetch: [String] = []
        
        for document in snapshot.documents {
            if let member = FamilyMember(from: document, familyId: familyId) {
                members.append(member)
                userIdsToFetch.append(member.userId)
            }
        }
        
        // Cache complete AppUser data for all family members
        fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
        
        // Sync members to SwiftData
        for member in members {
            let searchMemberId = member.id
            let descriptor = FetchDescriptor<FamilyMember>(
                predicate: #Predicate<FamilyMember> { m in
                    m.id == searchMemberId
                }
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
        
        try? modelContext.save()
        
        // Update published dictionary
        familyMembers[familyId] = members
        
        return members
    }
    
    /// Fetch pending requests directly from Firestore (prioritizes online data)
    func fetchPendingRequests(familyId: String) async throws -> [PendingJoinRequest] {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let snapshot = try await db.collection("families").document(familyId)
            .collection("pending")
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        
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
            let searchRequestId = request.requestId
            let descriptor = FetchDescriptor<PendingJoinRequest>(
                predicate: #Predicate<PendingJoinRequest> { r in
                    r.requestId == searchRequestId
                }
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
        
        try? modelContext.save()
        
        // Update published dictionary
        pendingRequests[familyId] = requests
        
        return requests
    }
    
    // MARK: - Cloud Functions
    
    /// Create a new family
    func createFamily(name: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let createFamilyFunction = functions.httpsCallable("createFamily")
        
        let result = try await createFamilyFunction.call([
            "name": name
        ])
        
        guard let data = result.data as? [String: Any],
              let familyId = data["familyId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from createFamily"])
        }
        
        return familyId
    }
    
    /// Redeem a share code to join a family
    func redeemShareCode(code: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let redeemCodeFunction = functions.httpsCallable("redeemShareCode")
        
        let result = try await redeemCodeFunction.call([
            "code": code
        ])
        
        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from redeemShareCode"])
        }
        
        return inviteId
    }
    
    /// Send a family invite to a user
    func sendFamilyInvite(toUserId: String, familyId: String, method: String = "search") async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let sendInviteFunction = functions.httpsCallable("sendFamilyInvite")
        
        let result = try await sendInviteFunction.call([
            "toUserId": toUserId,
            "familyId": familyId,
            "method": method
        ])
        
        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from sendFamilyInvite"])
        }
        
        return inviteId
    }
    
    /// Respond to a family invite (user step)
    func respondToFamilyInvite(inviteId: String, accept: Bool) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let respondFunction = functions.httpsCallable("respondToFamilyInvite_UserStep")
        
        _ = try await respondFunction.call([
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline"
        ])
    }
    
    /// Get familyId from an invite
    func getFamilyIdFromInvite(inviteId: String) async throws -> String? {
        let inviteDoc = try await db.collection("invites").document(inviteId).getDocument()
        guard let data = inviteDoc.data() else { return nil }
        return data["familyId"] as? String
    }
    
    /// Create a share code (friend or family type)
    func createShareCode(type: String, familyId: String? = nil) async throws -> (codeId: String, code: String, expiresAt: Date) {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let createCodeFunction = functions.httpsCallable("createShareCode")
        
        var data: [String: Any] = ["type": type]
        if let familyId = familyId {
            data["familyId"] = familyId
        }
        
        let result = try await createCodeFunction.call(data)
        
        guard let resultData = result.data as? [String: Any],
              let codeId = resultData["codeId"] as? String,
              let code = resultData["code"] as? String,
              let expiresAtString = resultData["expiresAt"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from createShareCode"])
        }
        
        let formatter = ISO8601DateFormatter()
        let expiresAt = formatter.date(from: expiresAtString) ?? Date().addingTimeInterval(15 * 60)
        
        return (codeId: codeId, code: code, expiresAt: expiresAt)
    }
    
    deinit {
        stopListening()
    }
}

