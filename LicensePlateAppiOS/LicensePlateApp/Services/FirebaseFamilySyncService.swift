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
        
        return familyFromFirestoreData(data, firebaseID: familyID)
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
        
        return familyFromFirestoreData(data, firebaseID: document.documentID)
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
        
        return familyFromFirestoreData(data, firebaseID: document.documentID)
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
        
        let docRef = db.collection("families").document(familyFirebaseID)
            .collection("members").document(member.id.uuidString)
        
      var data: [String: Any] = [
            "id": member.id.uuidString,
            "userID": member.userID,
            "familyID": member.familyID.uuidString,
            "role": member.role.rawValue,
            "joinedAt": Timestamp(date: member.joinedAt),
            "isActive": member.isActive
        ]
        
        if let invitedBy = member.invitedBy {
            data["invitedBy"] = invitedBy
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
    
    private func familyFromFirestoreData(_ data: [String: Any], firebaseID: String) -> Family? {
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
        return family
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
    
    enum SyncError: Error {
        case noModelContext
        case offline
        case invalidData
    }
}

