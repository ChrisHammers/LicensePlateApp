//
//  FirebaseFamilySyncService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import FirebaseFirestore
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
                    // Network came back online, sync pending changes
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
        try await docRef.setData(data, merge: true)
        
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
        
      var data: [String: Any] = [
            "id": member.id.uuidString,
            "userID": member.userID,
            "familyID": member.familyID.uuidString,
            "role": member.role.rawValue,
            "joinedAt": Timestamp(date: member.joinedAt),
            "isActive": member.isActive,
            "invitationStatus": member.invitationStatus.rawValue
        ]
        
        if let invitedBy = member.invitedBy {
            data["invitedBy"] = invitedBy
        }
        
        if let invitedAt = member.invitedAt {
            data["invitedAt"] = Timestamp(date: invitedAt)
        }
        
        try await docRef.setData(data, merge: true)
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
        if let existingFamily = try? modelContext.fetch(descriptor).first {
            existingFamily.firebaseFamilyID = firebaseID
            existingFamily.name = name
            existingFamily.maxCaptains = maxCaptains
            existingFamily.maxScouts = maxScouts
            existingFamily.linkedFamilyIDs = linkedFamilyIDs
            existingFamily.lastUpdated = lastUpdated
            existingFamily.shareCode = shareCode
            existingFamily.needsSync = false
            return existingFamily
        }
        
        // Create new family
        let family = Family(
            id: localID,
            name: name,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            linkedFamilyIDs: linkedFamilyIDs,
            maxCaptains: maxCaptains,
            maxScouts: maxScouts,
            firebaseFamilyID: firebaseID,
            needsSync: false,
            shareCode: shareCode
        )
        
        modelContext.insert(family)
        
        // Load members from Firestore subcollection
        let membersRef = db.collection("families").document(firebaseID).collection("members")
        let membersSnapshot = try? await membersRef.getDocuments()
        
        if let membersSnapshot = membersSnapshot {
            for memberDoc in membersSnapshot.documents {
                let memberData = memberDoc.data()
                // Document ID is now the userID
                let userID = memberDoc.documentID
                if let member = familyMemberFromFirestoreData(memberData, familyID: localID, userID: userID, modelContext: modelContext) {
                    // Check if member already exists
                    let memberID = member.id
                    let memberDescriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                        $0.id == memberID
                    })
                    let existingMember = try? modelContext.fetch(memberDescriptor).first
                    if existingMember == nil {
                        family.members.append(member)
                        modelContext.insert(member)
                    }
                }
            }
        }
        
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
    /// Uses collection group query to find all member documents where userID matches
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
        
        // Use collection group query to find all member documents for this user
        // This searches across all families/families/{familyId}/members/{userID}
        let membersQuery = db.collectionGroup("members")
            .whereField("userID", isEqualTo: userID)
            .whereField("invitationStatus", isEqualTo: "pending")
        
        let snapshot = try await membersQuery.getDocuments()
        var pendingMembers: [FamilyMember] = []
        
        for document in snapshot.documents {
            let memberData = document.data()
            
            // Extract familyID from the document path: families/{familyID}/members/{userID}
            let pathParts = document.reference.path.split(separator: "/")
            guard pathParts.count >= 4, pathParts[0] == "families", pathParts[2] == "members" else {
                continue
            }
            let familyFirebaseID = String(pathParts[1])
            
            // Get family localID from Firestore
            let familyDoc = try? await db.collection("families").document(familyFirebaseID).getDocument()
            guard let familyData = familyDoc?.data(),
                  let localIDString = familyData["localID"] as? String,
                  let familyLocalID = UUID(uuidString: localIDString) else {
                continue
            }
            
            // Create FamilyMember from Firestore data
            // Document ID is now the userID
            let documentUserID = document.documentID
            if let member = familyMemberFromFirestoreData(memberData, familyID: familyLocalID, userID: documentUserID, modelContext: modelContext) {
                pendingMembers.append(member)
                
                // Ensure it's saved locally
                let userIDValue = documentUserID
                let familyIDValue = familyLocalID
                let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate<FamilyMember> {
                    $0.userID == userIDValue && $0.familyID == familyIDValue
                })
                let existingMember = try? modelContext.fetch(descriptor).first
                if existingMember == nil {
                    modelContext.insert(member)
                    // Also need to associate with family
                    if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                        $0.id == familyLocalID
                    })).first {
                        family.members.append(member)
                    }
                }
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
        
        // Sync families that need sync
        let familyDescriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> {
            $0.needsSync == true
        })
        if let families = try? modelContext.fetch(familyDescriptor) {
            for family in families {
                do {
                    try await saveFamilyToFirestore(family)
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
                            } else {
                                // Insert new member
                                modelContext.insert(member)
                                // Associate with family
                                if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                                    $0.id == familyID
                                })).first {
                                    family.members.append(member)
                                }
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
                            memberToRemove.isActive = false
                            // Optionally remove from family relationship
                            if let family = try? modelContext.fetch(FetchDescriptor<Family>(predicate: #Predicate<Family> {
                                $0.id == familyID
                            })).first {
                                family.members.removeAll { $0.id == memberToRemove.id }
                            }
                            try? modelContext.save()
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

