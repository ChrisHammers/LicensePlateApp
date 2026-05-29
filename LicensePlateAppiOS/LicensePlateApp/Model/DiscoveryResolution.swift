//
//  DiscoveryResolution.swift
//  LicensePlateApp
//
//  Canonical post-reconciliation record (separate axes for discovery vs trip scoring vs personal history).
//

import Foundation

struct DiscoveryResolution: Identifiable, Codable, Sendable, Equatable {
    var id: String { resolutionId }
    var resolutionId: String
    var sourceEventId: String
    var sessionId: UUID
    var gameInstanceId: UUID
    var itemId: String
    var actorUserId: String
    var finalOutcome: DiscoveryResolutionOutcome
    var tripScoringOutcome: TripScoringOutcome
    var personalHistoryOutcome: PersonalHistoryOutcome
    var finalXpAward: Int
    var xpReason: XpReasonCode
    var resolvedAgainstEventId: String?
    var serverSequence: Int64
    var resolutionVersion: Int
    var resolvedAtServer: Date?

    init(
        resolutionId: String = UUID().uuidString,
        sourceEventId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String,
        actorUserId: String,
        finalOutcome: DiscoveryResolutionOutcome,
        tripScoringOutcome: TripScoringOutcome,
        personalHistoryOutcome: PersonalHistoryOutcome,
        finalXpAward: Int,
        xpReason: XpReasonCode,
        resolvedAgainstEventId: String? = nil,
        serverSequence: Int64 = 0,
        resolutionVersion: Int = 1,
        resolvedAtServer: Date? = nil
    ) {
        self.resolutionId = resolutionId
        self.sourceEventId = sourceEventId
        self.sessionId = sessionId
        self.gameInstanceId = gameInstanceId
        self.itemId = itemId
        self.actorUserId = actorUserId
        self.finalOutcome = finalOutcome
        self.tripScoringOutcome = tripScoringOutcome
        self.personalHistoryOutcome = personalHistoryOutcome
        self.finalXpAward = finalXpAward
        self.xpReason = xpReason
        self.resolvedAgainstEventId = resolvedAgainstEventId
        self.serverSequence = serverSequence
        self.resolutionVersion = resolutionVersion
        self.resolvedAtServer = resolvedAtServer
    }
}

extension DiscoveryResolution {
    /// Latest resolution row for an item when multiple versions exist (higher `serverSequence` wins).
    static func preferredLatest(in resolutions: [DiscoveryResolution]) -> DiscoveryResolution? {
        resolutions.max { a, b in
            if a.serverSequence != b.serverSequence { return a.serverSequence < b.serverSequence }
            return a.resolutionId < b.resolutionId
        }
    }
}
