//
//  LifetimeStatsSnapshots.swift
//  LicensePlateApp
//
//  Sendable DTOs crossed from MainActor fetch into background recompute.
//

import Foundation

struct LifetimeStatsRecomputeInput: Sendable {
    var subjectUserId: String
    var familyMemberUserIds: Set<String>
    var friendUserIds: Set<String>
    var trips: [LifetimeStatsTripInput]
}

struct LifetimeStatsTripInput: Sendable {
    var session: LifetimeStatsSessionSnapshot
    var games: [LifetimeStatsGameSnapshot]
    var discoveries: [GameDiscovery]
}

struct LifetimeStatsSessionSnapshot: Sendable {
    var id: UUID
    var name: String
    var statusRaw: String
    var createdAt: Date
    var createdBy: String?
    var startedAt: Date?
    var endedAt: Date?
    var endedBy: String?
    var participants: [TripParticipant]
    var riskFlags: [String]?
}

struct LifetimeStatsGameSnapshot: Sendable {
    var id: UUID
    var definitionId: String
    var sessionId: UUID
    var startedAt: Date
    var endedAt: Date?
    var ruleSet: GameRuleSet
    var commonConfig: CommonGameConfig
    var gameSpecificPayloadType: String?
    var gameSpecificPayloadVersion: String?
    var gameSpecificPayloadData: Data?
    var teams: [TripTeam]
    var fairnessUiLastAckAt: Date?
}
