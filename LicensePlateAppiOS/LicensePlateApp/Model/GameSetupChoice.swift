//
//  GameSetupChoice.swift
//  LicensePlateApp
//
//  Step 6.9.4 — Per-game setup inputs (mode, teams); trip participation is roster-derived separately.
//

import Foundation

/// Choices for assembling one `GameInstance`; not derived from trip participation (roster size).
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
