//
//  TripSummary.swift
//  LicensePlateApp
//
//  Step 07 — Rich summary for a completed trip (Travel Log detail). Built by TripSummaryBuilder.
//

import Foundation

/// High-level stats and metadata for one game in a trip.
struct TripSummaryGameItem: Sendable {
    var gameInstanceId: UUID
    var definitionId: String
    var discoveryCount: Int
    var startedAt: Date?
    var endedAt: Date?
    /// First discoveries or notable events (e.g. target id + label).
    var firstDiscoveries: [TargetDiscoverySummary]
}

/// Rich summary of a completed trip for TripSummaryView. All optional where data may be missing (e.g. no legacy Trip).
struct TripSummary: Sendable {
    var sessionId: UUID
    var tripName: String
    var status: TripStatus
    var endedAt: Date?
    var startedAt: Date?
    var participantCount: Int
    var gameCount: Int
    /// Total discoveries across all games (when available).
    var totalDiscoveryCount: Int
    /// Per-game breakdown.
    var games: [TripSummaryGameItem]
    /// Participant contributions (discovery count, score, first finds).
    var participantContributions: [ParticipantContribution]
    /// Target-level discovery details (first finder, labels) for UI.
    var discoveryProjection: DiscoveryCreditProjection?
    /// Optional location metadata for future map recap.
    var locationMetadata: [String: String]?
}
