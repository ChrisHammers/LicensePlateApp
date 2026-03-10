//
//  TripParticipant.swift
//  LicensePlateApp
//
//  Gameplay model foundation — participant identity and role in a trip session.
//

import Foundation

/// Role of a participant in a trip (e.g. owner vs member).
enum TripParticipantRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
}

/// A participant in a trip session. SwiftData-ready shape; no @Model in Step 01.
struct TripParticipant: Codable, Identifiable, Sendable {
    /// User id (matches AppUser.id).
    var userId: String
    /// Role in the trip.
    var role: TripParticipantRole
    /// When they joined.
    var joinedAt: Date
    /// When they left, if applicable.
    var leftAt: Date?

    var id: String { "\(userId)_\(joinedAt.timeIntervalSince1970)" }

    init(userId: String, role: TripParticipantRole = .member, joinedAt: Date = .now, leftAt: Date? = nil) {
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
        self.leftAt = leftAt
    }
}
