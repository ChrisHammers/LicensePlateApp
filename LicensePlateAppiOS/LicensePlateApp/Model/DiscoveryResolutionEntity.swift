//
//  DiscoveryResolutionEntity.swift
//  LicensePlateApp
//

import Foundation
import SwiftData

@Model
final class DiscoveryResolutionEntity {
    var resolutionId: String
    var sourceEventId: String
    var sessionId: String
    var gameInstanceId: String
    var itemId: String
    var actorUserId: String
    var finalOutcome: String
    var tripScoringOutcome: String
    var personalHistoryOutcome: String
    var finalXpAward: Int
    var xpReason: String
    var resolvedAgainstEventId: String?
    var serverSequence: Int64
    var resolutionVersion: Int
    var resolvedAtServer: Date?

    init(
        resolutionId: String,
        sourceEventId: String,
        sessionId: String,
        gameInstanceId: String,
        itemId: String,
        actorUserId: String,
        finalOutcome: String,
        tripScoringOutcome: String,
        personalHistoryOutcome: String,
        finalXpAward: Int,
        xpReason: String,
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
