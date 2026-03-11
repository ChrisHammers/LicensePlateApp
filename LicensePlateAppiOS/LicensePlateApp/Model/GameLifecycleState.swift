//
//  GameLifecycleState.swift
//  LicensePlateApp
//
//  Step 07.5 — Per-game lifecycle: created, started, ended, completed.
//

import Foundation

/// Lifecycle state of a game instance. Games are not "enabled/disabled"; they use these states.
enum GameLifecycleState: String, Codable, CaseIterable, Sendable {
    /// Game configured but not yet started.
    case created
    /// Game is active; discoveries can be recorded.
    case started
    /// Game session stopped manually or trip ended.
    case ended
    /// Completion goal achieved.
    case completed
}
