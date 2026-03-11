//
//  TripTeam.swift
//  LicensePlateApp
//
//  Step 06.5 — Team support. A team definition within a trip session.
//

import Foundation

/// A team within a trip session. Used for team-based scoring and multi-car/group play.
struct TripTeam: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    /// User ids of participants assigned to this team.
    var participantUserIds: [String]

    init(id: String = UUID().uuidString, name: String, participantUserIds: [String] = []) {
        self.id = id
        self.name = name
        self.participantUserIds = participantUserIds
    }
}
