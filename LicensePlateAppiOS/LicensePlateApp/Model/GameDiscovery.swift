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
    /// Optional risk flag for future anti-spam.
    var riskFlag: String?

    init(
        id: String = UUID().uuidString,
        gameInstanceId: UUID,
        participantId: String,
        targetId: String,
        discoveredAt: Date = .now,
        inputMethod: FoundRegion.InputMethod,
        location: LocationData? = nil,
        riskFlag: String? = nil
    ) {
        self.id = id
        self.gameInstanceId = gameInstanceId
        self.participantId = participantId
        self.targetId = targetId
        self.discoveredAt = discoveredAt
        self.inputMethod = inputMethod
        self.location = location
        self.riskFlag = riskFlag
    }
}
