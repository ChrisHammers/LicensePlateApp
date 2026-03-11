//
//  TripModeRulesEngine.swift
//  LicensePlateApp
//
//  Step 05 — participant-aware trip mode rules: collaborative vs competitive unfind and credit.
//

import Foundation

/// Pure logic for trip mode behavior. No persistence, no Firebase. Game-agnostic (targetId opaque).
enum TripModeRulesEngine {

    // MARK: - Unfind rules

    /// Whether the given participant is allowed to unfind (remove) this discovery.
    /// - Collaborative: any finder can unfind.
    /// - Competitive: only the discoverer can unfind their own discovery.
    /// - Solo: only the single participant can unfind (they are the discoverer).
    /// - Combined: same as collaborative for unfind (any finder can unfind).
    static func canParticipantUnfind(
        mode: TripMode,
        participantId: String,
        discovery: GameDiscovery,
        allDiscoveriesForTarget: [GameDiscovery]
    ) -> Bool {
        switch mode {
        case .solo:
            return discovery.participantId == participantId
        case .collaborative, .combined:
            return allDiscoveriesForTarget.contains { $0.participantId == participantId }
        case .competitive:
            return discovery.participantId == participantId
        }
    }

    // MARK: - Credit type

    /// Credit type for the given mode: shared (collaborative) or full (solo/competitive/combined).
    static func creditType(for mode: TripMode) -> GameCreditType {
        switch mode {
        case .collaborative:
            return .shared
        case .solo, .competitive, .combined:
            return .full
        }
    }

    // MARK: - Display

    /// When true, UI should surface only the first finder prominently at trip level (competitive).
    /// When false, UI can show all finders (collaborative).
    static func displayFirstFinderProminently(mode: TripMode) -> Bool {
        switch mode {
        case .competitive:
            return true
        case .solo, .collaborative, .combined:
            return false
        }
    }
}
