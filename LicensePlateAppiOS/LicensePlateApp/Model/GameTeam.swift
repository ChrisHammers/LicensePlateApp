//
//  GameTeam.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class GameTeam {
    @Attribute(.unique) var id: UUID
    var gameID: UUID
    var name: String?
    var pilotID: String // User ID of team captain
    var memberIDs: [String] // User IDs of team members
    var tripIDs: [UUID] = [] // Trips associated with this team
    var score: Int = 0
    var createdAt: Date
    
    // Relationship to Game
    var game: Game?
    
    init(
        id: UUID = UUID(),
        gameID: UUID,
        name: String? = nil,
        pilotID: String,
        memberIDs: [String] = [],
        tripIDs: [UUID] = [],
        score: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.gameID = gameID
        self.name = name
        self.pilotID = pilotID
        self.memberIDs = memberIDs
        self.tripIDs = tripIDs
        self.score = score
        self.createdAt = createdAt
    }
    
    /// Get all team member IDs including pilot
    var allMemberIDs: [String] {
        var all = memberIDs
        if !all.contains(pilotID) {
            all.insert(pilotID, at: 0)
        }
        return all
    }
    
    /// Check if a user is the pilot
    func isPilot(userID: String) -> Bool {
        pilotID == userID
    }
    
    /// Check if a user is a member of this team
    func isMember(userID: String) -> Bool {
        allMemberIDs.contains(userID)
    }
    
    /// Add a member to the team
    func addMember(_ userID: String) {
        if !allMemberIDs.contains(userID) {
            memberIDs.append(userID)
        }
    }
    
    /// Remove a member from the team (cannot remove pilot)
    func removeMember(_ userID: String) {
        guard userID != pilotID else { return }
        memberIDs.removeAll { $0 == userID }
    }
    
    /// Change the pilot
    func changePilot(to userID: String) {
        guard allMemberIDs.contains(userID) else { return }
        // Add old pilot to members if not already there
        if !memberIDs.contains(pilotID) {
            memberIDs.append(pilotID)
        }
        // Remove new pilot from members
        memberIDs.removeAll { $0 == userID }
        pilotID = userID
    }
}

