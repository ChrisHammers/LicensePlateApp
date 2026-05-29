//
//  TripInvite.swift
//  LicensePlateApp
//
//  Step 04 — Multiplayer trip invites. Dedicated model (not extending Invite).
//

import Foundation
import SwiftData

@Model
final class TripInvite {
    @Attribute(.unique) var inviteId: String
    var tripSessionId: String
    var tripName: String
    var fromUserId: String
    var toUserId: String?
    var status: String // sent, pending, accepted, declined, expired, canceled
    var createdAt: Date
    var expiresAt: Date
    var respondedAt: Date?

    enum TripInviteStatus: String, Codable, CaseIterable {
        case sent
        case pending
        case accepted
        case declined
        case expired
        case canceled
    }

    init(
        inviteId: String,
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String? = nil,
        status: TripInviteStatus = .pending,
        createdAt: Date = .now,
        expiresAt: Date,
        respondedAt: Date? = nil
    ) {
        self.inviteId = inviteId
        self.tripSessionId = tripSessionId
        self.tripName = tripName
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.status = status.rawValue
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.respondedAt = respondedAt
    }

    var isExpired: Bool {
        expiresAt < Date()
    }

    var statusEnum: TripInviteStatus {
        get {
            TripInviteStatus(rawValue: status) ?? .pending
        }
        set {
            status = newValue.rawValue
        }
    }
}
