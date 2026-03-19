//
//  TripMode.swift
//  LicensePlateApp
//
//  Step 6.9.1 — Trip participation: solo vs multiplayer. Game-level mode (collaborative/competitive) is on GameInstance.
//

import Foundation

/// Whether the trip is single-participant or multi-participant. Game rules (collaborative vs competitive) are on GameInstance.commonConfig.gameMode.
enum TripMode: String, Codable, CaseIterable, Sendable {
    /// Single player; no other participants.
    case solo
    /// Multiple participants (invited or joined). Game mode per game is on GameInstance.
    case multiplayer
}
