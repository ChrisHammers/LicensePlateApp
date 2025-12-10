//
//  AppCompetition.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

struct CompetitionEntry: Codable {
    var userID: String?
    var familyID: UUID?
    var teamID: UUID?
    var score: Int
    var rank: Int
    
    init(
        userID: String? = nil,
        familyID: UUID? = nil,
        teamID: UUID? = nil,
        score: Int = 0,
        rank: Int = 0
    ) {
        self.userID = userID
        self.familyID = familyID
        self.teamID = teamID
        self.score = score
        self.rank = rank
    }
}

@Model
final class AppCompetition {
    @Attribute(.unique) var id: UUID
    var name: String
    var competitionDescription: String
    var startDate: Date
    var endDate: Date?
    var competitionType: CompetitionType
    var isActive: Bool = true
    
    // Leaderboard stored as JSON string for SwiftData compatibility
    var leaderboardJSON: String = "[]"
    
    // Firebase sync
    var firebaseCompetitionID: String?
    var needsSync: Bool = false
    
    enum CompetitionType: String, Codable, CaseIterable {
        case scheduled // Specific date range
        case ongoing // Always active, resets periodically
        
        var displayName: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .ongoing: return "Ongoing"
            }
        }
    }
    
    // Computed property for leaderboard
    var leaderboard: [CompetitionEntry] {
        get {
            guard let data = leaderboardJSON.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([CompetitionEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8) {
                leaderboardJSON = jsonString
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        startDate: Date,
        endDate: Date? = nil,
        competitionType: CompetitionType,
        isActive: Bool = true,
        leaderboard: [CompetitionEntry] = [],
        firebaseCompetitionID: String? = nil,
        needsSync: Bool = false
    ) {
        self.id = id
        self.name = name
        self.competitionDescription = description
        self.startDate = startDate
        self.endDate = endDate
        self.competitionType = competitionType
        self.isActive = isActive
        self.leaderboard = leaderboard
        self.firebaseCompetitionID = firebaseCompetitionID
        self.needsSync = needsSync
    }
    
    /// Check if competition is currently active
    var isCurrentlyActive: Bool {
        guard isActive else { return false }
        
        let now = Date()
        guard now >= startDate else { return false }
        
        if let endDate = endDate {
            return now <= endDate
        }
        
        // Ongoing competitions without end date are always active after start
        return competitionType == .ongoing
    }
    
    /// Add or update an entry in the leaderboard
    func updateLeaderboard(entry: CompetitionEntry) {
        var current = leaderboard
        if let index = current.firstIndex(where: { 
            $0.userID == entry.userID || 
            $0.familyID == entry.familyID || 
            $0.teamID == entry.teamID 
        }) {
            current[index] = entry
        } else {
            current.append(entry)
        }
        // Sort by score descending and update ranks
        current.sort { $0.score > $1.score }
        for (index, _) in current.enumerated() {
            current[index].rank = index + 1
        }
        leaderboard = current
    }
}

