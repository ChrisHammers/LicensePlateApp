//
//  TripSummary.swift
//  LicensePlateApp
//
//  Step 07 — Rich summary for a completed trip (Travel Log detail). Built by TripSummaryBuilder.
//

import Foundation

/// High-level stats and metadata for one game in a trip. Step 07.5 — completionGoal and progressDescription from game config.
struct TripSummaryGameItem: Sendable {
    var gameInstanceId: UUID
    var definitionId: String
    var discoveryCount: Int
    var startedAt: Date?
    var endedAt: Date?
    /// First discoveries or notable events (e.g. target id + label).
    var firstDiscoveries: [TargetDiscoverySummary]
    /// Step 07.5 — Target count from game config (e.g. 50 for US states). Nil when config not available.
    var completionGoal: Int?
    /// Step 07.5 — Human-readable progress (e.g. "42 / 50 US states"). Nil when config not available.
    var progressDescription: String?
    /// Game-level collaborative vs competitive (from `GameInstance.commonConfig`).
    var gameMode: GameMode
    /// Short teams summary when `teams` was non-empty on the game; nil otherwise.
    var teamSummary: String?
}

/// Rich summary of a completed trip for TripSummaryView. All optional where data may be missing (e.g. no legacy Trip).
struct TripSummary: Sendable {
    var sessionId: UUID
    var tripName: String
    /// Trip participation: solo vs multiplayer (derived from `TripSession` roster via `TripSession.mode`).
    var tripMode: TripMode
    var status: TripSessionState
    var endedAt: Date?
    var startedAt: Date?
    var participantCount: Int
    var gameCount: Int
    /// Total discoveries across all games (when available).
    var totalDiscoveryCount: Int
    /// Per-game breakdown.
    var games: [TripSummaryGameItem]
    /// Roster-merged participant rows with competition rank and score ties (Step 11).
    var rankedParticipants: [RankedParticipantContribution]
    /// Target-level discovery details (first finder, labels) for UI.
    var discoveryProjection: DiscoveryCreditProjection?
    /// Optional location metadata for future map recap.
    var locationMetadata: [String: String]?

    /// True when any game on the trip is competitive (for summary UI: ranks, first-finds column).
    var hasCompetitiveGame: Bool {
        games.contains { $0.gameMode == .competitive }
    }

    /// Discoveries attributed to a known `GameInstance` row on this recap (sum of per-game counts).
    var assignedDiscoveryCount: Int {
        games.reduce(0) { $0 + $1.discoveryCount }
    }

    /// Events exist for games not present in `games` (e.g. deleted instance); recap may omit per-game detail for these.
    var unassignedDiscoveryCount: Int {
        max(0, totalDiscoveryCount - assignedDiscoveryCount)
    }
}
