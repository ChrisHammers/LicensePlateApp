//
//  GameInstanceState.swift
//  LicensePlateApp
//
//  Per-game lifecycle (Step 6.9.3); stored on GameInstance.commonConfig.
//

import Foundation

/// Lifecycle state of a game instance. Games are not "enabled/disabled"; they use these states.
enum GameInstanceState: String, Codable, CaseIterable, Sendable {
    /// Game configured but not yet started.
    case created
    /// Game is active; discoveries can be recorded.
    case started
    /// Game session stopped manually or trip ended.
    case ended
    /// Completion goal achieved.
    case completed
}
