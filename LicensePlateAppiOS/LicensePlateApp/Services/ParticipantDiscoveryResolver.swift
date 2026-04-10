//
//  ParticipantDiscoveryResolver.swift
//  LicensePlateApp
//
//  Step 05 — resolve first finder, all finders, and summary label for UI badges/chips.
//

import Foundation

/// Summary for UI: who found a target and how to display it. Game-agnostic (works off participantId and discoveredAt).
struct ParticipantDiscoverySummary: Sendable {
    /// First finder by discovery time (for display priority).
    var firstFinderParticipantId: String?
    /// All finder participant ids, ordered by discoveredAt ascending.
    var allFinderParticipantIds: [String]
    /// Placeholder label for badges/chips, e.g. "Found by user1" or "3 finders". Localize later.
    var summaryLabel: String
}

/// Resolves first finder, all finders, and summary from discoveries for a single target. No persistence.
enum ParticipantDiscoveryResolver {

    /// Builds a summary from discoveries for one target (e.g. same targetId). Sorts by discoveredAt for first-finder and order.
    /// - Parameter gameMode: Drives label emphasis via `GameModeRulesEngine.displayFirstFinderProminently` (competitive vs collaborative).
    static func summary(discoveries: [GameDiscovery], gameMode: GameMode = .collaborative) -> ParticipantDiscoverySummary {
        let sorted = discoveries.sorted { GameDiscovery.orderingAscending($0, $1) }
        let allIds = sorted.map(\.participantId)
        let firstId = allIds.first
        let label: String
        if allIds.isEmpty {
            label = ""
        } else if GameModeRulesEngine.displayFirstFinderProminently(mode: gameMode) {
            if let id = firstId {
                label = "Found by %@".localized(id)
            } else {
                label = ""
            }
        } else if allIds.count == 1, let id = firstId {
            label = "Found by %@".localized(id)
        } else {
            label = "%d finders".localized(allIds.count)
        }
        return ParticipantDiscoverySummary(
            firstFinderParticipantId: firstId,
            allFinderParticipantIds: allIds,
            summaryLabel: label
        )
    }

    /// Step 15 — Recap: collaborative multi-finder line with display names (`displayNames` falls back to raw ids).
    static func collaborativeMultiFinderDisplayLabel(
        orderedParticipantIds: [String],
        displayNames: [String: String]
    ) -> String {
        guard orderedParticipantIds.count >= 2 else {
            if let id = orderedParticipantIds.first {
                let name = displayNames[id] ?? id
                return "Found by %@".localized(name)
            }
            return ""
        }
        let names = orderedParticipantIds.map { displayNames[$0] ?? $0 }
        switch names.count {
        case 2:
            return "Found by %@ and %@".localized(names[0], names[1])
        case 3:
            return "Found by %@, %@, and %@".localized(names[0], names[1], names[2])
        default:
            let otherCount = names.count - 2
            return "Found by %@, %@, and %d others".localized(names[0], names[1], otherCount)
        }
    }
}
