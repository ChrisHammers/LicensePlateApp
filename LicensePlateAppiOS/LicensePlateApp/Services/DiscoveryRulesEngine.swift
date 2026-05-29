//
//  DiscoveryRulesEngine.swift
//  LicensePlateApp
//
//  Step 03 — One authoritative rules path for duplicate handling, attribution, and outcomes across solo/collaborative/competitive.
//

import Foundation

/// Centralized engine for discovery submission outcomes and credit resolution.
/// Uses GameModeRulesEngine and GameCreditCalculator; no persistence. Advisory risk remains in RiskAssessmentService (post-append).
enum DiscoveryRulesEngine {

    // MARK: - Write path: evaluate before append

    /// Evaluates a candidate discovery submission. Caller should append the event only when `result.shouldAppendEvent` is true.
    /// - Parameters:
    ///   - mode: Game mode (from GameInstance.commonConfig.gameMode).
    ///   - tripMode: Trip participation derived from `TripSession` roster (`TripSession.mode`). Solo trips must not accept finds from multiple distinct participants for the same target.
    ///   - existingDiscoveriesForTarget: Discoveries already recorded for this target (replay supports multiple finders per target).
    ///   - candidateParticipantId: Participant making the new find.
    ///   - candidateTargetId: Target being found (e.g. region id).
    ///   - gameInstanceId: Game instance id.
    ///   - inputMethod: How the find was made.
    ///   - occurredAt: Time of the find.
    ///   - teams: Game instance teams; used only for `GameCredit.teamId` on credits (not for duplicate rules).
    ///   - riskContext: Optional; if nil, risk flags are empty (risk assessment stays post-append).
    /// - Returns: Outcome, optional risk flags, and credits to assign (nil when rejected or personal_duplicate with no new credit).
    static func evaluateDiscoverySubmission(
        mode: GameMode,
        tripMode: TripMode,
        existingDiscoveriesForTarget: [GameDiscovery],
        candidateParticipantId: String,
        candidateTargetId: String,
        gameInstanceId: UUID,
        inputMethod: FoundRegion.InputMethod,
        occurredAt: Date,
        teams: [TripTeam] = [],
        riskContext: DiscoveryActionContext? = nil
    ) -> DiscoveryEvaluationResult {
        let candidateDiscovery = GameDiscovery(
            id: UUID().uuidString,
            gameInstanceId: gameInstanceId,
            participantId: candidateParticipantId,
            targetId: candidateTargetId,
            discoveredAt: occurredAt,
            inputMethod: inputMethod
        )

        if existingDiscoveriesForTarget.isEmpty {
            let credits = GameCreditCalculator.credits(
                for: mode,
                discovery: candidateDiscovery,
                existingDiscoveriesForTarget: [],
                teams: teams
            )
            return DiscoveryEvaluationResult(
                outcome: .newCredit,
                riskFlags: riskFlags(from: riskContext, discovery: candidateDiscovery),
                creditsToAssign: credits
            )
        }

        let existing = existingDiscoveriesForTarget
        let isSameParticipant = existing.contains { $0.participantId == candidateParticipantId }

        if isSameParticipant {
            return DiscoveryEvaluationResult(
                outcome: .personalDuplicate,
                riskFlags: riskFlags(from: riskContext, discovery: candidateDiscovery),
                creditsToAssign: nil
            )
        }

        // Other participant already found this target.
        if tripMode == .solo {
            // Solo implies a single participant; conflicting attribution is invalid (enforce server-side too).
            return DiscoveryEvaluationResult(
                outcome: .rejectedInvalidParticipant,
                riskFlags: riskFlags(from: riskContext, discovery: candidateDiscovery),
                creditsToAssign: nil
            )
        }

        switch mode {
        case .competitive:
            return DiscoveryEvaluationResult(
                outcome: .rejectedDuplicate,
                riskFlags: riskFlags(from: riskContext, discovery: candidateDiscovery),
                creditsToAssign: nil
            )
        case .collaborative:
            let credits = GameCreditCalculator.credits(
                for: mode,
                discovery: candidateDiscovery,
                existingDiscoveriesForTarget: existing,
                teams: teams
            )
            return DiscoveryEvaluationResult(
                outcome: .sharedDuplicate,
                riskFlags: riskFlags(from: riskContext, discovery: candidateDiscovery),
                creditsToAssign: credits
            )
        }
    }

    // MARK: - Read path: credits for summary

    /// Returns credits for all discoveries using the same rules as the write path (one representative discovery per target, same as current summary logic).
    /// - Parameters:
    ///   - mode: Game mode (from GameInstance.commonConfig.gameMode).
    ///   - discoveriesByTarget: Discoveries grouped by targetId (e.g. from Dictionary(grouping: discoveries, by: \.targetId)).
    ///   - teams: Game instance teams for `GameCredit.teamId` resolution.
    /// - Returns: Flat list of GameCredit (one set per target: first finder for competitive, all finders for collaborative).
    static func creditsForDiscoveries(
        mode: GameMode,
        discoveriesByTarget: [String: [GameDiscovery]],
        teams: [TripTeam] = []
    ) -> [GameCredit] {
        let isShared = GameModeRulesEngine.creditType(for: mode) == .shared
        var allCredits: [GameCredit] = []
        for (_, targetDiscoveries) in discoveriesByTarget {
            let sorted = targetDiscoveries.sorted(by: Self.discoveryCreditOrder)
            guard let discovery = isShared ? sorted.last : sorted.first else { continue }
            let existing = isShared ? Array(sorted.dropLast()) : Array(sorted.dropFirst())
            let credits = GameCreditCalculator.credits(
                for: mode,
                discovery: discovery,
                existingDiscoveriesForTarget: existing,
                teams: teams
            )
            allCredits.append(contentsOf: credits)
        }
        return allCredits
    }

    /// Same ordering as `TripActivityEventDiscoveryReplay` flattened discoveries (client time, server commit, ids).
    static func discoveryCreditOrder(_ a: GameDiscovery, _ b: GameDiscovery) -> Bool {
        GameDiscovery.orderingAscending(a, b)
    }

    private static func riskFlags(from context: DiscoveryActionContext?, discovery: GameDiscovery) -> [RiskFlag] {
        // Risk assessment remains a separate post-append step (RiskAssessmentService); engine focuses on outcome and credits.
        _ = context
        _ = discovery
        return []
    }
}
