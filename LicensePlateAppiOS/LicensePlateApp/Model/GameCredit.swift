//
//  GameCredit.swift
//  LicensePlateApp
//
//  Gameplay model foundation — attribution for a discovery (collaborative vs competitive).
//

import Foundation

/// How credit is assigned for a discovery: full (solo/competitive) or shared (collaborative).
enum GameCreditType: String, Codable, CaseIterable, Sendable {
    /// Single participant gets full credit (solo or competitive).
    case full
    /// Credit shared among participants (collaborative).
    case shared
}

/// Attribution for a single discovery. Supports both collaborative (shared) and competitive (per-participant) scoring.
struct GameCredit: Codable, Identifiable, Sendable, Equatable {
    /// Stable id for this credit record.
    var id: String
    /// Discovery this credit applies to.
    var discoveryId: String
    /// Participant receiving this credit (user id).
    var participantId: String
    /// Full or shared.
    var creditType: GameCreditType
    /// Optional weight for scoring (e.g. 1.0 for full, 0.5 for shared).
    var weight: Double?
    /// Team id when credit is attributed via game-scoped `TripTeam` lists (`GameCreditCalculator`).
    var teamId: String?

    init(
        id: String = UUID().uuidString,
        discoveryId: String,
        participantId: String,
        creditType: GameCreditType,
        weight: Double? = nil,
        teamId: String? = nil
    ) {
        self.id = id
        self.discoveryId = discoveryId
        self.participantId = participantId
        self.creditType = creditType
        self.weight = weight
        self.teamId = teamId
    }
}
