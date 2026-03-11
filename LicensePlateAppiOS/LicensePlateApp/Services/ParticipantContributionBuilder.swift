//
//  ParticipantContributionBuilder.swift
//  LicensePlateApp
//
//  Step 06.5.5 — per-participant contribution summary from discoveries and credits.
//

import Foundation

/// Per-participant contribution summary: discovery count, weighted score, first-find count.
struct ParticipantContribution: Sendable {
    var participantId: String
    var discoveryCount: Int
    var weightedScore: Double
    var firstFindCount: Int
}

/// Builds per-participant contribution summaries from discoveries and credits. Pure logic; no persistence.
/// Uses ParticipantDiscoveryResolver for first-finder per target; uses credits for weights.
enum ParticipantContributionBuilder {

    /// Build contribution summary for each participant that appears in discoveries or credits.
    /// - Parameters:
    ///   - discoveries: All discoveries (e.g. for a game instance).
    ///   - credits: Precomputed credits; used for weighted score. When empty, each discovery counts as weight 1.0 for its participant.
    /// - Returns: One ParticipantContribution per participant (discovery count, weighted score, first-find count).
    static func contributionSummary(
        discoveries: [GameDiscovery],
        credits: [GameCredit]
    ) -> [ParticipantContribution] {
        let discoveryCountByParticipant = Dictionary(grouping: discoveries, by: \.participantId)
            .mapValues { $0.count }
        let weightedScoreByParticipant: [String: Double]
        if credits.isEmpty {
            weightedScoreByParticipant = discoveryCountByParticipant.mapValues { Double($0) }
        } else {
            weightedScoreByParticipant = Dictionary(grouping: credits, by: \.participantId)
                .mapValues { $0.compactMap(\.weight).reduce(0, +) }
        }
        let firstFindCountByParticipant = buildFirstFindCountByParticipant(discoveries: discoveries)
        let allParticipantIds = Set(discoveryCountByParticipant.keys).union(weightedScoreByParticipant.keys)
        return allParticipantIds.map { participantId in
            ParticipantContribution(
                participantId: participantId,
                discoveryCount: discoveryCountByParticipant[participantId] ?? 0,
                weightedScore: weightedScoreByParticipant[participantId] ?? 0,
                firstFindCount: firstFindCountByParticipant[participantId] ?? 0
            )
        }
    }

    private static func buildFirstFindCountByParticipant(discoveries: [GameDiscovery]) -> [String: Int] {
        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        var firstFindCount: [String: Int] = [:]
        for (_, targetDiscoveries) in byTarget {
            let summary = ParticipantDiscoveryResolver.summary(discoveries: targetDiscoveries)
            if let firstId = summary.firstFinderParticipantId {
                firstFindCount[firstId, default: 0] += 1
            }
        }
        return firstFindCount
    }
}
