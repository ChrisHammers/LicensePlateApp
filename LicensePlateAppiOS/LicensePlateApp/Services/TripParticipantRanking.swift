//
//  TripParticipantRanking.swift
//  LicensePlateApp
//
//  Step 11 — Competitive trip: roster merge, leaderboard ordering, competition ranks, score ties.
//

import Foundation

/// A duplicate-rejection attempt recorded for the current user (competitive mode); from `discoveryRejected` events.
struct CompetitiveDuplicateAttempt: Sendable, Identifiable {
    var id: String
    var targetId: String
    var timestamp: Date
}

/// One row on a leaderboard: contribution plus placement. `rank` uses **competition ranking** by `weightedScore` only
/// (e.g. 10, 10, 8 → ranks 1, 1, 3). Sort order within the same score uses firstFindCount, discoveryCount, participantId.
/// `isTiedOnScore` is true when at least one other participant shares the same `weightedScore` (for UI / a11y).
struct RankedParticipantContribution: Sendable, Identifiable {
    var contribution: ParticipantContribution
    /// 1-based competition rank by weighted score.
    var rank: Int
    var isTiedOnScore: Bool

    var id: String { contribution.participantId }
}

/// Ensures every trip roster member appears in contribution rows (zeros when they have no discoveries/credits).
enum TripRosterContributionMerge {

    /// Merges `contributions` with `roster`: all `userId`s from roster are present; extra contribution-only ids are kept.
    static func merge(roster: [TripParticipant], contributions: [ParticipantContribution]) -> [ParticipantContribution] {
        var byId: [String: ParticipantContribution] = Dictionary(
            uniqueKeysWithValues: contributions.map { ($0.participantId, $0) }
        )
        for p in roster {
            if byId[p.userId] == nil {
                byId[p.userId] = ParticipantContribution(
                    participantId: p.userId,
                    discoveryCount: 0,
                    weightedScore: 0,
                    firstFindCount: 0
                )
            }
        }
        return byId.values.sorted { $0.participantId < $1.participantId }
    }
}

/// Pure ranking for trip or single-game standings.
enum TripParticipantRanking {

    /// Sort: `weightedScore` desc, `firstFindCount` desc, `discoveryCount` desc, `participantId` asc.
    /// Ranks: tied `weightedScore` → same rank; next rank skips (1, 1, 3).
    static func rankContributions(_ items: [ParticipantContribution]) -> [RankedParticipantContribution] {
        guard !items.isEmpty else { return [] }

        let sorted = items.sorted { a, b in
            if a.weightedScore != b.weightedScore {
                return a.weightedScore > b.weightedScore
            }
            if a.firstFindCount != b.firstFindCount {
                return a.firstFindCount > b.firstFindCount
            }
            if a.discoveryCount != b.discoveryCount {
                return a.discoveryCount > b.discoveryCount
            }
            return a.participantId < b.participantId
        }

        let scoreCounts = Dictionary(grouping: sorted, by: \.weightedScore).mapValues(\.count)

        var result: [RankedParticipantContribution] = []
        result.reserveCapacity(sorted.count)

        var currentRank = 1
        for (index, c) in sorted.enumerated() {
            if index > 0 {
                let prev = sorted[index - 1].weightedScore
                if c.weightedScore != prev {
                    currentRank = index + 1
                }
            }
            let tied = (scoreCounts[c.weightedScore] ?? 0) > 1
            result.append(RankedParticipantContribution(contribution: c, rank: currentRank, isTiedOnScore: tied))
        }
        return result
    }
}
