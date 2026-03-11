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
    static func summary(discoveries: [GameDiscovery]) -> ParticipantDiscoverySummary {
        let sorted = discoveries.sorted { $0.discoveredAt < $1.discoveredAt }
        let allIds = sorted.map(\.participantId)
        let firstId = allIds.first
        let label: String
        if allIds.isEmpty {
            label = ""
        } else if allIds.count == 1, let id = firstId {
            label = "Found by \(id)"
        } else {
            label = "\(allIds.count) finders"
        }
        return ParticipantDiscoverySummary(
            firstFinderParticipantId: firstId,
            allFinderParticipantIds: allIds,
            summaryLabel: label
        )
    }
}
