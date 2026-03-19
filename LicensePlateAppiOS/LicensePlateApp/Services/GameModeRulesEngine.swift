//
//  GameModeRulesEngine.swift
//  LicensePlateApp
//
//  Step 6.9.1 — Game-level rules: collaborative vs competitive unfind and credit. Use GameMode from GameInstance. Trip participation (solo vs multiplayer) is separate.
//

import Foundation

/// Pure logic for game mode behavior. No persistence, no Firebase. Game-agnostic (targetId opaque).
enum GameModeRulesEngine {

    // MARK: - Unfind rules

    /// Whether the given participant is allowed to unfind (remove) this discovery.
    /// - Collaborative: any finder can unfind.
    /// - Competitive: only the discoverer can unfind their own discovery.
    static func canParticipantUnfind(
        mode: GameMode,
        participantId: String,
        discovery: GameDiscovery,
        allDiscoveriesForTarget: [GameDiscovery]
    ) -> Bool {
        switch mode {
        case .collaborative:
            return allDiscoveriesForTarget.contains { $0.participantId == participantId }
        case .competitive:
            return discovery.participantId == participantId
        }
    }

    // MARK: - Credit type

    /// Credit type for the given mode: shared (collaborative) or full (competitive).
    static func creditType(for mode: GameMode) -> GameCreditType {
        switch mode {
        case .collaborative:
            return .shared
        case .competitive:
            return .full
        }
    }

    // MARK: - Display

    /// When true, UI should surface only the first finder prominently at trip level (competitive).
    /// When false, UI can show all finders (collaborative).
    static func displayFirstFinderProminently(mode: GameMode) -> Bool {
        switch mode {
        case .competitive:
            return true
        case .collaborative:
            return false
        }
    }
}
