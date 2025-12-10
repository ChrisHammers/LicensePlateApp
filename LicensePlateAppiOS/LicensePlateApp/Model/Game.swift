//
//  Game.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var gameMode: GameMode
    var scoringType: ScoringType
    var createdBy: String // User ID
    var isPublic: Bool = false
    var shareCode: String? // For public sharing
    
    // Teams
    @Relationship(deleteRule: .cascade, inverse: \GameTeam.game)
    var teams: [GameTeam] = []
    
    // Settings
    var maxTeamSize: Int?
    var minTeamSize: Int = 2
    var enabledCountryStrings: String = "United States,Canada,Mexico"
    
    // Firebase sync
    var firebaseGameID: String?
    var needsSync: Bool = false
    
    enum GameMode: String, Codable, CaseIterable {
        case competitive // Playing AGAINST
        case collaborative // Playing WITH (single team)
        
        var displayName: String {
            switch self {
            case .competitive: return "Competitive"
            case .collaborative: return "Collaborative"
            }
        }
    }
    
    enum ScoringType: String, Codable, CaseIterable {
        case totalFound // Highest total plates
        case uniqueFound // Most unique plates (no duplicates)
        case timeBased // First to find X plates
        case custom // User-defined rules
        
        var displayName: String {
            switch self {
            case .totalFound: return "Total Found"
            case .uniqueFound: return "Unique Found"
            case .timeBased: return "Time Based"
            case .custom: return "Custom"
            }
        }
    }
    
    // Computed property to get countries as enum array
    var enabledCountries: [PlateRegion.Country] {
        get {
            enabledCountryStrings
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap { PlateRegion.Country(rawValue: String($0)) }
        }
        set {
            enabledCountryStrings = newValue.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        gameMode: GameMode,
        scoringType: ScoringType,
        createdBy: String,
        isPublic: Bool = false,
        shareCode: String? = nil,
        teams: [GameTeam] = [],
        maxTeamSize: Int? = nil,
        minTeamSize: Int = 2,
        enabledCountries: [PlateRegion.Country] = [.unitedStates, .canada, .mexico],
        firebaseGameID: String? = nil,
        needsSync: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.gameMode = gameMode
        self.scoringType = scoringType
        self.createdBy = createdBy
        self.isPublic = isPublic
        self.shareCode = shareCode
        self.teams = teams
        self.maxTeamSize = maxTeamSize
        self.minTeamSize = minTeamSize
        self.enabledCountryStrings = enabledCountries.map { $0.rawValue }.joined(separator: ",")
        self.firebaseGameID = firebaseGameID
        self.needsSync = needsSync
    }
    
    /// Check if game is active
    var isActive: Bool {
        startedAt != nil && endedAt == nil
    }
    
    /// Check if game has ended
    var hasEnded: Bool {
        endedAt != nil
    }
    
    /// Generate a share code if one doesn't exist
    func generateShareCodeIfNeeded() {
        if shareCode == nil {
            shareCode = UUID().uuidString.prefix(8).uppercased()
        }
    }
}

