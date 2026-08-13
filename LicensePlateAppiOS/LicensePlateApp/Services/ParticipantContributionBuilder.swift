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

/// COPPA FR-28h: which finds may influence a competitive RESULT.
///
/// A late replay is a genuine find — it happened during the game, it just reached the
/// server after the game closed (offline play, or a child's queue draining at consent). It
/// counts everywhere a find counts: XP, lifetime stats, the found list, the recap's totals.
///
/// What it must not do is move an outcome. Competitive standings are frozen at trip end:
/// participants are expected to get their finds in before the game closes, and a result
/// that could be overturned days later by someone's phone reconnecting is not a result.
/// Collaborative and solo play have no winner, so nothing is filtered there.
enum CompetitiveOutcomeEligibility {

    /// The finds that may set the winner and weighted points.
    static func outcomeEligible(_ discoveries: [GameDiscovery]) -> [GameDiscovery] {
        discoveries.filter { !$0.isLateReplay }
    }

    /// Outcome-eligible finds AND the credits derived from exactly those finds.
    ///
    /// Both halves are required. `weightedScore` comes entirely from credits, so filtering
    /// the discovery list while passing credits built from the unfiltered set leaves the
    /// late find's weight in the score and the freeze does not hold. Callers must never
    /// build credits from one set and rank from another.
    ///
    /// This is deliberately NOT pushed down into `DiscoveryRulesEngine.creditsForDiscoveries`:
    /// that builder also feeds lifetime stats and the discovery-credit display projection,
    /// which must keep COUNTING late finds. Only outcome derivation freezes.
    static func outcomeInputs(
        discoveries: [GameDiscovery],
        mode: GameMode,
        teams: [TripTeam] = []
    ) -> (discoveries: [GameDiscovery], credits: [GameCredit]) {
        let eligible = outcomeEligible(discoveries)
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(
            mode: mode,
            discoveriesByTarget: Dictionary(grouping: eligible, by: \.targetId),
            teams: teams
        )
        return (eligible, credits)
    }

    /// True when excluding late replays would actually change the input — i.e. this game
    /// received at least one late find.
    static func hasLateReplays(_ discoveries: [GameDiscovery]) -> Bool {
        discoveries.contains { $0.isLateReplay }
    }
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
        let byGameTarget = Dictionary(grouping: discoveries) { d in
            "\(d.gameInstanceId.uuidString)_\(d.targetId)"
        }
        var firstFindCount: [String: Int] = [:]
        for (_, targetDiscoveries) in byGameTarget {
            let summary = ParticipantDiscoveryResolver.summary(discoveries: targetDiscoveries)
            if let firstId = summary.firstFinderParticipantId {
                firstFindCount[firstId, default: 0] += 1
            }
        }
        return firstFindCount
    }
}
