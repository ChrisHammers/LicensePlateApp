//
//  DiscoveryCreditProjectionService.swift
//  LicensePlateApp
//
//  Step 06.5.5 — UI-friendly summary from discoveries and credits; delegates to ParticipantDiscoveryResolver.
//

import Foundation

/// Per-participant score summary for UI (weighted score and credited discovery count).
struct ParticipantScoreSummary: Sendable {
    var participantId: String
    var weightedScore: Double
    var creditedDiscoveryCount: Int
}

/// Per-target discovery summary for UI (first finder and label from ParticipantDiscoveryResolver).
struct TargetDiscoverySummary: Sendable, Identifiable {
    /// Set when aggregating multiple games so the same `targetId` can appear once per game.
    var gameInstanceId: UUID?
    var targetId: String
    var firstFinderParticipantId: String?
    var allFinderParticipantIds: [String]
    var summaryLabel: String

    var id: String {
        let g = gameInstanceId.map(\.uuidString) ?? "_"
        return "\(g)_\(targetId)"
    }
}

/// Full projection result: participant scores and per-target summaries.
struct DiscoveryCreditProjection: Sendable {
    var participantScores: [ParticipantScoreSummary]
    var targetSummaries: [TargetDiscoverySummary]
}

/// Produces UI-friendly summary data from discoveries and credits. Pure logic; no persistence.
/// Uses ParticipantDiscoveryResolver for first-finder and labels; uses credits for weighted scores.
enum DiscoveryCreditProjectionService {

    /// Build projection from discoveries and optional credits. Groups discoveries by targetId for summaries.
    /// - Parameters:
    ///   - discoveries: All discoveries (e.g. for a game instance).
    ///   - credits: Optional precomputed credits; when provided, participant scores use these weights.
    /// - Parameters:
    ///   - gameModeByInstanceId: Per-game `GameMode` for target labels; defaults to collaborative when a game id is missing.
    /// - Returns: Participant score summaries and per-target discovery summaries for UI.
    static func project(
        discoveries: [GameDiscovery],
        credits: [GameCredit]? = nil,
        gameModeByInstanceId: [UUID: GameMode]? = nil
    ) -> DiscoveryCreditProjection {
        let targetSummaries = buildTargetSummaries(discoveries: discoveries, gameModeByInstanceId: gameModeByInstanceId)
        let participantScores = buildParticipantScores(discoveries: discoveries, credits: credits)
        return DiscoveryCreditProjection(
            participantScores: participantScores,
            targetSummaries: targetSummaries
        )
    }

    private static func buildTargetSummaries(
        discoveries: [GameDiscovery],
        gameModeByInstanceId: [UUID: GameMode]?
    ) -> [TargetDiscoverySummary] {
        let byGameTarget = Dictionary(grouping: discoveries) { d in
            "\(d.gameInstanceId.uuidString)_\(d.targetId)"
        }
        return byGameTarget.values.compactMap { targetDiscoveries -> TargetDiscoverySummary? in
            guard let first = targetDiscoveries.first else { return nil }
            let mode = gameModeByInstanceId?[first.gameInstanceId] ?? .collaborative
            let summary = ParticipantDiscoveryResolver.summary(discoveries: targetDiscoveries, gameMode: mode)
            return TargetDiscoverySummary(
                gameInstanceId: first.gameInstanceId,
                targetId: first.targetId,
                firstFinderParticipantId: summary.firstFinderParticipantId,
                allFinderParticipantIds: summary.allFinderParticipantIds,
                summaryLabel: summary.summaryLabel
            )
        }
    }

    private static func buildParticipantScores(
        discoveries: [GameDiscovery],
        credits: [GameCredit]?
    ) -> [ParticipantScoreSummary] {
        let effectiveCredits: [GameCredit]
        if let credits = credits, !credits.isEmpty {
            effectiveCredits = credits
        } else {
            effectiveCredits = discoveries.map { d in
                GameCredit(
                    discoveryId: d.id,
                    participantId: d.participantId,
                    creditType: .full,
                    weight: 1.0
                )
            }
        }
        let byParticipant = Dictionary(grouping: effectiveCredits, by: \.participantId)
        return byParticipant.map { participantId, participantCredits in
            let weightedScore = participantCredits.compactMap(\.weight).reduce(0, +)
            return ParticipantScoreSummary(
                participantId: participantId,
                weightedScore: weightedScore,
                creditedDiscoveryCount: participantCredits.count
            )
        }
    }
}
