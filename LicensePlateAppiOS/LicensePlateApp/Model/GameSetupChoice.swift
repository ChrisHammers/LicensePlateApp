//
//  GameSetupChoice.swift
//  LicensePlateApp
//
//  Step 6.9.4 — Per-game setup inputs (mode, teams) distinct from trip-level TripMode.
//

import Foundation

/// Choices for assembling one `GameInstance`; not derived from `TripSession.mode`.
struct GameSetupChoice: Sendable {
    var gameType: GameType
    var gameMode: GameMode
    var teams: [TripTeam]

    init(gameType: GameType, gameMode: GameMode = .collaborative, teams: [TripTeam] = []) {
        self.gameType = gameType
        self.gameMode = gameMode
        self.teams = teams
    }
}
