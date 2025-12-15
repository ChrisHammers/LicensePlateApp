//
//  FirebaseFamilySyncService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import SwiftData
import Network
import Combine

@MainActor
class FirebaseFamilySyncService: ObservableObject {
    static let shared = FirebaseFamilySyncService()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "FamilySyncNetworkMonitor")
    @Published private(set) var isOnline = true
    
    // Real-time listeners for family members
    private var familyListeners: [UUID: ListenerRegistration] = [:]
    
    private init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    // Network came back online, cleanup orphaned families and sync pending changes
                    await self?.cleanupOrphanedFamilies()
                    await self?.syncPendingChanges()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    /// Initialize the service with model context
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Family Sync
    
    /// Save Family to Firestore
    func saveFamilyToFirestore(_ family: Family) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        // DEBUG: Check auth state
        let authUser = FirebaseAuth.Auth.auth().currentUser
        if let authUser = authUser {
            print("🔍 DEBUG - Saving family:")
            print("   Firebase Auth UID: \(authUser.uid)")
            print("   Family Firebase ID: \(family.firebaseFamilyID ?? "nil")")
            print("   Family local ID: \(family.id)")
            
            // Check if family exists in Firestore
            if let firebaseID = family.firebaseFamilyID {
                let docRef = db.collection("families").document(firebaseID)
                let doc = try? await docRef.getDocument()
                print("   Family exists in Firestore: \(doc?.exists ?? false)")
                
                // Check if user is a member
                let memberRef = docRef.collection("members").document(authUser.uid)
                let memberDoc = try? await memberRef.getDocument()
                if let memberDoc = memberDoc, memberDoc.exists, let memberData = memberDoc.data() {
                    let role = memberData["role"] as? String ?? "unknown"
                    print("   User is member with role: \(role)")
                } else {
                    print("   User is NOT a member in Firestore")
                    print("   This is OK if creating a new family")
                }
            }
        } else {
            print("❌ ERROR - No authenticated user when saving family!")
            throw SyncError.offline
        }
        
        // Check if online
        guard isOnline else {
            family.needsSync = true
            try? modelContext.save()
            return
        }
        
        // Generate Firebase ID if needed
        if family.firebaseFamilyID == nil {
            family.firebaseFamilyID = UUID().uuidString
        }
        
        guard let firebaseID = family.firebaseFamilyID else {
            family.needsSync = true
            return
        }
        
        let docRef = db.collection("families").document(firebaseID)
        let data = firestoreDataFromFamily(family)
        
        // Check if document exists to determine operation type
        let existingDoc = try? await docRef.getDocument()
        let documentExists = existingDoc?.exists ?? false
        
        print("🔍 DEBUG - Attempting to write family document:")
        print("   Path: families/\(firebaseID)")
        print("   Document exists: \(documentExists)")
        
        if documentExists {
            // Document exists - use merge for update
            print("   Operation: setData with merge: true (UPDATE)")
            try await docRef.setData(data, merge: true)
        } else {
            // Document doesn't exist - use setData without merge for create
            print("   Operation: setData without merge (CREATE)")
            try await docRef.setData(data)
        }
        
        family.needsSync = false
        try? modelContext.save()
    }
    
    /// Load Family from Firestore
    func loadFamilyFromFirestore(familyID: String) async throws -> Family? {
        let docRef = db.collection("families").document(familyID)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return try await familyFromFirestoreData(data, firebaseID: familyID)
    }
    
    /// Load only the user's family from Firestore (if they have a familyID)
    func loadUserFamilyFromFirestore(userID: String, familyID: UUID) async throws -> Family? {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        // First, try to find the family locally
        let descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.id == familyID
        })
        if let localFamily = try? modelContext.fetch(descriptor).first {
            // If family has a firebaseFamilyID and doesn't need sync, load from Firestore
            if let firebaseID = localFamily.firebaseFamilyID, !localFamily.needsSync {
                return try? await loadFamilyFromFirestore(familyID: firebaseID)
            }
            return localFamily
        }
        
        // If not found locally, search Firestore by local ID
        let query = db.collection("families").whereField("localID", isEqualTo: familyID.uuidString).limit(to: 1)
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        let firebaseID = document.documentID
        return try? await loadFamilyFromFirestore(familyID: firebaseID)
    }
    
    /// Clean up families that don't exist in Firestore
    func cleanupOrphanedFamilies() async {
        guard let modelContext = modelContext else { return }
        guard isOnline else { return }
        
        // Get current user's familyID to preserve it
        let currentUserID = FirebaseAuth.Auth.auth().currentUser?.uid
        let currentUserDescriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == currentUserID ?? ""
        })
        let currentUser = try? modelContext.fetch(currentUserDescriptor).first
        let userFamilyID = currentUser?.familyID
        
        // Get all families that are synced (don't need sync)
        let descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.needsSync == false
        })
        
        guard let families = try? modelContext.fetch(descriptor) else { return }
        
        var deletedCount = 0
        for family in families {
            // Only check families that have a firebaseFamilyID
            guard let firebaseID = family.firebaseFamilyID else { continue }
            
            // Skip if this is the user's current family
            if family.id == userFamilyID {
                continue
            }
            
            // Check if family exists in Firestore
            let docRef = db.collection("families").document(firebaseID)
            if let doc = try? await docRef.getDocument(), !doc.exists {
                // Family doesn't exist in Firestore, remove it locally
                print("🗑️ Removing orphaned family: \(family.id) (firebaseID: \(firebaseID))")
                
                // Stop listener for this family first
                stopListeningToFamily(familyID: family.id)
                
                // Clear familyID from all users who had this family
                let familyIDValue = family.id
                let membersDescriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                    $0.familyID == familyIDValue
                })
                if let members = try? modelContext.fetch(membersDescriptor) {
                    for member in members {
                        let memberIDValue = member.userID
                        let userDescriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
                            $0.id == memberIDValue
                        })
                        if let user = try? modelContext.fetch(userDescriptor).first {
                            user.familyID = nil
                            user.needsSync = true
                        }
                    }
                }
                
                // Delete all members
                if let members = try? modelContext.fetch(membersDescriptor) {
                    for member in members {
                        modelContext.delete(member)
                    }
                }
                
                // Delete the family
                modelContext.delete(family)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            do {
                try modelContext.save()
                print("✅ Cleaned up \(deletedCount) orphaned families")
            } catch {
                print("❌ Error saving after cleanup: \(error)")
            }
        }
    }
    
    /// Stop all family listeners except for the user's current family
    func stopAllFamilyListenersExcept(userFamilyID: UUID?) {
        let listenersToStop = familyListeners.keys.filter { $0 != userFamilyID }
        for familyID in listenersToStop {
            stopListeningToFamily(familyID: familyID)
            print("🛑 Stopped listener for family: \(familyID)")
        }
    }
    
    /// Load Family by local UUID
    func loadFamilyByLocalID(_ localID: UUID) async throws -> Family? {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        // First try to find locally
        let descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.id == localID
        })
        if let localFamily = try? modelContext.fetch(descriptor).first {
            return localFamily
        }
        
        // If not found locally, search Firestore by local ID
        let query = db.collection("families").whereField("localID", isEqualTo: localID.uuidString).limit(to: 1)
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first,
              let data = document.data() as? [String: Any] else {
            return nil
        }
        
        return try await familyFromFirestoreData(data, firebaseID: document.documentID)
    }
    
    /// Load Family by share code
    func loadFamilyByShareCode(_ code: String) async throws -> Family? {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        // First try to find locally
        let descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.shareCode == code
        })
        if let localFamily = try? modelContext.fetch(descriptor).first {
            return localFamily
        }
        
        // If not found locally, search Firestore by share code
        let query = db.collection("families").whereField("shareCode", isEqualTo: code).limit(to: 1)
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first,
              let data = document.data() as? [String: Any] else {
            return nil
        }
        
        return try await familyFromFirestoreData(data, firebaseID: document.documentID)
    }
    
    // MARK: - FamilyMember Sync
    
    /// Save FamilyMember to Firestore
    func saveFamilyMemberToFirestore(_ member: FamilyMember, familyFirebaseID: String) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        // DEBUG: Check auth state and userID match
        let authUser = FirebaseAuth.Auth.auth().currentUser
        if let authUser = authUser {
            print("🔍 DEBUG - Saving member:")
            print("   Firebase Auth UID: \(authUser.uid)")
            print("   Member userID: \(member.userID)")
            print("   Match: \(member.userID == authUser.uid)")
            print("   Path: families/\(familyFirebaseID)/members/\(member.userID)")
            print("   Role: \(member.role.rawValue)")
            print("   Invitation Status: \(member.invitationStatus.rawValue)")
            
            if member.userID != authUser.uid {
                print("⚠️ WARNING - Member userID doesn't match Firebase Auth UID!")
                print("   This will cause permission errors in Firestore rules!")
            }
        } else {
            print("❌ ERROR - No authenticated user when saving member!")
        }
        
        guard isOnline else {
            // Mark family for sync instead
            if let family = member.family {
                family.needsSync = true
                try? modelContext.save()
            }
            return
        }
        
        // Use userID as document ID for easier querying and security rules
        let docRef = db.collection("families").document(familyFirebaseID)
            .collection("members").document(member.userID)
        
        // Check if member document already exists
        let existingDoc = try? await docRef.getDocument()
        let documentExists = existingDoc?.exists ?? false
        print("🔍 DEBUG - Member document exists: \(documentExists)")
        
      var data: [String: Any] = [
            "id": member.id.uuidString,
            "userID": member.userID,
            "familyID": member.familyID.uuidString,
            "role": member.role.rawValue,
            "joinedAt": Timestamp(date: member.joinedAt),
            "isActive": member.isActive,
            "invitationStatus": member.invitationStatus.rawValue
        ]
        
        print("🔍 DEBUG - Saving member with status: \(member.invitationStatus.rawValue), isActive: \(member.isActive)")
        print("🔍 DEBUG - Member data being saved: invitationStatus=\(data["invitationStatus"] as? String ?? "nil"), isActive=\(data["isActive"] as? Bool ?? false)")
        
        if let invitedBy = member.invitedBy {
            data["invitedBy"] = invitedBy
        }
        
        if let invitedAt = member.invitedAt {
            data["invitedAt"] = Timestamp(date: invitedAt)
        }
        
        print("🔍 DEBUG - Attempting to write member document:")
        print("   Path: families/\(familyFirebaseID)/members/\(member.userID)")
        print("   Document exists: \(documentExists)")
        print("   Final data: invitationStatus=\(data["invitationStatus"] as? String ?? "nil"), isActive=\(data["isActive"] as? Bool ?? false)")
        
        if documentExists {
            // Document exists - use merge for update
            print("   Operation: setData with merge: true (UPDATE)")
            try await docRef.setData(data, merge: true)
        } else {
            // Document doesn't exist - use setData without merge for create
            print("   Operation: setData without merge (CREATE)")
            try await docRef.setData(data)
        }
        
        // Verify what was actually saved
        if let savedDoc = try? await docRef.getDocument(), let savedData = savedDoc.data() {
            print("🔍 DEBUG - Verification after save: invitationStatus=\(savedData["invitationStatus"] as? String ?? "nil"), isActive=\(savedData["isActive"] as? Bool ?? false)")
        }
        
        // If this is a pending invitation, add it to the user's document
        if member.invitationStatus == .pending {
            await addPendingInvitationToUserDocument(
                userID: member.userID,
                familyFirebaseID: familyFirebaseID,
                role: member.role.rawValue,
                invitedBy: member.invitedBy,
                invitedAt: member.invitedAt ?? member.joinedAt
            )
        } else if member.invitationStatus == .accepted || member.invitationStatus == .declined {
            // Remove from user's pending invitations if accepted or declined
            await removePendingInvitationFromUserDocument(
                userID: member.userID,
                familyFirebaseID: familyFirebaseID
            )
        }
    }
    
    /// Add a pending invitation to the user's document via Cloud Function
    private func addPendingInvitationToUserDocument(
        userID: String,
        familyFirebaseID: String,
        role: String,
        invitedBy: String?,
        invitedAt: Date
    ) async {
        guard isOnline else { return }
        
        let functions = Functions.functions()
        let addInvitation = functions.httpsCallable("addPendingInvitation")
        
        // Get current user ID for invitedBy if not provided
        let invitedByUID = invitedBy ?? FirebaseAuth.Auth.auth().currentUser?.uid ?? ""
        
        do {
            // Convert Date to ISO 8601 string for Cloud Function
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let invitedAtString = dateFormatter.string(from: invitedAt)
            
            let data: [String: Any] = [
                "invitedUserID": userID,
                "familyFirebaseID": familyFirebaseID,
                "role": role,
                "invitedBy": invitedByUID,
                "invitedAt": invitedAtString
            ]
            
            let result = try await addInvitation.call(data)
            print("✅ Added pending invitation via Cloud Function: \(userID)")
            
            if let resultData = result.data as? [String: Any],
               let message = resultData["message"] as? String {
                print("   Cloud Function response: \(message)")
            }
        } catch {
            print("⚠️ Error adding pending invitation via Cloud Function: \(error)")
            // Note: The member document is still created, but the user's pendingFamilyInvitations
            // won't be updated. This is acceptable - the invitation will still work via the
            // member document, and can be synced later.
        }
    }
    
    /// Remove a pending invitation from the user's document via Cloud Function
    func removePendingInvitationFromUserDocument(
        userID: String,
        familyFirebaseID: String
    ) async {
        guard isOnline else { return }
        
        let functions = Functions.functions()
        let removeInvitation = functions.httpsCallable("removePendingInvitation")
        
        do {
            let data: [String: Any] = [
                "userID": userID,
                "familyFirebaseID": familyFirebaseID
            ]
            
            let result = try await removeInvitation.call(data)
            print("✅ Removed pending invitation via Cloud Function: \(userID)")
            
            if let resultData = result.data as? [String: Any],
               let message = resultData["message"] as? String {
                print("   Cloud Function response: \(message)")
            }
        } catch {
            print("⚠️ Error removing pending invitation via Cloud Function: \(error)")
            // Note: The member document is still updated/deleted, but the user's
            // pendingFamilyInvitations won't be updated. This can be synced later.
        }
    }
    
    // MARK: - Game Sync
    
    /// Save Game to Firestore
    func saveGameToFirestore(_ game: Game) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        guard isOnline else {
            game.needsSync = true
            try? modelContext.save()
            return
        }
        
        if game.firebaseGameID == nil {
            game.firebaseGameID = UUID().uuidString
        }
        
        guard let firebaseID = game.firebaseGameID else {
            game.needsSync = true
            return
        }
        
        let docRef = db.collection("games").document(firebaseID)
        let data = firestoreDataFromGame(game)
        try await docRef.setData(data, merge: true)
        
        game.needsSync = false
        try? modelContext.save()
    }
    
    /// Load Game from Firestore
    func loadGameFromFirestore(gameID: String) async throws -> Game? {
        let docRef = db.collection("games").document(gameID)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return gameFromFirestoreData(data, firebaseID: gameID)
    }
    
    // MARK: - FriendRequest Sync
    
    /// Save FriendRequest to Firestore
    func saveFriendRequestToFirestore(_ request: FriendRequest) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        guard isOnline else {
            return // FriendRequests don't have needsSync, they're ephemeral
        }
        
        let docRef = db.collection("friendRequests").document(request.id.uuidString)
        var data: [String: Any] = [
            "id": request.id.uuidString,
            "fromUserID": request.fromUserID,
            "toUserID": request.toUserID,
            "status": request.status.rawValue,
            "createdAt": Timestamp(date: request.createdAt)
        ]
        
        if let respondedAt = request.respondedAt {
            data["respondedAt"] = Timestamp(date: respondedAt)
        }
        if let approvedBy = request.approvedBy {
            data["approvedBy"] = approvedBy
        }
        
        try await docRef.setData(data, merge: true)
    }
    
    // MARK: - Helper Methods
    
    private func firestoreDataFromFamily(_ family: Family) -> [String: Any] {
        var data: [String: Any] = [
            "localID": family.id.uuidString,
            "createdAt": Timestamp(date: family.createdAt),
            "lastUpdated": Timestamp(date: family.lastUpdated),
            "maxCaptains": family.maxCaptains,
            "maxScouts": family.maxScouts
        ]
        
        if let name = family.name {
            data["name"] = name
        }
        if !family.linkedFamilyIDs.isEmpty {
            data["linkedFamilyIDs"] = family.linkedFamilyIDs.map { $0.uuidString }
        }
        if let shareCode = family.shareCode {
            data["shareCode"] = shareCode
        }
        
        return data
    }
    
    private func familyFromFirestoreData(_ data: [String: Any], firebaseID: String) async throws -> Family? {
        guard let modelContext = modelContext else { return nil }
        
        let localID: UUID
        if let localIDString = data["localID"] as? String, let uuid = UUID(uuidString: localIDString) {
            localID = uuid
        } else {
            localID = UUID()
        }
        
        let name = data["name"] as? String
        let maxCaptains = data["maxCaptains"] as? Int ?? 2
        let maxScouts = data["maxScouts"] as? Int ?? 3
        let shareCode = data["shareCode"] as? String
        let showShareCode = data["showShareCode"] as? Bool ?? false
        
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = .now
        }
        
        let lastUpdated: Date
        if let timestamp = data["lastUpdated"] as? Timestamp {
            lastUpdated = timestamp.dateValue()
        } else {
            lastUpdated = .now
        }
        
        let linkedFamilyIDs: [UUID] = {
            if let idsArray = data["linkedFamilyIDs"] as? [String] {
                return idsArray.compactMap { UUID(uuidString: $0) }
            }
            return []
        }()
        
        // Check if family already exists locally
        let descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.id == localID
        })
        let existingFamily = try? modelContext.fetch(descriptor).first
        let family: Family
        
        if let existing = existingFamily {
            // Update existing family properties
            existing.firebaseFamilyID = firebaseID
            existing.name = name
            existing.maxCaptains = maxCaptains
            existing.maxScouts = maxScouts
            existing.linkedFamilyIDs = linkedFamilyIDs
            existing.lastUpdated = lastUpdated
            existing.shareCode = shareCode
            existing.showShareCode = showShareCode
            existing.needsSync = false
            family = existing
        } else {
            // Create new family
            family = Family(
                id: localID,
                name: name,
                createdAt: createdAt,
                lastUpdated: lastUpdated,
                linkedFamilyIDs: linkedFamilyIDs,
                maxCaptains: maxCaptains,
                maxScouts: maxScouts,
                firebaseFamilyID: firebaseID,
                needsSync: false,
                shareCode: shareCode,
                showShareCode: showShareCode
            )
            modelContext.insert(family)
        }
        
        // Load members from Firestore subcollection
        let membersRef = db.collection("families").document(firebaseID).collection("members")
        let membersSnapshot = try? await membersRef.getDocuments()
        
        // Track all userIDs from Firestore
        var firestoreMemberUserIDs = Set<String>()
        
        if let membersSnapshot = membersSnapshot {
            for memberDoc in membersSnapshot.documents {
                let memberData = memberDoc.data()
                // Document ID is now the userID
                let userID = memberDoc.documentID
                firestoreMemberUserIDs.insert(userID)
                
                if let member = familyMemberFromFirestoreData(memberData, familyID: localID, userID: userID, modelContext: modelContext) {
                    // Check if member already exists by userID and familyID (not by id)
                    let userIDValue = userID
                    let familyIDValue = localID
                    let memberDescriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                        $0.userID == userIDValue && $0.familyID == familyIDValue
                    })
                    
                    if let existingMember = try? modelContext.fetch(memberDescriptor).first {
                        // Update existing member with Firestore data (only if needsSync is false)
                        if !family.needsSync {
                            existingMember.role = member.role
                            existingMember.joinedAt = member.joinedAt
                            existingMember.invitedBy = member.invitedBy
                            existingMember.isActive = member.isActive
                            existingMember.invitationStatus = member.invitationStatus
                            existingMember.invitedAt = member.invitedAt
                        }
                    } else {
                        // Create new member
                        family.members.append(member)
                        modelContext.insert(member)
                    }
                }
            }
        }
        
        // Remove members that no longer exist in Firestore (only when needsSync is false)
        if !family.needsSync {
            let familyIDValue = localID
            let allLocalMembersDescriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                $0.familyID == familyIDValue
            })
            if let allLocalMembers = try? modelContext.fetch(allLocalMembersDescriptor) {
                for localMember in allLocalMembers {
                    if !firestoreMemberUserIDs.contains(localMember.userID) {
                        // Member no longer exists in Firestore, remove it
                        let memberUserID = localMember.userID
                        family.members.removeAll { $0.id == localMember.id }
                        modelContext.delete(localMember)
                        
                        // Clear the user's familyID
                        let userDescriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
                            $0.id == memberUserID
                        })
                        if let user = try? modelContext.fetch(userDescriptor).first {
                            user.familyID = nil
                            user.needsSync = true
                        }
                    }
                }
            }
        }
        
        try? modelContext.save()
        return family
    }
    
    /// Create FamilyMember from Firestore data
    /// - Parameters:
    ///   - data: Firestore document data
    ///   - familyID: The family's local UUID
    ///   - userID: The userID (now used as document ID, but also in data for backward compatibility)
    ///   - modelContext: SwiftData model context
    private func familyMemberFromFirestoreData(_ data: [String: Any], familyID: UUID, userID: String, modelContext: ModelContext) -> FamilyMember? {
        // userID is passed as parameter (from document ID) but also check data for backward compatibility
        let memberUserID = data["userID"] as? String ?? userID
        
        // Generate a UUID for the member.id (or use existing if present)
        let memberID: UUID
        if let idString = data["id"] as? String, let uuid = UUID(uuidString: idString) {
            memberID = uuid
        } else {
            memberID = UUID() // Generate new ID if not present
        }
        
        guard let roleString = data["role"] as? String,
              let role = FamilyMember.FamilyRole(rawValue: roleString) else {
            return nil
        }
        
        let joinedAt: Date
        if let timestamp = data["joinedAt"] as? Timestamp {
            joinedAt = timestamp.dateValue()
        } else {
            joinedAt = .now
        }
        
        let invitedBy = data["invitedBy"] as? String
        let isActive = data["isActive"] as? Bool ?? true
        
        // Handle invitation status (backward compatibility: if nil, treat as accepted)
        let invitationStatus: FamilyMember.InvitationStatus
        if let statusString = data["invitationStatus"] as? String,
           let status = FamilyMember.InvitationStatus(rawValue: statusString) {
            invitationStatus = status
        } else {
            // Backward compatibility: if isActive is true and no status, treat as accepted
            invitationStatus = isActive ? .accepted : .pending
        }
        
        let invitedAt: Date?
        if let timestamp = data["invitedAt"] as? Timestamp {
            invitedAt = timestamp.dateValue()
        } else {
            invitedAt = nil
        }
        
        // Check if member already exists by userID and familyID (not by member.id)
        let userIDValue = memberUserID
        let familyIDValue = familyID
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
            $0.userID == userIDValue && $0.familyID == familyIDValue
        })
        
        if let existingMember = try? modelContext.fetch(descriptor).first {
            // Update existing member
            existingMember.role = role
            existingMember.joinedAt = joinedAt
            existingMember.invitedBy = invitedBy
            existingMember.isActive = isActive
            existingMember.invitationStatus = invitationStatus
            existingMember.invitedAt = invitedAt
            return existingMember
        }
        
        // Create new member
        let member = FamilyMember(
            id: memberID,
            userID: memberUserID,
            familyID: familyID,
            role: role,
            joinedAt: joinedAt,
            invitedBy: invitedBy,
            isActive: isActive,
            invitationStatus: invitationStatus,
            invitedAt: invitedAt
        )
        
        return member
    }
    
    /// Query pending family invitations for a user from Firestore
    /// Load pending invitations from the user's document
    func loadPendingInvitationsForUser(userID: String) async throws -> [FamilyMember] {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        guard isOnline else {
            // Return local pending invitations if offline
            let userIDValue = userID
            let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                $0.userID == userIDValue
            })
            let allUserMembers = (try? modelContext.fetch(descriptor)) ?? [FamilyMember]()
            return allUserMembers.filter { $0.invitationStatus == .pending }
        }
        
        // Read pending invitations from user document
        let userRef = db.collection("users").document(userID)
        let userDoc = try await userRef.getDocument()
        
        guard let data = userDoc.data(),
              let pendingInvitationsData = data["pendingFamilyInvitations"] as? [[String: Any]] else {
            // No pending invitations
            return []
        }
        
        var pendingMembers: [FamilyMember] = []
        
        // Process each pending invitation
        for invitationData in pendingInvitationsData {
            guard let familyFirebaseID = invitationData["familyFirebaseID"] as? String,
                  let roleString = invitationData["role"] as? String,
                  let role = FamilyMember.FamilyRole(rawValue: roleString) else {
                continue
            }
            
            // Get family localID from Firestore
            let familyDoc = try? await db.collection("families").document(familyFirebaseID).getDocument()
            guard let familyData = familyDoc?.data(),
                  let localIDString = familyData["localID"] as? String,
                  let familyLocalID = UUID(uuidString: localIDString) else {
                continue
            }
            
            // Get invitedAt date
            let invitedAt: Date
            if let timestamp = invitationData["invitedAt"] as? Timestamp {
                invitedAt = timestamp.dateValue()
            } else {
                invitedAt = .now
            }
            
            let invitedBy = invitationData["invitedBy"] as? String
            
            // Check if member already exists locally
            let userIDValue = userID
            let familyIDValue = familyLocalID
            let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                $0.userID == userIDValue && $0.familyID == familyIDValue
            })
            
            if let existingMember = try? modelContext.fetch(descriptor).first {
                // Update existing member if needed
                if existingMember.invitationStatus != .pending {
                    existingMember.invitationStatus = .pending
                    existingMember.invitedAt = invitedAt
                    existingMember.invitedBy = invitedBy
                    existingMember.isActive = false
                }
                pendingMembers.append(existingMember)
            } else {
                // Create new member
                let member = FamilyMember(
                    userID: userID,
                    familyID: familyLocalID,
                    role: role,
                    joinedAt: invitedAt,
                    invitedBy: invitedBy,
                    isActive: false,
                    invitationStatus: .pending,
                    invitedAt: invitedAt
                )
                
                modelContext.insert(member)
                
                // Associate with family
                if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                    $0.id == familyLocalID
                })).first {
                    family.members.append(member)
                }
                
                pendingMembers.append(member)
            }
        }
        
        try? modelContext.save()
        return pendingMembers
    }
    
    private func firestoreDataFromGame(_ game: Game) -> [String: Any] {
        var data: [String: Any] = [
            "localID": game.id.uuidString,
            "name": game.name,
            "createdAt": Timestamp(date: game.createdAt),
            "gameMode": game.gameMode.rawValue,
            "scoringType": game.scoringType.rawValue,
            "createdBy": game.createdBy,
            "isPublic": game.isPublic,
            "minTeamSize": game.minTeamSize,
            "enabledCountryStrings": game.enabledCountryStrings
        ]
        
        if let startedAt = game.startedAt {
            data["startedAt"] = Timestamp(date: startedAt)
        }
        if let endedAt = game.endedAt {
            data["endedAt"] = Timestamp(date: endedAt)
        }
        if let shareCode = game.shareCode {
            data["shareCode"] = shareCode
        }
        if let maxTeamSize = game.maxTeamSize {
            data["maxTeamSize"] = maxTeamSize
        }
        
        return data
    }
    
    private func gameFromFirestoreData(_ data: [String: Any], firebaseID: String) -> Game? {
        guard let modelContext = modelContext else { return nil }
        
        guard let localIDString = data["localID"] as? String,
              let localID = UUID(uuidString: localIDString),
              let name = data["name"] as? String,
              let gameModeString = data["gameMode"] as? String,
              let gameMode = Game.GameMode(rawValue: gameModeString),
              let scoringTypeString = data["scoringType"] as? String,
              let scoringType = Game.ScoringType(rawValue: scoringTypeString),
              let createdBy = data["createdBy"] as? String,
              let enabledCountryStrings = data["enabledCountryStrings"] as? String else {
            return nil
        }
        
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = .now
        }
        
        let startedAt: Date?
        if let timestamp = data["startedAt"] as? Timestamp {
            startedAt = timestamp.dateValue()
        } else {
            startedAt = nil
        }
        
        let endedAt: Date?
        if let timestamp = data["endedAt"] as? Timestamp {
            endedAt = timestamp.dateValue()
        } else {
            endedAt = nil
        }
        
        let isPublic = data["isPublic"] as? Bool ?? false
        let minTeamSize = data["minTeamSize"] as? Int ?? 2
        let maxTeamSize = data["maxTeamSize"] as? Int
        let shareCode = data["shareCode"] as? String
        
        // Convert enabledCountryStrings to [PlateRegion.Country]
        let enabledCountries: [PlateRegion.Country] = enabledCountryStrings
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { PlateRegion.Country(rawValue: String($0)) }
        
        // Check if game already exists locally
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate<Game> {
            $0.id == localID
        })
        if let existingGame = try? modelContext.fetch(descriptor).first {
            existingGame.firebaseGameID = firebaseID
            existingGame.name = name
            existingGame.gameMode = gameMode
            existingGame.scoringType = scoringType
            existingGame.startedAt = startedAt
            existingGame.endedAt = endedAt
            existingGame.isPublic = isPublic
            existingGame.shareCode = shareCode
            existingGame.minTeamSize = minTeamSize
            existingGame.maxTeamSize = maxTeamSize
            existingGame.enabledCountryStrings = enabledCountryStrings
            existingGame.needsSync = false
            return existingGame
        }
        
        // Create new game
        let game = Game(
            id: localID,
            name: name,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            gameMode: gameMode,
            scoringType: scoringType,
            createdBy: createdBy,
            isPublic: isPublic,
            shareCode: shareCode,
            maxTeamSize: maxTeamSize,
            minTeamSize: minTeamSize,
            enabledCountries: enabledCountries,
            firebaseGameID: firebaseID,
            needsSync: false
        )
        
        modelContext.insert(game)
        return game
    }
    
    /// Sync all pending family-related changes to Firebase
    func syncPendingChanges() async {
        guard let modelContext = modelContext else { return }
        guard isOnline else { return }
        
        // Clean up orphaned families first (families that don't exist in Firestore)
        await cleanupOrphanedFamilies()
        
        // Sync families that need sync
        let familyDescriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.needsSync == true
        })
        if let families = try? modelContext.fetch(familyDescriptor) {
            for family in families {
                do {
                    // If family already exists in Firestore, load it instead of writing
                    if let firebaseID = family.firebaseFamilyID {
                        let docRef = db.collection("families").document(firebaseID)
                        let doc = try? await docRef.getDocument()
                        
                        if doc?.exists == true {
                            // Family exists in Firestore - load it instead of writing
                            print("🔍 Family \(family.id) exists in Firestore, loading instead of writing")
                            _ = try? await loadFamilyFromFirestore(familyID: firebaseID)
                            // After loading, needsSync should be set to false by loadFamilyFromFirestore
                        } else {
                            // Family doesn't exist - write it (will create new)
                            print("🔍 Family \(family.id) doesn't exist in Firestore, creating it")
                            try await saveFamilyToFirestore(family)
                        }
                    } else {
                        // No Firebase ID yet - write it (will create new and assign Firebase ID)
                        print("🔍 Family \(family.id) has no Firebase ID, creating it")
                        try await saveFamilyToFirestore(family)
                    }
                } catch {
                    print("Error syncing pending family \(family.id): \(error)")
                }
            }
        }
        
        // Sync games that need sync
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate<Game> {
            $0.needsSync == true
        })
        if let games = try? modelContext.fetch(gameDescriptor) {
            for game in games {
                do {
                    try await saveGameToFirestore(game)
                } catch {
                    print("Error syncing pending game \(game.id): \(error)")
                }
            }
        }
        
        // Sync competitions that need sync
        let competitionDescriptor = FetchDescriptor<AppCompetition>(predicate: #Predicate<AppCompetition> {
            $0.needsSync == true
        })
        if let competitions = try? modelContext.fetch(competitionDescriptor) {
            for competition in competitions {
                do {
                    try await saveCompetitionToFirestore(competition)
                } catch {
                    print("Error syncing pending competition \(competition.id): \(error)")
                }
            }
        }
    }
    
    // MARK: - AppCompetition Sync
    
    /// Save AppCompetition to Firestore
    func saveCompetitionToFirestore(_ competition: AppCompetition) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        guard isOnline else {
            competition.needsSync = true
            try? modelContext.save()
            return
        }
        
        if competition.firebaseCompetitionID == nil {
            competition.firebaseCompetitionID = UUID().uuidString
        }
        
        guard let firebaseID = competition.firebaseCompetitionID else {
            competition.needsSync = true
            return
        }
        
        let docRef = db.collection("competitions").document(firebaseID)
        var data: [String: Any] = [
            "localID": competition.id.uuidString,
            "name": competition.name,
            "competitionDescription": competition.competitionDescription,
            "startDate": Timestamp(date: competition.startDate),
            "competitionType": competition.competitionType.rawValue,
            "isActive": competition.isActive,
            "leaderboardJSON": competition.leaderboardJSON
        ]
        
        if let endDate = competition.endDate {
            data["endDate"] = Timestamp(date: endDate)
        }
        
        try await docRef.setData(data, merge: true)
        
        competition.needsSync = false
        try? modelContext.save()
    }
    
    // MARK: - User Search
    
    /// Search for users by username or email prefix
    func searchUsers(query: String) async throws -> [UserSearchResult] {
        guard isOnline else {
            throw SyncError.offline
        }
        
        guard query.count >= 3 else {
            return []
        }
        
        var results: [UserSearchResult] = []
        let queryLower = query.lowercased()
        let firstCharLower = queryLower.prefix(1)
        let firstCharUpper = firstCharLower.uppercased()
        
        // Search by username - substring matching (not just prefix)
        // Firestore queries are case-sensitive and only support prefix matching.
        // To find usernames containing the query anywhere, we search from the first
        // character and filter client-side for substring matches.
        
        // Calculate the upper bound: lowercase first char + 1
        let upperBound: String
        if let firstCharLowerUnicode = firstCharLower.unicodeScalars.first,
           let nextUnicode = UnicodeScalar(firstCharLowerUnicode.value + 1) {
            upperBound = String(nextUnicode)
        } else {
            // Fallback
            upperBound = String(firstCharLower) + "\u{f8ff}"
        }
        
        // Search from uppercase first char to lowercase first char + 1
        // This catches all usernames starting with that letter in any case
        let usernameQuery = db.collection("users")
            .whereField("userName", isGreaterThanOrEqualTo: String(firstCharUpper))
            .whereField("userName", isLessThan: upperBound)
            .limit(to: 100) // Get more results to filter from
        
        var seenUserIDs = Set<String>()
        
        do {
            let usernameSnapshot = try await usernameQuery.getDocuments()
            for document in usernameSnapshot.documents {
                let data = document.data()
                let userID = document.documentID
                if seenUserIDs.contains(userID) { continue }
                
                let userName = data["userName"] as? String ?? ""
                let isEmailPublic = data["isEmailPublic"] as? Bool ?? false
                let isPhonePublic = data["isPhonePublic"] as? Bool ?? false
                let email = isEmailPublic ? (data["email"] as? String) : nil
                let phoneNumber = isPhonePublic ? (data["phoneNumber"] as? String) : nil
                
                // Case-insensitive substring filter: check if query appears anywhere in username
                if userName.lowercased().contains(queryLower) {
                    results.append(UserSearchResult(
                        id: userID,
                        userName: userName,
                        email: email,
                        phoneNumber: phoneNumber,
                        matchedField: "username"
                    ))
                    seenUserIDs.insert(userID)
                    if results.count >= 20 { break }
                }
            }
        } catch {
            print("Error searching users by username: \(error)")
        }
        
        // Search by email prefix
        let emailQuery = db.collection("users")
            .whereField("email", isGreaterThanOrEqualTo: queryLower)
            .whereField("email", isLessThan: queryLower + "\u{f8ff}")
            .limit(to: 20)
        
        do {
            let emailSnapshot = try await emailQuery.getDocuments()
            for document in emailSnapshot.documents {
                let data = document.data()
                let userID = document.documentID
                
                // Check if we already have this user from username search
                if seenUserIDs.contains(userID) {
                    continue
                }
                
                // Only match by email if email is public
                let isEmailPublic = data["isEmailPublic"] as? Bool ?? false
                if !isEmailPublic {
                    continue // Skip this user - email is private, don't match by email
                }
                
                let userName = data["userName"] as? String ?? ""
                let isPhonePublic = data["isPhonePublic"] as? Bool ?? false
                let email = data["email"] as? String
                let phoneNumber = isPhonePublic ? (data["phoneNumber"] as? String) : nil
                
                results.append(UserSearchResult(
                    id: userID,
                    userName: userName,
                    email: email,
                    phoneNumber: phoneNumber,
                    matchedField: "email"
                ))
                seenUserIDs.insert(userID)
                if results.count >= 20 { break }
            }
        } catch {
            print("Error searching users by email: \(error)")
        }
        
        // Search by phone number prefix
        let phoneQuery = db.collection("users")
            .whereField("phoneNumber", isGreaterThanOrEqualTo: queryLower)
            .whereField("phoneNumber", isLessThan: queryLower + "\u{f8ff}")
            .limit(to: 20)
        
        do {
            let phoneSnapshot = try await phoneQuery.getDocuments()
            for document in phoneSnapshot.documents {
                let data = document.data()
                let userID = document.documentID
                
                // Check if we already have this user from previous searches
                if seenUserIDs.contains(userID) {
                    continue
                }
                
                // Only match by phone if phone is public
                let isPhonePublic = data["isPhonePublic"] as? Bool ?? false
                if !isPhonePublic {
                    continue // Skip this user - phone is private, don't match by phone
                }
                
                let userName = data["userName"] as? String ?? ""
                let isEmailPublic = data["isEmailPublic"] as? Bool ?? false
                let email = isEmailPublic ? (data["email"] as? String) : nil
                let phoneNumber = data["phoneNumber"] as? String
                
                results.append(UserSearchResult(
                    id: userID,
                    userName: userName,
                    email: email,
                    phoneNumber: phoneNumber,
                    matchedField: "phone"
                ))
                seenUserIDs.insert(userID)
                if results.count >= 20 { break }
            }
        } catch {
            print("Error searching users by phone: \(error)")
        }
        
        // Remove duplicates and limit to 20 total
        var uniqueResults: [UserSearchResult] = []
        var seenIDs: Set<String> = []
        
        for result in results {
            if !seenIDs.contains(result.id) && seenIDs.count < 20 {
                uniqueResults.append(result)
                seenIDs.insert(result.id)
            }
        }
        
        return uniqueResults
    }
    
    // MARK: - Real-Time Listeners
    
    /// Start listening to family member changes in real-time
    /// - Parameters:
    ///   - familyID: The local UUID of the family
    ///   - firebaseFamilyID: The Firebase document ID of the family
    ///   - onUpdate: Callback called when members change
    func startListeningToFamily(familyID: UUID, firebaseFamilyID: String, onUpdate: @escaping () -> Void) {
        guard let modelContext = modelContext else {
            print("⚠️ Cannot start listener: no model context")
            return
        }
        
        // Stop existing listener if any
        stopListeningToFamily(familyID: familyID)
        
        guard isOnline else {
            print("⚠️ Cannot start listener: offline")
            return
        }
        
        let membersRef = db.collection("families").document(firebaseFamilyID).collection("members")
        
        let listener = membersRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Error listening to family members: \(error)")
                return
            }
            
            guard let snapshot = snapshot else { return }
            
            Task { @MainActor in
                // Process document changes
                for change in snapshot.documentChanges {
                    let memberData = change.document.data()
                    let userID = change.document.documentID
                    
                    switch change.type {
                    case .added, .modified:
                        // Create or update FamilyMember
                        if let member = try? await self.familyMemberFromFirestoreData(memberData, familyID: familyID, userID: userID, modelContext: modelContext) {
                            // Check if member already exists
                            let userIDValue = userID
                            let familyIDValue = familyID
                            let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                                $0.userID == userIDValue && $0.familyID == familyIDValue
                            })
                            
                            if let existingMember = try? modelContext.fetch(descriptor).first {
                                // Update existing member
                                existingMember.role = member.role
                                existingMember.joinedAt = member.joinedAt
                                existingMember.invitedBy = member.invitedBy
                                existingMember.isActive = member.isActive
                                existingMember.invitationStatus = member.invitationStatus
                                existingMember.invitedAt = member.invitedAt
                                print("🔄 Updated member \(userID) in family \(familyID) via real-time listener")
                            } else {
                                // Insert new member
                                modelContext.insert(member)
                                // Associate with family
                                if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                                    $0.id == familyID
                                })).first {
                                    family.members.append(member)
                                }
                                print("➕ Added member \(userID) to family \(familyID) via real-time listener")
                            }
                            
                            try? modelContext.save()
                        }
                        
                    case .removed:
                        // Remove member from local data
                        let userIDValue = userID
                        let familyIDValue = familyID
                        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                            $0.userID == userIDValue && $0.familyID == familyIDValue
                        })
                        
                        if let memberToRemove = try? modelContext.fetch(descriptor).first {
                            // Remove from family relationship
                            if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                                $0.id == familyID
                            })).first {
                                family.members.removeAll { $0.id == memberToRemove.id }
                            }
                            
                            // Delete the member from local data
                            modelContext.delete(memberToRemove)
                            
                            // Clear the user's familyID if this is the current user's member record
                            let userDescriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
                                $0.id == userIDValue
                            })
                            if let user = try? modelContext.fetch(userDescriptor).first {
                                user.familyID = nil
                                user.needsSync = true
                            }
                            
                            try? modelContext.save()
                            print("🗑️ Removed member \(userID) from family \(familyID) via real-time listener")
                        }
                    }
                }
                
                // Notify that updates are complete
                onUpdate()
            }
        }
        
        // Store listener reference
        familyListeners[familyID] = listener
    }
    
    /// Stop listening to family member changes
    /// - Parameter familyID: The local UUID of the family
    func stopListeningToFamily(familyID: UUID) {
        if let listener = familyListeners[familyID] {
            listener.remove()
            familyListeners.removeValue(forKey: familyID)
        }
    }
    
    /// Delete a family from Firestore
    func deleteFamilyFromFirestore(familyFirebaseID: String) async throws {
        guard isOnline else {
            throw SyncError.offline
        }
        
        let familyRef = db.collection("families").document(familyFirebaseID)
        
        // Delete all members first
        let membersRef = familyRef.collection("members")
        let membersSnapshot = try await membersRef.getDocuments()
        
        for document in membersSnapshot.documents {
            try await document.reference.delete()
        }
        
        // Delete the family document
        try await familyRef.delete()
        
        print("✅ Deleted family from Firestore: \(familyFirebaseID)")
    }
    
    /// Remove a pending invitation (cancel invitation)
    func removePendingInvitation(userID: String, familyFirebaseID: String) async throws {
        guard let modelContext = modelContext else {
            throw SyncError.noModelContext
        }
        
        guard isOnline else {
            throw SyncError.offline
        }
        
        // Remove from user's pendingFamilyInvitations
        await removePendingInvitationFromUserDocument(userID: userID, familyFirebaseID: familyFirebaseID)
        
        // Delete the member document from Firestore
        let memberRef = db.collection("families").document(familyFirebaseID)
            .collection("members").document(userID)
        try await memberRef.delete()
        
        // Remove from local data
        let userIDValue = userID
        let familyFirebaseIDValue = familyFirebaseID
        let familyDescriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.firebaseFamilyID == familyFirebaseIDValue
        })
        if let family = try? modelContext.fetch(familyDescriptor).first {
            // Capture family.id in a local constant for use in predicate
            let familyIDValue = family.id
            let memberDescriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                $0.userID == userIDValue && $0.familyID == familyIDValue
            })
            if let member = try? modelContext.fetch(memberDescriptor).first {
                family.members.removeAll { $0.id == member.id }
                modelContext.delete(member)
                try? modelContext.save()
            }
        }
        
        print("✅ Removed pending invitation for user: \(userID) from family: \(familyFirebaseID)")
    }
    
    /// Stop all family listeners
    func stopAllFamilyListeners() {
        for (_, listener) in familyListeners {
            listener.remove()
        }
        familyListeners.removeAll()
    }
    
    enum SyncError: Error {
        case noModelContext
        case offline
        case invalidData
    }
}

