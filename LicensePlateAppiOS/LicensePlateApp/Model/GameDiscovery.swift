//
//  GameDiscovery.swift
//  LicensePlateApp
//
//  Gameplay model foundation — a single “find” (e.g. region found), participant-scoped; replaces single-owner FoundRegion semantics.
//

import Foundation

/// A single discovery in a game (e.g. a region found). Uses existing FoundRegion.InputMethod for input type.
struct GameDiscovery: Codable, Identifiable, Sendable {
    var id: String
    /// Game instance this discovery belongs to.
    var gameInstanceId: UUID
    /// Participant who made the discovery (user id).
    var participantId: String
    /// Target id (e.g. regionID for license-plate game).
    var targetId: String
    var discoveredAt: Date
    /// How it was discovered (list, voice, etc.).
    var inputMethod: FoundRegion.InputMethod
    /// Optional location at discovery time.
    var location: LocationData?
    /// Legacy/transitional: single risk string. Kept only for backward compatibility. Do not write for new flows; use `riskFlags` instead. Step 11.6.
    var riskFlag: String?
    /// Authoritative discovery risk field (Step 11 expected structure). New code must use this for display, analytics, and presentation. Legacy-adapted discoveries may have nil.
    var riskFlags: [RiskFlag]?

    init(
        id: String = UUID().uuidString,
        gameInstanceId: UUID,
        participantId: String,
        targetId: String,
        discoveredAt: Date = .now,
        inputMethod: FoundRegion.InputMethod,
        location: LocationData? = nil,
        riskFlag: String? = nil,
        riskFlags: [RiskFlag]? = nil
    ) {
        self.id = id
        self.gameInstanceId = gameInstanceId
        self.participantId = participantId
        self.targetId = targetId
        self.discoveredAt = discoveredAt
        self.inputMethod = inputMethod
        self.location = location
        self.riskFlag = riskFlag
        self.riskFlags = riskFlags
    }

    /// Highest severity among risk flags, if any.
    var highestRiskSeverity: RiskSeverity? {
        riskFlags?.map(\.severity).max()
    }

    /// True if any flag has review severity.
    var hasReviewLevelRisk: Bool {
        riskFlags?.contains(where: { $0.severity == .review }) ?? false
    }

    var riskFlagCount: Int {
        riskFlags?.count ?? 0
    }
}
