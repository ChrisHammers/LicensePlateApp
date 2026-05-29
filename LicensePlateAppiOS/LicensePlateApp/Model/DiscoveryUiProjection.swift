//
//  DiscoveryUiProjection.swift
//  LicensePlateApp
//
//  Read model for discovery tiles/rows — views should use this instead of ad hoc XP rules.
//

import Foundation

/// High-level tile state for a single item in a game (stable across pending/final XP transitions).
enum DiscoveryTileDisplayState: String, Codable, Sendable, CaseIterable {
    case notFound
    /// User or trip still shows the find visually while server/ledger reconciles.
    case foundVisuallyActive
    case foundVisuallyRemoved
}

/// XP phase for the viewer on this item (ledger-driven).
enum DiscoveryXpProjectionPhase: String, Codable, Sendable, CaseIterable {
    case none
    case provisional
    case finalPending
    case final
}

/// Coarse sync state for messaging (not a wire protocol).
enum DiscoverySyncProjectionState: String, Codable, Sendable, CaseIterable {
    case localOnly
    case synced
    case supersededOrAdjusted
}

struct DiscoveryUiProjection: Identifiable, Sendable, Equatable {
    var id: String { "\(sessionId.uuidString)|\(gameInstanceId.uuidString)|\(itemId)|\(viewerUserId)" }

    var sessionId: UUID
    var gameInstanceId: UUID
    var itemId: String
    var viewerUserId: String

    var displayState: DiscoveryTileDisplayState
    var tripAttribution: ParticipantDiscoverySummary
    /// Whether the viewer has any active discovery row for this item (replay-derived).
    var viewerHasActiveDiscovery: Bool
    var xpPhase: DiscoveryXpProjectionPhase
    /// Net XP delta shown for this item from ledger rows for this viewer (provisional + final rows for the base key).
    var xpShownDelta: Int
    var syncState: DiscoverySyncProjectionState
    var statusBadgeText: String?
    var lastUpdated: Date
}
